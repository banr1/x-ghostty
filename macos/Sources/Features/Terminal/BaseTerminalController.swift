import Cocoa
import SwiftUI
import Combine
import XGhosttyKit

/// A base class for windows that can contain XGhostty windows. This base class implements
/// the bare minimum functionality that every terminal window in XGhostty should implement.
///
/// Usage: Specify this as the base class of your window controller for the window that contains
/// a terminal. The window controller must also be the window delegate OR the window delegate
/// functions on this base class must be called by your own custom delegate. For the terminal
/// view the TerminalView SwiftUI view must be used and this class is the view model and
/// delegate.
///
/// Special considerations to implement:
///
///   - Fullscreen: you must manually listen for the right notification and implement the
///   callback that calls toggleFullscreen on this base class.
///
/// Notably, things this class does NOT implement (not exhaustive):
///
///   - Tabbing, because there are many ways to get tabbed behavior in macOS and we
///   don't want to be opinionated about it.
///   - Window restoration or save state
///   - Window visual styles (such as titlebar colors)
///
/// The primary idea of all the behaviors we don't implement here are that subclasses may not
/// want these behaviors.
class BaseTerminalController: NSWindowController,
                              NSWindowDelegate,
                              TerminalViewDelegate,
                              TerminalViewModel,
                              ClipboardConfirmationViewDelegate,
                              FullscreenDelegate {
    /// The app instance that this terminal view will represent.
    let ghostty: XGhostty.App

    /// The currently focused surface.
    var focusedSurface: XGhostty.SurfaceView? {
        didSet {
            // Cross-group click: surface is in a different group's pane tree, so
            // sync the group layer without moving the AppKit first responder (it's correct already).
            if let surface = focusedSurface, !surfaceTree.contains(surface) {
                if let targetGroupID = workspace.state.groups.first(where: {
                    $0.value.paneTree.find(id: surface.id) != nil
                })?.key {
                    workspace.switchFocusedGroup(
                        to: targetGroupID,
                        savingOutgoingPaneTree: surfaceTree)
                    surfaceTree = workspace.focusedPaneTree
                }
            }

            syncFocusToSurfaceTree()
            workspace.setFocusedSurface(focusedSurface.map { SurfaceID(rawValue: $0.id) })
        }
    }

    /// The tree of splits within this terminal window.
    @Published var surfaceTree: SplitTree<XGhostty.SurfaceView> = .init() {
        didSet { surfaceTreeDidChange(from: oldValue, to: surfaceTree) }
    }

    /// The group layer wrapping `surfaceTree`. In Phase 0 this mirrors the
    /// focused group's pane tree; `surfaceTree` remains the source of truth for
    /// rendering, actions and Combine observation. See `SPEC.md` §15 Phase 0.
    private(set) var workspace = WorkspaceModel()

    /// This can be set to show/hide the command palette.
    @Published var commandPaletteIsShowing: Bool = false

    /// Set if the terminal view should show the update overlay.
    @Published var updateOverlayIsVisible: Bool = false

    /// True when any surface in this controller currently has an active bell.
    @Published private(set) var bell: Bool = false

    /// Whether the terminal surface should focus when the mouse is over it.
    var focusFollowsMouse: Bool {
        self.derivedConfig.focusFollowsMouse
    }

    /// Non-nil when an alert is active so we don't overlap multiple.
    private var alert: NSAlert?

    /// The clipboard confirmation window, if shown.
    private var clipboardConfirmation: ClipboardConfirmationController?

    /// Fullscreen state management.
    private(set) var fullscreenStyle: FullscreenStyle?

    /// Event monitor (see individual events for why)
    private var eventMonitor: Any?

    /// The previous frame information from the window
    private var savedFrame: SavedFrame?

    /// Cache previously applied appearance to avoid unnecessary updates
    private var appliedColorScheme: xghostty_color_scheme_e?

    /// The configuration derived from the XGhostty config so we don't need to rely on references.
    private var derivedConfig: DerivedConfig

    /// Track whether background is forced opaque (true) or using config transparency (false)
    var isBackgroundOpaque: Bool = false

    /// The cancellables related to our focused surface.
    private var focusedSurfaceCancellables: Set<AnyCancellable> = []

    /// Cancellable for aggregating bell state across all surfaces in this controller.
    private var bellStateCancellable: AnyCancellable?

    /// Cancellable for invalidating restorable state on group-layer changes.
    private var workspaceStateCancellable: AnyCancellable?

    /// An override title for the tab/window set by the user via prompt_tab_title.
    /// When set, this takes precedence over the computed title from the terminal.
    var titleOverride: String? {
        didSet { applyTitleToWindow() }
    }

    /// The last computed title from the focused surface (without the override).
    private var lastComputedTitle: String = "👻"

    /// The time that undo/redo operations that contain running ptys are valid for.
    var undoExpiration: Duration {
        ghostty.config.undoTimeout
    }

    /// The undo manager for this controller is the undo manager of the window,
    /// which we set via the delegate method.
    override var undoManager: ExpiringUndoManager? {
        // This should be set via the delegate method windowWillReturnUndoManager
        if let result = window?.undoManager as? ExpiringUndoManager {
            return result
        }

        // If the window one isn't set, we fallback to our global one.
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            return appDelegate.undoManager
        }

        return nil
    }

    struct SavedFrame {
        let window: NSRect
        let screen: NSRect
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported for this view")
    }

    init(_ ghostty: XGhostty.App,
         baseConfig base: XGhostty.SurfaceConfiguration? = nil,
         surfaceTree tree: SplitTree<XGhostty.SurfaceView>? = nil,
         workspace restoredWorkspace: WorkspaceState? = nil
    ) {
        self.ghostty = ghostty
        self.derivedConfig = DerivedConfig(ghostty.config)

        super.init(window: nil)

        // Initialize our initial surface.
        guard let xghostty_app = ghostty.app else { preconditionFailure("app must be loaded") }

        if let restoredWorkspace {
            // Restore the full group layer (Phase 6 / `SPEC.md` §12). Each pane
            // was decoded as a fresh shell; the focused group's pane tree becomes
            // the `surfaceTree` source of truth and the rest of the groups render
            // from the workspace. Setting `surfaceTree` first is a no-op mirror
            // (the default empty model has no focused group) before we install
            // the restored model whose focused group already holds this tree.
            let model = WorkspaceModel(restoredWorkspace)
            self.surfaceTree = model.focusedPaneTree
            self.workspace = model
        } else {
            self.surfaceTree = tree ?? .init(view: XGhostty.SurfaceView(xghostty_app, baseConfig: base))

            // Wrap the initial pane tree into the group layer. Phase 0 keeps a
            // single default group whose pane tree mirrors `surfaceTree`.
            self.workspace = WorkspaceModel(wrapping: self.surfaceTree)
        }

        // Persist state-only group-layer mutations. `resize_group` /
        // `equalize_groups` / `rename_group` (both the inline editor and the
        // `set_group_title` action) change `workspace.state` without touching
        // `surfaceTree`, so they never reach `surfaceTreeDidChange`'s
        // `invalidateRestorableState`. Mirror that hook on the group layer's
        // source of truth so canonical group ratios and names survive relaunch.
        // (`dropFirst` skips the initial value emitted on subscription.)
        workspaceStateCancellable = workspace.$state
            .dropFirst()
            .sink { [weak self] _ in self?.invalidateRestorableState() }

        // Setup our bell state for the window
        setupBellNotificationPublisher()

        // Setup our notifications for behaviors
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(onConfirmClipboardRequest),
            name: XGhostty.Notification.confirmClipboard,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(didChangeScreenParametersNotification),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(ghosttyConfigDidChangeBase(_:)),
            name: .ghosttyConfigDidChange,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(ghosttyCommandPaletteDidToggle(_:)),
            name: .ghosttyCommandPaletteDidToggle,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(ghosttyMaximizeDidToggle(_:)),
            name: .ghosttyMaximizeDidToggle,
            object: nil)

        // Splits
        center.addObserver(
            self,
            selector: #selector(ghosttyDidCloseSurface(_:)),
            name: XGhostty.Notification.ghosttyCloseSurface,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(ghosttyDidNewSplit(_:)),
            name: XGhostty.Notification.ghosttyNewSplit,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(ghosttyDidNewGroupSplit(_:)),
            name: XGhostty.Notification.ghosttyNewGroupSplit,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(ghosttyDidRenameGroup(_:)),
            name: XGhostty.Notification.ghosttyRenameGroup,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(ghosttyDidSetGroupTitle(_:)),
            name: XGhostty.Notification.ghosttySetGroupTitle,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(ghosttyDidGotoGroup(_:)),
            name: XGhostty.Notification.ghosttyGotoGroup,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(ghosttyDidResizeGroup(_:)),
            name: XGhostty.Notification.ghosttyResizeGroup,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(ghosttyDidEqualizeGroups(_:)),
            name: XGhostty.Notification.ghosttyEqualizeGroups,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(ghosttyDidToggleGroupZoom(_:)),
            name: XGhostty.Notification.ghosttyToggleGroupZoom,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(ghosttyDidHideGroup(_:)),
            name: XGhostty.Notification.ghosttyHideGroup,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(ghosttyDidShowGroup(_:)),
            name: XGhostty.Notification.ghosttyShowGroup,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(ghosttyDidCloseGroup(_:)),
            name: XGhostty.Notification.ghosttyCloseGroup,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(ghosttyDidEqualizeSplits(_:)),
            name: XGhostty.Notification.didEqualizeSplits,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(ghosttyDidFocusSplit(_:)),
            name: XGhostty.Notification.ghosttyFocusSplit,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(ghosttyDidToggleSplitZoom(_:)),
            name: XGhostty.Notification.didToggleSplitZoom,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(ghosttyDidResizeSplit(_:)),
            name: XGhostty.Notification.didResizeSplit,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(ghosttyDidPresentTerminal(_:)),
            name: XGhostty.Notification.ghosttyPresentTerminal,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(ghosttySurfaceDragEndedNoTarget(_:)),
            name: .ghosttySurfaceDragEndedNoTarget,
            object: nil)

        // Listen for local events that we need to know of outside of
        // single surface handlers.
        self.eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.flagsChanged]
        ) { [weak self] event in self?.localEventHandler(event) }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        undoManager?.removeAllActions(withTarget: self)
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    // MARK: Methods

    /// Create a new split.
    @discardableResult
    func newSplit(
        at oldView: XGhostty.SurfaceView,
        direction: SplitTree<XGhostty.SurfaceView>.NewDirection,
        baseConfig config: XGhostty.SurfaceConfiguration? = nil
    ) -> XGhostty.SurfaceView? {
        // We can only create new splits for surfaces in our tree.
        guard surfaceTree.root?.node(view: oldView) != nil else { return nil }

        // Create a new surface view
        guard let xghostty_app = ghostty.app else { return nil }
        let newView = XGhostty.SurfaceView(xghostty_app, baseConfig: config)

        // Do the split
        let newTree: SplitTree<XGhostty.SurfaceView>
        do {
            newTree = try surfaceTree.inserting(
                view: newView,
                at: oldView,
                direction: direction)
        } catch {
            // If splitting fails for any reason (it should not), then we just log
            // and return. The new view we created will be deinitialized and its
            // no big deal.
            XGhostty.logger.warning("failed to insert split: \(error, privacy: .public)")
            return nil
        }

        replaceSurfaceTree(
            newTree,
            moveFocusTo: newView,
            moveFocusFrom: oldView,
            undoAction: "New Split")

        return newView
    }

    /// Create a new group as a sibling of the focused group, with a single
    /// initial pane, and move focus into it (`SPEC.md` §11.1).
    ///
    /// Registers a group-aware undo ("New Group"): because the focused group
    /// switches here, `replaceSurfaceTree`'s `surfaceTree`-only undo can't be
    /// reused (it would mirror the old panes into the new group). Instead we
    /// snapshot the whole `WorkspaceState` before/after and register a
    /// `registerWorkspaceUndo` that restores them atomically.
    @discardableResult
    func newGroupSplit(
        at oldView: XGhostty.SurfaceView,
        direction: SplitTree<GroupRef>.NewDirection,
        baseConfig config: XGhostty.SurfaceConfiguration? = nil
    ) -> XGhostty.SurfaceView? {
        // The anchor surface must be in our (the focused group's) tree, and we
        // need a focused group to anchor the new sibling against.
        guard surfaceTree.root?.node(view: oldView) != nil else { return nil }
        guard workspace.state.focusedGroup != nil else { return nil }
        guard let xghostty_app = ghostty.app else { return nil }

        // Build the new group's single initial pane.
        let newView = XGhostty.SurfaceView(xghostty_app, baseConfig: config)
        let newPaneTree = SplitTree<XGhostty.SurfaceView>(view: newView)

        // Name and assemble the new group, focused on its initial pane.
        let now = Date()
        let existingNames = Set(workspace.state.groups.values.map(\.name))
        let newGroup = GroupState(
            id: GroupID(),
            name: GroupNameGenerator.make(existing: existingNames),
            paneTree: newPaneTree,
            focusedSurface: SurfaceID(rawValue: newView.id),
            createdAt: now,
            lastFocusedAt: now)

        // Snapshot before the switch so the undo can restore the outgoing group.
        let before = workspace.state

        // Single group-switch point: persist the outgoing pane tree, insert the
        // new group next to the focused one, and switch focus (un-zooms first).
        do {
            try workspace.openNewGroup(
                newGroup,
                direction: direction,
                savingOutgoingPaneTree: surfaceTree)
        } catch {
            XGhostty.logger.warning("failed to open new group split: \(error, privacy: .public)")
            return nil
        }

        // Swap the source-of-truth pane tree to the new group's tree. The
        // resulting `surfaceTreeDidChange` mirrors it back into the now-focused
        // new group (a no-op) and re-renders the workspace.
        surfaceTree = newPaneTree
        DispatchQueue.main.async {
            XGhostty.moveFocus(to: newView, from: oldView)
        }

        // The post-mirror state is the redo target; it retains the new pane.
        registerWorkspaceUndo("New Group", undo: before, redo: workspace.state)

        return newView
    }

    /// Move focus to a surface view.
    func focusSurface(_ view: XGhostty.SurfaceView) {
        // Check if target surface is in our tree
        guard surfaceTree.contains(view) else { return }

        // Move focus to the target surface and activate the window/app
        DispatchQueue.main.async {
            XGhostty.moveFocus(to: view)
            view.window?.makeKeyAndOrderFront(nil)
            if !NSApp.isActive {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    /// Called when the surfaceTree variable changed.
    ///
    /// Subclasses should call super first.
    func surfaceTreeDidChange(from: SplitTree<XGhostty.SurfaceView>, to: SplitTree<XGhostty.SurfaceView>) {
        // Mirror the focused group's pane tree into the group layer (Phase 0).
        // `surfaceTree` is the source of truth; the workspace follows it.
        workspace.replaceFocusedPaneTree(to, focusedSurface: focusedSurface)

        // If our surface tree becomes empty then we have no focused surface.
        if to.isEmpty {
            focusedSurface = nil
        }
        syncSurfaceTreeOcclusionState()
    }

    /// Update all surfaces with the focus state. This ensures that libghostty has an accurate view about
    /// what surface is focused. This must be called whenever a surface OR window changes focus.
    func syncFocusToSurfaceTree() {
        for surfaceView in surfaceTree {
            // Our focus state requires that this window is key and our currently
            // focused surface is the surface in this view.
            let focused: Bool = (window?.isKeyWindow ?? false) &&
                surfaceView == focusedSurface &&
                surfaceView.isFirstResponder
            surfaceView.focusDidChange(focused)
        }
    }

    // Call this whenever the frame changes
    private func windowFrameDidChange() {
        // We need to update our saved frame information in case of monitor
        // changes (see didChangeScreenParameters notification).
        savedFrame = nil
        guard let window, let screen = window.screen else { return }
        savedFrame = .init(window: window.frame, screen: screen.visibleFrame)
    }

    func confirmCloseAsync(
        messageText: String,
        informativeText: String,
        confirmButtonTitle: String = "Close",
    ) async -> NSApplication.ModalResponse? {
        // If we already have an alert, we need to wait for that one.
        guard alert == nil else { return nil }

        // If there is no window to attach the modal then we assume success
        // since we'll never be able to show the modal.
        guard let window else {
            return .OK
        }

        // If we need confirmation by any, show one confirmation for all windows
        // in the tab group.
        let alert = NSAlert()
        alert.messageText = messageText
        alert.informativeText = informativeText
        alert.addButton(withTitle: confirmButtonTitle)
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        // Store our alert so we only ever show one.
        self.alert = alert
        defer {
            // This is important so that we avoid losing focus when Stage
            // Manager is used (#8336)
            alert.window.orderOut(nil)
            self.alert = nil
        }
        return await alert.beginSheetModal(for: window)
    }

    func confirmClose(
        messageText: String,
        informativeText: String,
        confirmButtonTitle: String = "Close",
        completion: @escaping () -> Void
    ) {
        Task {
            guard let response = await confirmCloseAsync(messageText: messageText, informativeText: informativeText, confirmButtonTitle: confirmButtonTitle) else {
                completion()
                return
            }
            if [.alertFirstButtonReturn, .OK].contains(response) {
                completion()
            }
        }
    }

    /// Prompt the user to change the tab/window title.
    func promptTabTitle() {
        guard let window else { return }

        let alert = NSAlert()
        alert.messageText = "Change Tab Title"
        alert.informativeText = "Leave blank to restore the default."
        alert.alertStyle = .informational

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
        textField.stringValue = titleOverride ?? window.title
        alert.accessoryView = textField

        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        alert.window.initialFirstResponder = textField

        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            guard response == .alertFirstButtonReturn else { return }

            let newTitle = textField.stringValue
            if newTitle.isEmpty {
                self.titleOverride = nil
            } else {
                self.titleOverride = newTitle
            }
        }
    }

    /// Close a surface from a view.
    func closeSurface(
        _ view: XGhostty.SurfaceView,
        withConfirmation: Bool = true
    ) {
        guard let node = surfaceTree.root?.node(view: view) else { return }
        closeSurface(node, withConfirmation: withConfirmation)
    }

    /// Close a surface node (which may contain splits), requesting confirmation if necessary.
    ///
    /// This will also insert the proper undo stack information in.
    func closeSurface(
        _ node: SplitTree<XGhostty.SurfaceView>.Node,
        withConfirmation: Bool = true
    ) {
        // This node must be part of our tree
        guard surfaceTree.contains(node) else { return }

        // If the child process is not alive, then we exit immediately
        guard withConfirmation else {
            removeSurfaceNode(node)
            return
        }

        // Confirm close. We use an NSAlert instead of a SwiftUI confirmationDialog
        // due to SwiftUI bugs (see XGhostty #560). To repeat from #560, the bug is that
        // confirmationDialog allows the user to Cmd-W close the alert, but when doing
        // so SwiftUI does not update any of the bindings to note that window is no longer
        // being shown, and provides no callback to detect this.
        confirmClose(
            messageText: "Close Terminal?",
            informativeText: "The terminal still has a running process. If you close the terminal the process will be killed."
        ) { [weak self] in
            if let self {
                self.removeSurfaceNode(node)
            }
        }
    }

    // MARK: Split Tree Management

    /// Find the next surface to focus when a node is being closed.
    /// Goes to previous split unless we're the leftmost leaf, then goes to next.
    private func findNextFocusTargetAfterClosing(node: SplitTree<XGhostty.SurfaceView>.Node) -> XGhostty.SurfaceView? {
        guard let root = surfaceTree.root else { return nil }

        // If we're the leftmost, then we move to the next surface after closing.
        // Otherwise, we move to the previous.
        if root.leftmostLeaf() == node.leftmostLeaf() {
            return surfaceTree.focusTarget(for: .next, from: node)
        } else {
            return surfaceTree.focusTarget(for: .previous, from: node)
        }
    }

    /// Remove a node from the surface tree and move focus appropriately.
    ///
    /// This also updates the undo manager to support restoring this node.
    ///
    /// This does no confirmation and assumes confirmation is already done.
    private func removeSurfaceNode(_ node: SplitTree<XGhostty.SurfaceView>.Node) {
        // Move focus if the closed surface was focused and we have a next target
        let nextFocus: XGhostty.SurfaceView? = if node.contains(
            where: { $0 == focusedSurface }
        ) {
            findNextFocusTargetAfterClosing(node: node)
        } else {
            nil
        }

        replaceSurfaceTree(
            surfaceTree.removing(node),
            // When a non-focused surface is removed and this window stays as the key window,
            // we should refocus the `focusedSurface` to make sure the window's firstResponder remains as it is.
            //
            // This is a weird workaround, since `resignFirstResponder` wasn't called on `focusedSurface` after drag,
            // but the first responder became the window itself.
            moveFocusTo: nextFocus ?? focusedSurface,
            undoAction: "Close Terminal"
        )
    }

    func replaceSurfaceTree(
        _ newTree: SplitTree<XGhostty.SurfaceView>,
        moveFocusTo newView: XGhostty.SurfaceView? = nil,
        moveFocusFrom oldView: XGhostty.SurfaceView? = nil,
        undoAction: String? = nil
    ) {
        // Setup our new split tree
        let oldTree = surfaceTree
        surfaceTree = newTree
        if let newView {
            DispatchQueue.main.async {
                XGhostty.moveFocus(to: newView, from: oldView)
            }
        }

        // Setup our undo
        guard let undoManager else { return }
        if let undoAction {
            undoManager.setActionName(undoAction)
        }

        // The group this pane edit belongs to. A pane undo only ever restores
        // `surfaceTree`, which `surfaceTreeDidChange` mirrors into whatever group
        // is focused *at replay time*. If the focused group has since changed,
        // replaying would mirror this group's panes into the wrong group and
        // corrupt the layer (the group-aware undo cross-cutting task). Capturing
        // the group here and skipping when it differs is the corruption guard —
        // pane undos stay valid across round-trip group switches (the guard
        // passes again once we return) but no-op while focused elsewhere.
        let groupID = workspace.state.focusedGroup

        undoManager.registerUndo(
            withTarget: self,
            expiresAfter: undoExpiration
        ) { target in
            guard target.workspace.state.focusedGroup == groupID else { return }

            target.surfaceTree = oldTree
            if let oldView {
                DispatchQueue.main.async {
                    XGhostty.moveFocus(to: oldView, from: target.focusedSurface)
                }
            }

            undoManager.registerUndo(
                withTarget: target,
                expiresAfter: target.undoExpiration
            ) { target in
                guard target.workspace.state.focusedGroup == groupID else { return }

                target.replaceSurfaceTree(
                    newTree,
                    moveFocusTo: newView,
                    moveFocusFrom: target.focusedSurface,
                    undoAction: undoAction)
            }
        }
    }

    // MARK: Group-aware undo (cross-cutting task)

    /// Restore a captured `WorkspaceState` snapshot and re-sync the
    /// source-of-truth `surfaceTree` to the restored focused group.
    ///
    /// Order is load-bearing: the model is restored *first* so `focusedGroup` is
    /// correct before `surfaceTree` is assigned — its `surfaceTreeDidChange`
    /// mirror then writes into the restored group, not a stale one. The mirror
    /// reads the possibly-stale `self.focusedSurface`, but `replaceFocusedPaneTree`
    /// ignores a surface that isn't in the restored tree and keeps the snapshot's
    /// stored focus, so the stale value is harmless.
    private func restoreWorkspaceState(_ snapshot: WorkspaceState) {
        workspace.restoreState(snapshot)
        let focus = workspace.focusedGroupState?.focusedSurface
        surfaceTree = workspace.focusedPaneTree
        moveKeyboardFocus(toGroupSurface: focus)
    }

    /// Register a group-aware undo that swaps between two whole-`WorkspaceState`
    /// snapshots. Unlike `replaceSurfaceTree`'s undo (which restores only
    /// `surfaceTree`), this restores `focusedGroup` / `canonicalGroupTree` /
    /// `groups` together, so it stays correct across focused-group switches.
    ///
    /// The snapshots are value-type copies that retain the live `SurfaceView`s,
    /// so an undo of `close_group` keeps the closed group's processes alive for
    /// the `undoExpiration` window (mirroring `close_surface` undo), and a redo of
    /// `new_group_split` can restore the new pane the post-mutation snapshot
    /// retains. Symmetric ping-pong: each direction re-registers its inverse.
    private func registerWorkspaceUndo(
        _ actionName: String,
        undo undoState: WorkspaceState,
        redo redoState: WorkspaceState
    ) {
        guard let undoManager else { return }
        undoManager.setActionName(actionName)
        undoManager.registerUndo(
            withTarget: self,
            expiresAfter: undoExpiration
        ) { target in
            target.restoreWorkspaceState(undoState)
            target.registerWorkspaceUndo(actionName, undo: redoState, redo: undoState)
        }
    }

    // MARK: Notifications

    @objc private func didChangeScreenParametersNotification(_ notification: Notification) {
        // If we have a window that is visible and it is outside the bounds of the
        // screen then we clamp it back to within the screen.
        guard let window else { return }
        guard window.isVisible else { return }

        // We ignore fullscreen windows because macOS automatically resizes
        // those back to the fullscreen bounds.
        guard !window.styleMask.contains(.fullScreen) else { return }

        guard let screen = window.screen else { return }
        let visibleFrame = screen.visibleFrame
        var newFrame = window.frame

        // Clamp width/height
        if newFrame.size.width > visibleFrame.size.width {
            newFrame.size.width = visibleFrame.size.width
        }
        if newFrame.size.height > visibleFrame.size.height {
            newFrame.size.height = visibleFrame.size.height
        }

        // Ensure the window is on-screen. We only do this if the previous frame
        // was also on screen. If a user explicitly wanted their window off screen
        // then we let it stay that way.
        x: if newFrame.origin.x < visibleFrame.origin.x {
            if let savedFrame, savedFrame.window.origin.x < savedFrame.screen.origin.x {
                break x
            }

            newFrame.origin.x = visibleFrame.origin.x
        }
        y: if newFrame.origin.y < visibleFrame.origin.y {
            if let savedFrame, savedFrame.window.origin.y < savedFrame.screen.origin.y {
                break y
            }

            newFrame.origin.y = visibleFrame.origin.y
        }

        // Apply the new window frame
        window.setFrame(newFrame, display: true)
    }

    @objc private func ghosttyConfigDidChangeBase(_ notification: Notification) {
        // We only care if the configuration is a global configuration, not a
        // surface-specific one.
        guard notification.object == nil else { return }

        // Get our managed configuration object out
        guard let config = notification.userInfo?[
            Notification.Name.GhosttyConfigChangeKey
        ] as? XGhostty.Config else { return }

        // Update our derived config
        self.derivedConfig = DerivedConfig(config)
    }

    @objc private func ghosttyCommandPaletteDidToggle(_ notification: Notification) {
        guard let surfaceView = notification.object as? XGhostty.SurfaceView else { return }
        guard surfaceTree.contains(surfaceView) else { return }
        toggleCommandPalette(nil)
    }

    @objc private func ghosttyMaximizeDidToggle(_ notification: Notification) {
        guard let window else { return }
        guard let surfaceView = notification.object as? XGhostty.SurfaceView else { return }
        guard surfaceTree.contains(surfaceView) else { return }
        window.zoom(nil)
    }

    @objc private func ghosttyDidCloseSurface(_ notification: Notification) {
        guard let target = notification.object as? XGhostty.SurfaceView else { return }
        guard let node = surfaceTree.root?.node(view: target) else { return }

        // §11.10: closing the last pane of a group is really closing the group.
        // When this close would empty the focused group's pane tree *and* there
        // are sibling groups, escalate to `close_group` (which switches focus to
        // a sibling). With only one group we fall through to the existing
        // close_surface path, which already handles last-pane → tab/window close
        // with the familiar "Close Terminal?" confirmation (§18.5).
        if workspace.state.groups.count > 1, surfaceTree.removing(node).isEmpty {
            closeFocusedGroup()
            return
        }

        closeSurface(
            node,
            withConfirmation: (notification.userInfo?["process_alive"] as? Bool) ?? false)
    }

    @objc private func ghosttyDidNewSplit(_ notification: Notification) {
        // The target must be within our tree
        guard let oldView = notification.object as? XGhostty.SurfaceView else { return }
        guard surfaceTree.root?.node(view: oldView) != nil else { return }

        // Notification must contain our base config
        let configAny = notification.userInfo?[XGhostty.Notification.NewSurfaceConfigKey]
        let config = configAny as? XGhostty.SurfaceConfiguration

        // Determine our desired direction
        guard let directionAny = notification.userInfo?["direction"] else { return }
        guard let direction = directionAny as? xghostty_action_split_direction_e else { return }
        let splitDirection: SplitTree<XGhostty.SurfaceView>.NewDirection
        switch direction {
        case XGHOSTTY_SPLIT_DIRECTION_RIGHT: splitDirection = .right
        case XGHOSTTY_SPLIT_DIRECTION_LEFT: splitDirection = .left
        case XGHOSTTY_SPLIT_DIRECTION_DOWN: splitDirection = .down
        case XGHOSTTY_SPLIT_DIRECTION_UP: splitDirection = .up
        default: return
        }

        newSplit(at: oldView, direction: splitDirection, baseConfig: config)
    }

    @objc private func ghosttyDidNewGroupSplit(_ notification: Notification) {
        // The anchor surface must be within our tree.
        guard let oldView = notification.object as? XGhostty.SurfaceView else { return }
        guard surfaceTree.root?.node(view: oldView) != nil else { return }

        // Notification must contain our base config.
        let configAny = notification.userInfo?[XGhostty.Notification.NewSurfaceConfigKey]
        let config = configAny as? XGhostty.SurfaceConfiguration

        // Determine the direction the new group should be placed in.
        guard let directionAny = notification.userInfo?["direction"] else { return }
        guard let direction = directionAny as? xghostty_action_split_direction_e else { return }
        let splitDirection: SplitTree<GroupRef>.NewDirection
        switch direction {
        case XGHOSTTY_SPLIT_DIRECTION_RIGHT: splitDirection = .right
        case XGHOSTTY_SPLIT_DIRECTION_LEFT: splitDirection = .left
        case XGHOSTTY_SPLIT_DIRECTION_DOWN: splitDirection = .down
        case XGHOSTTY_SPLIT_DIRECTION_UP: splitDirection = .up
        default: return
        }

        newGroupSplit(at: oldView, direction: splitDirection, baseConfig: config)
    }

    @objc private func ghosttyDidRenameGroup(_ notification: Notification) {
        // The triggering surface must be within our (focused group's) tree.
        guard let view = notification.object as? XGhostty.SurfaceView else { return }
        guard surfaceTree.contains(view) else { return }

        // `rename_group` targets the focused group; enter inline-rename mode.
        workspace.beginRenamingFocusedGroup()
    }

    @objc private func ghosttyDidSetGroupTitle(_ notification: Notification) {
        guard let view = notification.object as? XGhostty.SurfaceView else { return }
        guard surfaceTree.contains(view) else { return }
        guard let title = notification.userInfo?["title"] as? String else { return }
        guard let id = workspace.state.focusedGroup else { return }

        // `set_group_title:<name>` sets the focused group's name directly.
        workspace.renameGroup(id, to: title)
    }

    @objc private func ghosttyDidGotoGroup(_ notification: Notification) {
        // The triggering surface must be within our (focused group's) tree.
        guard let view = notification.object as? XGhostty.SurfaceView else { return }
        guard surfaceTree.contains(view) else { return }

        guard let direction = notification.userInfo?[
            XGhostty.Notification.GroupDirectionKey] as? XGhostty.SplitFocusDirection else { return }

        // Resolve the visible neighbor group in that direction (`SPEC.md` §11.3)
        // and reuse the label-click focus switch, which restores the target
        // group's last-focused pane.
        let treeDirection: SplitTree<GroupRef>.FocusDirection = direction.toSplitTreeFocusDirection()
        guard let target = workspace.gotoGroupTarget(treeDirection) else { return }
        focusGroup(target)
    }

    @objc private func ghosttyDidResizeGroup(_ notification: Notification) {
        // The triggering surface must be within our (focused group's) tree.
        guard let view = notification.object as? XGhostty.SurfaceView else { return }
        guard surfaceTree.contains(view) else { return }

        guard let direction = notification.userInfo?[
            XGhostty.Notification.ResizeGroupDirectionKey] as? XGhostty.SplitResizeDirection else { return }
        guard let amount = notification.userInfo?[
            XGhostty.Notification.ResizeGroupAmountKey] as? UInt16 else { return }

        let spatialDirection: SplitTree<GroupRef>.Spatial.Direction
        switch direction {
        case .up: spatialDirection = .up
        case .down: spatialDirection = .down
        case .left: spatialDirection = .left
        case .right: spatialDirection = .right
        }

        // Convert the pixel amount to a normalized ratio delta against the
        // workspace's content area (the region all visible groups divide). This
        // is exact for a single top-level group split (the common 2-group case)
        // and a graceful approximation for nested group splits, where the LCA
        // split's container is smaller — the divider simply moves a little less
        // than `amount`px. `adjustRatio` clamps the result to [0.1, 0.9].
        let size = window?.contentView?.bounds.size ?? surfaceTree.viewBounds()
        let dimension: CGFloat = switch spatialDirection {
        case .left, .right: size.width
        case .up, .down: size.height
        }
        guard dimension > 0 else { return }
        let ratioDelta = Double(amount) / Double(dimension)

        workspace.resizeFocusedGroup(spatialDirection, ratioDelta: ratioDelta)
    }

    @objc private func ghosttyDidEqualizeGroups(_ notification: Notification) {
        // The triggering surface must be within our (focused group's) tree.
        guard let view = notification.object as? XGhostty.SurfaceView else { return }
        guard surfaceTree.contains(view) else { return }

        workspace.equalizeGroups()
    }

    @objc private func ghosttyDidToggleGroupZoom(_ notification: Notification) {
        // The triggering surface must be within our (focused group's) tree.
        guard let view = notification.object as? XGhostty.SurfaceView else { return }
        guard surfaceTree.contains(view) else { return }

        // Toggle group zoom; rendering reacts via `effectiveVisibleGroupTree`
        // (`SPEC.md` §11.6). The focused group stays focused, so `surfaceTree`
        // is untouched. Toggling reshapes the group view tree (split↔single
        // leaf), which re-hosts the same surface views, so re-assert keyboard
        // focus on the triggering surface (mirrors `ghosttyDidToggleSplitZoom`).
        workspace.toggleGroupZoom()
        window?.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async {
            XGhostty.moveFocus(to: view)
        }
    }

    @objc private func ghosttyDidHideGroup(_ notification: Notification) {
        // The triggering surface must be within our (focused group's) tree.
        guard let view = notification.object as? XGhostty.SurfaceView else { return }
        guard surfaceTree.contains(view) else { return }

        hideFocusedGroup()
    }

    @objc private func ghosttyDidShowGroup(_ notification: Notification) {
        // The triggering surface must be within our (focused group's) tree.
        guard let view = notification.object as? XGhostty.SurfaceView else { return }
        guard surfaceTree.contains(view) else { return }

        guard let name = notification.userInfo?[
            XGhostty.Notification.ShowGroupNameKey] as? String else { return }
        guard let id = workspace.hiddenGroupID(named: name) else { return }
        showGroup(id)
    }

    @objc private func ghosttyDidCloseGroup(_ notification: Notification) {
        // The triggering surface must be within our (focused group's) tree.
        guard let view = notification.object as? XGhostty.SurfaceView else { return }
        guard surfaceTree.contains(view) else { return }

        closeFocusedGroup()
    }

    @objc private func ghosttyDidEqualizeSplits(_ notification: Notification) {
        guard let target = notification.object as? XGhostty.SurfaceView else { return }

        // Check if target surface is in current controller's tree
        guard surfaceTree.contains(target) else { return }

        // Equalize the splits
        surfaceTree = surfaceTree.equalized()
    }

    @objc private func ghosttyDidFocusSplit(_ notification: Notification) {
        // The target must be within our tree
        guard let target = notification.object as? XGhostty.SurfaceView else { return }
        guard surfaceTree.root?.node(view: target) != nil else { return }

        // Get the direction from the notification
        guard let directionAny = notification.userInfo?[XGhostty.Notification.SplitDirectionKey] else { return }
        guard let direction = directionAny as? XGhostty.SplitFocusDirection else { return }

        // Find the node for the target surface
        guard let targetNode = surfaceTree.root?.node(view: target) else { return }

        // Find the next surface to focus
        guard let nextSurface = surfaceTree.focusTarget(for: direction.toSplitTreeFocusDirection(), from: targetNode) else {
            return
        }

        if surfaceTree.zoomed != nil {
            if derivedConfig.splitPreserveZoom.contains(.navigation) {
                surfaceTree = SplitTree(
                    root: surfaceTree.root,
                    zoomed: surfaceTree.root?.node(view: nextSurface))
            } else {
                surfaceTree = SplitTree(root: surfaceTree.root, zoomed: nil)
            }
        }

        // Move focus to the next surface
        DispatchQueue.main.async {
            XGhostty.moveFocus(to: nextSurface, from: target)
        }
    }

    @objc private func ghosttyDidToggleSplitZoom(_ notification: Notification) {
        // The target must be within our tree
        guard let target = notification.object as? XGhostty.SurfaceView else { return }
        guard let targetNode = surfaceTree.root?.node(view: target) else { return }

        // Toggle the zoomed state
        if surfaceTree.zoomed == targetNode {
            // Already zoomed, unzoom it
            surfaceTree = SplitTree(root: surfaceTree.root, zoomed: nil)
        } else {
            // We require that the split tree have splits
            guard surfaceTree.isSplit else { return }

            // Not zoomed or different node zoomed, zoom this node
            surfaceTree = SplitTree(root: surfaceTree.root, zoomed: targetNode)
        }

        // Move focus to our window. Importantly this ensures that if we click the
        // reset zoom button in a tab bar of an unfocused tab that we become focused.
        window?.makeKeyAndOrderFront(nil)

        // Ensure focus stays on the target surface. We lose focus when we do
        // this so we need to grab it again.
        DispatchQueue.main.async {
            XGhostty.moveFocus(to: target)
        }
    }

    @objc private func ghosttyDidResizeSplit(_ notification: Notification) {
        // The target must be within our tree
        guard let target = notification.object as? XGhostty.SurfaceView else { return }
        guard let targetNode = surfaceTree.root?.node(view: target) else { return }

        // Extract direction and amount from notification
        guard let directionAny = notification.userInfo?[XGhostty.Notification.ResizeSplitDirectionKey] else { return }
        guard let direction = directionAny as? XGhostty.SplitResizeDirection else { return }

        guard let amountAny = notification.userInfo?[XGhostty.Notification.ResizeSplitAmountKey] else { return }
        guard let amount = amountAny as? UInt16 else { return }

        // Convert XGhostty.SplitResizeDirection to SplitTree.Spatial.Direction
        let spatialDirection: SplitTree<XGhostty.SurfaceView>.Spatial.Direction
        switch direction {
        case .up: spatialDirection = .up
        case .down: spatialDirection = .down
        case .left: spatialDirection = .left
        case .right: spatialDirection = .right
        }

        // Use viewBounds for the spatial calculation bounds
        let bounds = CGRect(origin: .zero, size: surfaceTree.viewBounds())

        // Perform the resize using the new SplitTree resize method
        do {
            surfaceTree = try surfaceTree.resizing(node: targetNode, by: amount, in: spatialDirection, with: bounds)
        } catch {
            XGhostty.logger.warning("failed to resize split: \(error, privacy: .public)")
        }
    }

    @objc private func ghosttyDidPresentTerminal(_ notification: Notification) {
        guard let target = notification.object as? XGhostty.SurfaceView else { return }
        guard surfaceTree.contains(target) else { return }

        // Bring the window to front and focus the surface.
        window?.makeKeyAndOrderFront(nil)

        // We use a small delay to ensure this runs after any UI cleanup
        // (e.g., command palette restoring focus to its original surface).
        XGhostty.moveFocus(to: target)
        XGhostty.moveFocus(to: target, delay: 0.1)

        // Show a brief highlight to help the user locate the presented terminal.
        target.highlight()
    }

    @objc private func ghosttySurfaceDragEndedNoTarget(_ notification: Notification) {
        guard let target = notification.object as? XGhostty.SurfaceView else { return }
        guard let targetNode = surfaceTree.root?.node(view: target) else { return }

        // If our tree isn't split, then we never create a new window, because
        // it is already a single split.
        guard surfaceTree.isSplit else { return }

        // If we are removing our focused surface then we move it. We need to
        // keep track of our old one so undo sends focus back to the right place.
        let oldFocusedSurface = focusedSurface
        if focusedSurface == target {
            focusedSurface = findNextFocusTargetAfterClosing(node: targetNode)
        }

        // Remove the surface from our tree
        let removedTree = surfaceTree.removing(targetNode)

        // Create a new tree with the dragged surface and open a new window
        let newTree = SplitTree<XGhostty.SurfaceView>(view: target)

        // Treat our undo below as a full group.
        undoManager?.beginUndoGrouping()
        undoManager?.setActionName("Move Split")
        defer {
            undoManager?.endUndoGrouping()
        }

        replaceSurfaceTree(removedTree, moveFocusFrom: oldFocusedSurface)
        _ = TerminalController.newWindow(
            ghostty,
            tree: newTree,
            position: notification.userInfo?[Notification.Name.ghosttySurfaceDragEndedNoTargetPointKey] as? NSPoint,
            confirmUndo: false,
            inheritBackgroundOpacity: isBackgroundOpaque)
    }

    // MARK: Local Events

    private func localEventHandler(_ event: NSEvent) -> NSEvent? {
        return switch event.type {
        case .flagsChanged:
            localEventFlagsChanged(event)

        default:
            event
        }
    }

    private func localEventFlagsChanged(_ event: NSEvent) -> NSEvent? {
        var surfaces: [XGhostty.SurfaceView] = surfaceTree.map { $0 }

        // If we're the main window receiving key input, then we want to avoid
        // calling this on our focused surface because that'll trigger a double
        // flagsChanged call.
        if NSApp.mainWindow == window {
            surfaces = surfaces.filter { $0 != focusedSurface }
        }

        for surface in surfaces {
            surface.flagsChanged(with: event)
        }

        return event
    }

    // MARK: TerminalViewDelegate

    func focusedSurfaceDidChange(to: XGhostty.SurfaceView?) {
        let lastFocusedSurface = focusedSurface
        focusedSurface = to

        // Important to cancel any prior subscriptions
        focusedSurfaceCancellables = []

        // Setup our title listener. If we have a focused surface we always use that.
        // Otherwise, we try to use our last focused surface. In either case, we only
        // want to care if the surface is in the tree so we don't listen to titles of
        // closed surfaces.
        if let titleSurface = focusedSurface ?? lastFocusedSurface,
           surfaceTree.contains(titleSurface) {
            // If we have a surface, we want to listen for title changes.
            titleSurface.$title
                .combineLatest(titleSurface.$bell)
                .map { [weak self] in self?.computeTitle(title: $0, bell: $1) ?? "" }
                .sink { [weak self] in self?.titleDidChange(to: $0) }
                .store(in: &focusedSurfaceCancellables)
        } else {
            // There is no surface to listen to titles for.
            titleDidChange(to: "👻")
        }
    }

    private func computeTitle(title: String, bell: Bool) -> String {
        var result = title
        if bell && ghostty.config.bellFeatures.contains(.title) {
            result = "🔔 \(result)"
        }

        return result
    }

    private func titleDidChange(to: String) {
        lastComputedTitle = to
        applyTitleToWindow()
    }

    private func applyTitleToWindow() {
        guard let window else { return }

        if let titleOverride {
            window.title = computeTitle(
                title: titleOverride,
                bell: focusedSurface?.bell ?? false)
            return
        }

        window.title = lastComputedTitle
    }

    func pwdDidChange(to: URL?) {
        guard let window else { return }

        if derivedConfig.macosTitlebarProxyIcon == .visible {
            // Use the 'to' URL directly
            window.representedURL = to
        } else {
            window.representedURL = nil
        }
    }

    func cellSizeDidChange(to: NSSize) {
        guard derivedConfig.windowStepResize else { return }
        // Stage manager can sometimes present windows in such a way that the
        // cell size is temporarily zero due to the window being tiny. We can't
        // set content resize increments to this value, so avoid an assertion failure.
        guard to.width > 0 && to.height > 0 else { return }
        self.window?.contentResizeIncrements = to
    }

    func performSplitAction(_ action: TerminalSplitOperation) {
        switch action {
        case .resize(let resize):
            splitDidResize(node: resize.node, to: resize.ratio)
        case .drop(let drop):
            splitDidDrop(source: drop.payload, destination: drop.destination, zone: drop.zone)
        }
    }

    /// Switch the focused group in response to a group-label click
    /// (`SPEC.md` §7.1). Mirrors `newGroupSplit`'s swap: persist the outgoing
    /// pane tree, flip the focused group, swap `surfaceTree` to the target's
    /// panes, and move keyboard focus into its last-focused pane (§14.12).
    ///
    /// Like `newGroupSplit`, this registers no undo: `replaceSurfaceTree`'s undo
    /// only restores `surfaceTree`, which would mirror the wrong pane tree into
    /// the wrong group after a focus switch. Group-aware undo is a deferred
    /// follow-up (see `TODO.md`).
    func focusGroup(_ id: GroupID) {
        guard workspace.state.focusedGroup != id else { return }
        guard workspace.state.groups[id] != nil else { return }

        // Persist the current panes into the outgoing group and flip focus.
        let targetFocus = workspace.switchFocusedGroup(
            to: id,
            savingOutgoingPaneTree: surfaceTree)

        // Swap the source-of-truth pane tree to the newly focused group. The
        // resulting `surfaceTreeDidChange` mirrors it back (a no-op) and
        // re-renders the workspace.
        surfaceTree = workspace.focusedPaneTree

        moveKeyboardFocus(toGroupSurface: targetFocus)
    }

    /// Hide the focused group in response to `hide_group` (`SPEC.md` §11.7). The
    /// model moves focus to a visible neighbor and keeps the hidden group's
    /// processes alive; here we swap `surfaceTree` to the neighbor's panes and
    /// move keyboard focus, mirroring `focusGroup`. No-op when the focused group
    /// is the last visible one (§18.2). Registers a group-aware undo ("Hide
    /// Group") so the hide can be reversed; the snapshot keeps the hidden group's
    /// panes (its processes already stay alive via `groups`, §14.7).
    func hideFocusedGroup() {
        let before = workspace.state
        guard let result = workspace.hideFocusedGroup(
            savingOutgoingPaneTree: surfaceTree) else { return }

        surfaceTree = workspace.focusedPaneTree
        moveKeyboardFocus(toGroupSurface: result.focus)
        registerWorkspaceUndo("Hide Group", undo: before, redo: workspace.state)
    }

    /// Show the hidden group `id` in response to a shelf pill click or the
    /// `show_group` action (`SPEC.md` §11.8). The model un-hides it, clears any
    /// zoom, and focuses it; here we swap `surfaceTree` to its panes and move
    /// keyboard focus into its last-focused pane. Registers a group-aware undo
    /// ("Show Group") so the reveal can be reversed.
    func showGroup(_ id: GroupID) {
        guard workspace.state.hiddenGroupIDs.contains(id) else { return }
        let before = workspace.state
        let targetFocus = workspace.showGroup(id, savingOutgoingPaneTree: surfaceTree)

        surfaceTree = workspace.focusedPaneTree
        moveKeyboardFocus(toGroupSurface: targetFocus)
        registerWorkspaceUndo("Show Group", undo: before, redo: workspace.state)
    }

    /// Close the focused group in response to `close_group` or a last-pane
    /// `Cmd+W` (`SPEC.md` §11.9, §11.10). This is destructive — it terminates
    /// the group's processes — so it confirms first whenever any pane still has a
    /// live process (mirroring close_surface / window-close UX; the dialog text
    /// only makes sense when there is something to terminate).
    ///
    /// The `.switched` close registers a group-aware undo ("Close Group"); the
    /// pre-close snapshot retains the closed group's `SurfaceView`s, so its
    /// processes stay alive for the `undoExpiration` window (mirroring
    /// `close_surface` undo). The §18.5 last-group case delegates to the existing
    /// tab/window close, which carries its own undo, so it is not double-wrapped.
    func closeFocusedGroup() {
        guard let group = workspace.focusedGroupState else { return }

        // The focused group's panes are exactly `surfaceTree`.
        guard surfaceTree.contains(where: { $0.needsConfirmQuit }) else {
            performCloseFocusedGroup()
            return
        }

        let paneCount = surfaceTree.reduce(into: 0) { count, _ in count += 1 }
        let pane = paneCount == 1 ? "pane" : "panes"
        confirmClose(
            messageText: "Close Group “\(group.name)”?",
            informativeText: "This will close \(paneCount) \(pane) and terminate their processes.",
            confirmButtonTitle: "Close Group"
        ) { [weak self] in
            self?.performCloseFocusedGroup()
        }
    }

    /// Apply a confirmed `close_group`: prune the focused group from the group
    /// structure and either swap `surfaceTree` to the nearest remaining group
    /// (terminating the closed group's surfaces as they fall out of scope, §14.8)
    /// or, when it was the only group, delegate to tab/window close (§18.5).
    private func performCloseFocusedGroup() {
        let before = workspace.state
        switch workspace.closeFocusedGroup() {
        case .switched(_, let focus):
            surfaceTree = workspace.focusedPaneTree
            moveKeyboardFocus(toGroupSurface: focus)
            registerWorkspaceUndo("Close Group", undo: before, redo: workspace.state)

        case .closedLast:
            // §18.5: emptying the tree routes through `replaceSurfaceTree`, whose
            // `TerminalController` override turns it into `closeTabImmediately()`
            // (closing the window if it is the last tab).
            replaceSurfaceTree(.init())

        case nil:
            break
        }
    }

    /// Move keyboard focus to `surfaceID` within the (now current) `surfaceTree`,
    /// falling back to its first leaf. Shared tail of every group focus switch
    /// (`focusGroup` / `goto_group` / `hide_group` / `show_group`, §14.12).
    private func moveKeyboardFocus(toGroupSurface surfaceID: SurfaceID?) {
        let target: XGhostty.SurfaceView?
        if let surfaceID,
           let node = surfaceTree.find(id: surfaceID.rawValue),
           case .leaf(let view) = node {
            target = view
        } else {
            target = surfaceTree.firstLeaf
        }
        if let target {
            DispatchQueue.main.async {
                XGhostty.moveFocus(to: target)
            }
        }
    }

    private func splitDidResize(node: SplitTree<XGhostty.SurfaceView>.Node, to newRatio: Double) {
        let resizedNode = node.resizing(to: newRatio)
        do {
            surfaceTree = try surfaceTree.replacing(node: node, with: resizedNode)
        } catch {
            XGhostty.logger.warning("failed to replace node during split resize: \(error, privacy: .public)")
        }
    }

    private func splitDidDrop(
        source: XGhostty.SurfaceView,
        destination: XGhostty.SurfaceView,
        zone: TerminalSplitDropZone
    ) {
        // Map drop zone to split direction
        let direction: SplitTree<XGhostty.SurfaceView>.NewDirection = switch zone {
        case .top: .up
        case .bottom: .down
        case .left: .left
        case .right: .right
        }

        // Check if source is in our tree
        if let sourceNode = surfaceTree.root?.node(view: source) {
            // Source is in our tree - same window move
            let treeWithoutSource = surfaceTree.removing(sourceNode)
            let newTree: SplitTree<XGhostty.SurfaceView>
            do {
                newTree = try treeWithoutSource.inserting(view: source, at: destination, direction: direction)
            } catch {
                XGhostty.logger.warning("failed to insert surface during drop: \(error, privacy: .public)")
                return
            }

            replaceSurfaceTree(
                newTree,
                moveFocusTo: source,
                moveFocusFrom: focusedSurface,
                undoAction: "Move Split")
            return
        }

        // Source is not in our tree - search other windows
        var sourceController: BaseTerminalController?
        var sourceNode: SplitTree<XGhostty.SurfaceView>.Node?
        for window in NSApp.windows {
            guard let controller = window.windowController as? BaseTerminalController else { continue }
            guard controller !== self else { continue }
            if let node = controller.surfaceTree.root?.node(view: source) {
                sourceController = controller
                sourceNode = node
                break
            }
        }

        guard let sourceController, let sourceNode else {
            XGhostty.logger.warning("source surface not found in any window during drop")
            return
        }

        // Remove from source controller's tree and add it to our tree.
        // We do this first because if there is an error then we can
        // abort.
        let newTree: SplitTree<XGhostty.SurfaceView>
        do {
            newTree = try surfaceTree.inserting(view: source, at: destination, direction: direction)
        } catch {
            XGhostty.logger.warning("failed to insert surface during cross-window drop: \(error, privacy: .public)")
            return
        }

        // Treat our undo below as a full group.
        undoManager?.beginUndoGrouping()
        undoManager?.setActionName("Move Split")
        defer {
            undoManager?.endUndoGrouping()
        }

        // Remove the node from the source.
        sourceController.removeSurfaceNode(sourceNode)

        // Add in the surface to our tree
        replaceSurfaceTree(
            newTree,
            moveFocusTo: source,
            moveFocusFrom: focusedSurface)
    }

    func performAction(_ action: String, on surfaceView: XGhostty.SurfaceView) {
        guard let surface = surfaceView.surface else { return }
        let len = action.utf8CString.count
        if len == 0 { return }
        _ = action.withCString { cString in
            xghostty_surface_binding_action(surface, cString, UInt(len - 1))
        }
    }

    // MARK: Appearance

    /// Toggle the background opacity between transparent and opaque states.
    /// Do nothing if the configured background-opacity is >= 1 (already opaque).
    /// Subclasses should override this to add platform-specific checks and sync appearance.
    func toggleBackgroundOpacity() {
        // Do nothing if config is already fully opaque
        guard ghostty.config.backgroundOpacity < 1 else { return }

        // Do nothing if in fullscreen (transparency doesn't apply in fullscreen)
        guard let window, !window.styleMask.contains(.fullScreen) else { return }

        let newValue = !isBackgroundOpaque
        let controllers = NSApplication.shared.windows.compactMap {
            $0.windowController as? BaseTerminalController
        }

        for controller in controllers {
            controller.isBackgroundOpaque = newValue
            controller.syncAppearance()
        }
    }

    /// Override this to resync any appearance related properties. This will be called automatically
    /// when certain window properties change that affect appearance. The list below should be updated
    /// as we add new things:
    ///
    ///  - ``toggleBackgroundOpacity``
    func syncAppearance() {
        // Purposely a no-op. This lets subclasses override this and we can call
        // it virtually from here.
    }

    // MARK: Fullscreen

    /// Toggle fullscreen for the given mode.
    func toggleFullscreen(mode: FullscreenMode) {
        // We need a window to fullscreen
        guard let window = self.window else { return }

        // If we have a previous fullscreen style initialized, we want to check if
        // our mode changed. If it changed and we're in fullscreen, we exit so we can
        // toggle it next time. If it changed and we're not in fullscreen we can just
        // switch the handler.
        var newStyle = mode.style(for: window)
        newStyle?.delegate = self
        old: if let oldStyle = self.fullscreenStyle {
            // If we're not fullscreen, we can nil it out so we get the new style
            if !oldStyle.isFullscreen {
                self.fullscreenStyle = newStyle
                break old
            }

            assert(oldStyle.isFullscreen)

            // We consider our mode changed if the types change (obvious) but
            // also if its nil (not obvious) because nil means that the style has
            // likely changed but we don't support it.
            if newStyle == nil || type(of: newStyle!) != type(of: oldStyle) {
                // Our mode changed. Exit fullscreen (since we're toggling anyways)
                // and then set the new style for future use
                oldStyle.exit()
                self.fullscreenStyle = newStyle

                // We're done
                return
            }

            // Style is the same.
        } else {
            // We have no previous style
            self.fullscreenStyle = newStyle
        }
        guard let fullscreenStyle else { return }

        if fullscreenStyle.isFullscreen {
            fullscreenStyle.exit()
        } else {
            fullscreenStyle.enter()
        }
    }

    func fullscreenDidChange() {
        guard let fullscreenStyle else { return }

        // When we enter fullscreen, we want to show the update overlay so that it
        // is easily visible. For native fullscreen this is visible by showing the
        // menubar but we don't want to rely on that.
        if fullscreenStyle.isFullscreen {
            updateOverlayIsVisible = true
        } else {
            updateOverlayIsVisible = defaultUpdateOverlayVisibility()
        }

        // Always resync our appearance
        syncAppearance()
    }

    // MARK: Clipboard Confirmation

    @objc private func onConfirmClipboardRequest(notification: SwiftUI.Notification) {
        guard let target = notification.object as? XGhostty.SurfaceView else { return }
        guard target == self.focusedSurface else { return }
        guard let surface = target.surface else { return }

        // We need a window
        guard let window = self.window else { return }

        // Check whether we use non-native fullscreen
        guard let str = notification.userInfo?[XGhostty.Notification.ConfirmClipboardStrKey] as? String else { return }
        guard let state = notification.userInfo?[XGhostty.Notification.ConfirmClipboardStateKey] as? UnsafeMutableRawPointer? else { return }
        guard let request = notification.userInfo?[XGhostty.Notification.ConfirmClipboardRequestKey] as? XGhostty.ClipboardRequest else { return }

        // If we already have a clipboard confirmation view up, we ignore this request.
        // This shouldn't be possible...
        guard self.clipboardConfirmation == nil else {
            XGhostty.App.completeClipboardRequest(surface, data: "", state: state, confirmed: true)
            return
        }

        // Show our paste confirmation
        self.clipboardConfirmation = ClipboardConfirmationController(
            surface: surface,
            contents: str,
            request: request,
            state: state,
            delegate: self
        )
        window.beginSheet(self.clipboardConfirmation!.window!)
    }

    func clipboardConfirmationComplete(_ action: ClipboardConfirmationView.Action, _ request: XGhostty.ClipboardRequest) {
        // End our clipboard confirmation no matter what
        guard let cc = self.clipboardConfirmation else { return }
        self.clipboardConfirmation = nil

        // Close the sheet
        if let ccWindow = cc.window {
            window?.endSheet(ccWindow)
        }

        switch request {
        case let .osc_52_write(pasteboard):
            guard case .confirm = action else { break }
            let pb = pasteboard ?? NSPasteboard.general
            pb.declareTypes([.string], owner: nil)
            pb.setString(cc.contents, forType: .string)
        case .osc_52_read, .paste:
            let str: String
            switch action {
            case .cancel:
                str = ""

            case .confirm:
                str = cc.contents
            }

            XGhostty.App.completeClipboardRequest(cc.surface, data: str, state: cc.state, confirmed: true)
        }
    }

    // MARK: NSWindowController

    override func windowDidLoad() {
        super.windowDidLoad()

        // Setup our undo manager.

        // Everything beyond here is setting up the window
        guard let window else { return }

        // We always initialize our fullscreen style to native if we can because
        // initialization sets up some state (i.e. observers). If its set already
        // somehow we don't do this.
        if fullscreenStyle == nil {
            fullscreenStyle = NativeFullscreen(window)
            fullscreenStyle?.delegate = self
        }

        // Set our update overlay state
        updateOverlayIsVisible = defaultUpdateOverlayVisibility()
    }

    func defaultUpdateOverlayVisibility() -> Bool {
        guard let window else { return true }

        // No titlebar we always show the update overlay because it can't support
        // updates in the titlebar
        guard window.styleMask.contains(.titled) else {
            return true
        }

        // If it's a non terminal window we can't trust it has an update accessory,
        // so we always want to show the overlay.
        guard let window = window as? TerminalWindow else {
            return true
        }

        // Show the overlay if the window isn't.
        return !window.supportsUpdateAccessory
    }

    // MARK: NSWindowDelegate

    /// Check whether window should be closed without showing an alert
    func windowCanBeClosedWithoutConfirmation() -> Bool {
        // We must have a window. Is it even possible not to?
        guard let window = self.window else { return true }

        // If we have no surfaces, close.
        if surfaceTree.isEmpty { return true }

        // If we already have an alert, continue with it
        guard alert == nil else { return false }

        // If our surfaces don't require confirmation, close.
        if !surfaceTree.contains(where: { $0.needsConfirmQuit }) { return true }

        return false
    }

    // This is called when performClose is called on a window (NOT when close()
    // is called directly). performClose is called primarily when UI elements such
    // as the "red X" are pressed.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !windowCanBeClosedWithoutConfirmation() else {
            return true
        }
        // We require confirmation, so show an alert as long as we aren't already.
        confirmClose(
            messageText: "Close Terminal?",
            informativeText: "The terminal still has a running process. If you close the terminal the process will be killed."
        ) { [weak self] in
            self?.window?.close()
        }

        return false
    }

    func windowWillClose(_ notification: Notification) {
        guard let window else { return }

        // Emit a final bell-state transition so any observers can clear state
        // without separately tracking NSWindow lifecycle events.
        if bell {
            bell = false
            NotificationCenter.default.post(
                name: .terminalWindowBellDidChangeNotification,
                object: self,
                userInfo: [Notification.Name.terminalWindowHasBellKey: false]
            )
        }

        // I don't know if this is required anymore. We previously had a ref cycle between
        // the view and the window so we had to nil this out to break it but I think this
        // may now be resolved. We should verify that no memory leaks and we can remove this.
        window.contentView = nil

        // Make sure we clean up all our undos
        window.undoManager?.removeAllActions(withTarget: self)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        // If when we become key our first responder is the window itself, then we
        // want to move focus to our focused terminal surface. This works around
        // various weirdness with moving surfaces around.
        if let window, window.firstResponder == window, let focusedSurface {
            DispatchQueue.main.async {
                XGhostty.moveFocus(to: focusedSurface)
            }
        }

        // Becoming key can race with responder updates when activating a window.
        // Sync on the next runloop so split focus has settled first.
        DispatchQueue.main.async {
            self.syncFocusToSurfaceTree()
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        // Becoming/losing key means we have to notify our surface(s) that we have focus
        // so things like cursors blink, pty events are sent, etc.
        self.syncFocusToSurfaceTree()
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        syncSurfaceTreeOcclusionState()
    }

    private func syncSurfaceTreeOcclusionState() {
        let visible = self.window?.occlusionState.contains(.visible) ?? false
        for view in surfaceTree {
            if let surface = view.surface, view.isWindowVisible != visible {
                xghostty_surface_set_occlusion(surface, visible)
                view.isWindowVisible = visible
            }
        }
    }

    func windowDidResize(_ notification: Notification) {
        windowFrameDidChange()
    }

    func windowDidMove(_ notification: Notification) {
        windowFrameDidChange()
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else { return nil }
        return appDelegate.undoManager
    }

    // MARK: First Responder

    @IBAction func close(_ sender: Any) {
        guard let surface = focusedSurface?.surface else { return }
        ghostty.requestClose(surface: surface)
    }

    @IBAction func closeWindow(_ sender: Any) {
        guard let window = window else { return }
        window.performClose(sender)
    }

    @IBAction func changeTabTitle(_ sender: Any) {
        if let targetWindow = window {
            let inlineHostWindow =
                targetWindow.tabbedWindows?
                    .first(where: { $0.tabBarView != nil }) as? TerminalWindow
                ?? (targetWindow as? TerminalWindow)

            if let inlineHostWindow, inlineHostWindow.beginInlineTabTitleEdit(for: targetWindow) {
                return
            }
        }

        promptTabTitle()
    }

    @IBAction func splitRight(_ sender: Any) {
        guard let surface = focusedSurface?.surface else { return }
        ghostty.split(surface: surface, direction: XGHOSTTY_SPLIT_DIRECTION_RIGHT)
    }

    @IBAction func splitLeft(_ sender: Any) {
        guard let surface = focusedSurface?.surface else { return }
        ghostty.split(surface: surface, direction: XGHOSTTY_SPLIT_DIRECTION_LEFT)
    }

    @IBAction func splitDown(_ sender: Any) {
        guard let surface = focusedSurface?.surface else { return }
        ghostty.split(surface: surface, direction: XGHOSTTY_SPLIT_DIRECTION_DOWN)
    }

    @IBAction func splitUp(_ sender: Any) {
        guard let surface = focusedSurface?.surface else { return }
        ghostty.split(surface: surface, direction: XGHOSTTY_SPLIT_DIRECTION_UP)
    }

    @IBAction func splitZoom(_ sender: Any) {
        guard let surface = focusedSurface?.surface else { return }
        ghostty.splitToggleZoom(surface: surface)
    }

    @IBAction func splitMoveFocusPrevious(_ sender: Any) {
        splitMoveFocus(direction: .previous)
    }

    @IBAction func splitMoveFocusNext(_ sender: Any) {
        splitMoveFocus(direction: .next)
    }

    @IBAction func splitMoveFocusAbove(_ sender: Any) {
        splitMoveFocus(direction: .up)
    }

    @IBAction func splitMoveFocusBelow(_ sender: Any) {
        splitMoveFocus(direction: .down)
    }

    @IBAction func splitMoveFocusLeft(_ sender: Any) {
        splitMoveFocus(direction: .left)
    }

    @IBAction func splitMoveFocusRight(_ sender: Any) {
        splitMoveFocus(direction: .right)
    }

    @IBAction func equalizeSplits(_ sender: Any) {
        guard let surface = focusedSurface?.surface else { return }
        ghostty.splitEqualize(surface: surface)
    }

    @IBAction func moveSplitDividerUp(_ sender: Any) {
        guard let surface = focusedSurface?.surface else { return }
        ghostty.splitResize(surface: surface, direction: .up, amount: 10)
    }

    @IBAction func moveSplitDividerDown(_ sender: Any) {
        guard let surface = focusedSurface?.surface else { return }
        ghostty.splitResize(surface: surface, direction: .down, amount: 10)
    }

    @IBAction func moveSplitDividerLeft(_ sender: Any) {
        guard let surface = focusedSurface?.surface else { return }
        ghostty.splitResize(surface: surface, direction: .left, amount: 10)
    }

    @IBAction func moveSplitDividerRight(_ sender: Any) {
        guard let surface = focusedSurface?.surface else { return }
        ghostty.splitResize(surface: surface, direction: .right, amount: 10)
    }

    private func splitMoveFocus(direction: XGhostty.SplitFocusDirection) {
        guard let surface = focusedSurface?.surface else { return }
        ghostty.splitMoveFocus(surface: surface, direction: direction)
    }

    @IBAction func increaseFontSize(_ sender: Any) {
        guard let surface = focusedSurface?.surface else { return }
        ghostty.changeFontSize(surface: surface, .increase(1))
    }

    @IBAction func decreaseFontSize(_ sender: Any) {
        guard let surface = focusedSurface?.surface else { return }
        ghostty.changeFontSize(surface: surface, .decrease(1))
    }

    @IBAction func resetFontSize(_ sender: Any) {
        guard let surface = focusedSurface?.surface else { return }
        ghostty.changeFontSize(surface: surface, .reset)
    }

    @IBAction func toggleCommandPalette(_ sender: Any?) {
        commandPaletteIsShowing.toggle()
        if commandPaletteIsShowing {
            // Fix the incorrect focus when toggling from InlineTitleEditor
            // When toggling the command palette from the inline title editor,
            // the first responder state of the surface is changed quickly from true to false.

            // `makeFirstResponder:` is called by the title editor when finishing,
            // but it happens **after** the command palette is shown,
            // so the `focused` is set to `true` while the command palette is shown.
            // (Could be an AppKit issue as well, since the resign is not called after but the command palette is receiving `keyDown`).

            // Since `performKeyEquivalent(with:)` is called on all of the subviews
            // until one of the return `true` so the paste action is consumed by the surface
            // instead of the first responder (command palette).
            _ = focusedSurface?.resignFirstResponder()
        }
    }

    @IBAction func find(_ sender: Any) {
        focusedSurface?.find(sender)
    }

    @IBAction func selectionForFind(_ sender: Any) {
        focusedSurface?.selectionForFind(sender)
    }

    @IBAction func scrollToSelection(_ sender: Any) {
        focusedSurface?.scrollToSelection(sender)
    }

    @IBAction func findNext(_ sender: Any) {
        focusedSurface?.findNext(sender)
    }

    @IBAction func findPrevious(_ sender: Any) {
        focusedSurface?.findNext(sender)
    }

    @IBAction func findHide(_ sender: Any) {
        focusedSurface?.findHide(sender)
    }

    @objc func resetTerminal(_ sender: Any) {
        guard let surface = focusedSurface?.surface else { return }
        ghostty.resetTerminal(surface: surface)
    }

    private struct DerivedConfig {
        let macosTitlebarProxyIcon: XGhostty.MacOSTitlebarProxyIcon
        let windowStepResize: Bool
        let focusFollowsMouse: Bool
        let splitPreserveZoom: XGhostty.Config.SplitPreserveZoom

        init() {
            self.macosTitlebarProxyIcon = .visible
            self.windowStepResize = false
            self.focusFollowsMouse = false
            self.splitPreserveZoom = .init()
        }

        init(_ config: XGhostty.Config) {
            self.macosTitlebarProxyIcon = config.macosTitlebarProxyIcon
            self.windowStepResize = config.windowStepResize
            self.focusFollowsMouse = config.focusFollowsMouse
            self.splitPreserveZoom = config.splitPreserveZoom
        }
    }
}

extension BaseTerminalController: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(findHide):
            return focusedSurface?.searchState != nil

        default:
            return true
        }
    }

    // MARK: - Surface Color Scheme

    /// Update the surface tree's color scheme only when it actually changes.
    ///
    /// Calling ``xghostty_surface_set_color_scheme`` triggers
    /// ``syncAppearance(_:)`` via notification,
    /// so we avoid redundant calls.
    func updateColorSchemeForSurfaceTree() {
        /// Derive the target scheme from `window-theme` or system appearance.
        /// We set the scheme on surfaces so they pick the correct theme
        /// and let ``syncAppearance(_:)`` update the window accordingly.
        ///
        /// Using App's effectiveAppearance here to prevent incorrect updates.
        let themeAppearance = NSApplication.shared.effectiveAppearance
        let scheme: xghostty_color_scheme_e
        if themeAppearance.isDark {
            scheme = XGHOSTTY_COLOR_SCHEME_DARK
        } else {
            scheme = XGHOSTTY_COLOR_SCHEME_LIGHT
        }
        guard scheme != appliedColorScheme else {
            return
        }
        for surfaceView in surfaceTree {
            if let surface = surfaceView.surface {
                xghostty_surface_set_color_scheme(surface, scheme)
            }
        }
        appliedColorScheme = scheme
    }
}

// MARK: Combine Methods

extension BaseTerminalController {
    /// Publishes an app-wide notification whenever this terminal window's aggregate
    /// bell state changes.
    private func setupBellNotificationPublisher() {
        bellStateCancellable = surfaceValuesPublisher(valueKeyPath: \.bell, publisherKeyPath: \.$bell)
            .map { $0.values.contains(true) }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hasBell in
                guard let self else { return }
                bell = hasBell
                NotificationCenter.default.post(
                    name: .terminalWindowBellDidChangeNotification,
                    object: self,
                    userInfo: [Notification.Name.terminalWindowHasBellKey: hasBell]
                )
            }
    }

    /// Creates a publisher for values on all surfaces in this controller's tree.
    ///
    /// The publisher emits a dictionary of surface IDs to values whenever the tree changes
    /// or any surface publishes a new value for the key path.
    func surfaceValuesPublisher<Value>(
        valueKeyPath: KeyPath<XGhostty.SurfaceView, Value>,
        publisherKeyPath: KeyPath<XGhostty.SurfaceView, Published<Value>.Publisher>
    ) -> AnyPublisher<[XGhostty.SurfaceView.ID: Value], Never> {
        // `surfaceTree` can be replaced entirely when splits are added/removed/closed.
        // For each tree snapshot we build a fresh publisher that watches all surfaces
        // in that snapshot.
        $surfaceTree
            .map { tree in
                tree.valuesPublisher(
                    valueKeyPath: valueKeyPath,
                    publisherKeyPath: publisherKeyPath
                )
            }
            // Keep only the latest tree publisher active. This automatically cancels
            // subscriptions for old/removed surfaces when the tree changes.
            .switchToLatest()
            .eraseToAnyPublisher()
    }
}

// MARK: Notifications

extension Notification.Name {
    /// Terminal window aggregate bell state changed.
    static let terminalWindowBellDidChangeNotification = Notification.Name("com.mitchellh.xghostty.terminalWindowBellDidChange")
    static let terminalWindowHasBellKey = terminalWindowBellDidChangeNotification.rawValue + ".hasBell"
}
