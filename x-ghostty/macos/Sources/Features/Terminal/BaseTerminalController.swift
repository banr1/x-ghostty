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
            // Cross-project click: surface is in a different project's pane tree, so
            // sync the project layer without moving the AppKit first responder (it's correct already).
            if let surface = focusedSurface, !surfaceTree.contains(surface) {
                if let targetProjectID = workspace.state.projects.first(where: {
                    $0.value.paneTree.find(id: surface.id) != nil
                })?.key {
                    workspace.switchFocusedProject(
                        to: targetProjectID,
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

    /// The project layer wrapping `surfaceTree`. In Phase 0 this mirrors the
    /// focused project's pane tree; `surfaceTree` remains the source of truth for
    /// rendering, actions and Combine observation. See `SPEC.md` §15 Phase 0.
    private(set) var workspace = WorkspaceModel()

    /// Every surface this controller owns, across *all* projects — focused,
    /// unfocused, and hidden alike.
    ///
    /// `surfaceTree` is only the focused project's panes; the other projects' panes
    /// live in `workspace.state.projects` and their processes are just as alive
    /// (`SPEC.md` §14.7). Anything that reasons about what closing this
    /// window would destroy must use this, never `surfaceTree`, or it will
    /// silently kill background projects.
    var allSurfaces: [XGhostty.SurfaceView] {
        // The focused project's canonical panes are `surfaceTree`; the workspace
        // copy is only mirrored on change, so prefer the live tree for it and
        // take the rest from the workspace. Dedupe by id because the mirror is
        // normally in sync (the same views would otherwise appear twice).
        var seen = Set<UUID>()
        var result: [XGhostty.SurfaceView] = []

        for view in surfaceTree where seen.insert(view.id).inserted {
            result.append(view)
        }

        let focusedProject = workspace.state.focusedProject
        for (id, project) in workspace.state.projects where id != focusedProject {
            for view in project.paneTree where seen.insert(view.id).inserted {
                result.append(view)
            }
        }

        return result
    }

    /// Whether closing this controller's window would terminate a live process
    /// in any project, and therefore requires confirmation.
    var needsCloseConfirmation: Bool {
        allSurfaces.contains(where: { $0.needsConfirmQuit })
    }

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

    /// Whether a `confirmClose`/`confirmCloseAsync` sheet is currently up.
    ///
    /// Callers that would start a *new* destructive flow must check this so they
    /// can't stack a second sheet, and — more importantly — can't slip past the
    /// one the user hasn't answered yet.
    var isShowingConfirmation: Bool { alert != nil }

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

    /// Cancellable for invalidating restorable state on project-layer changes.
    private var workspaceStateCancellable: AnyCancellable?

    /// An override title for the window set by the user.
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
            // Restore the full project layer (Phase 6 / `SPEC.md` §12). Each pane
            // was decoded as a fresh shell; the focused project's pane tree becomes
            // the `surfaceTree` source of truth and the rest of the projects render
            // from the workspace. Setting `surfaceTree` first is a no-op mirror
            // (the default empty model has no focused project) before we install
            // the restored model whose focused project already holds this tree.
            let model = WorkspaceModel(restoredWorkspace)
            self.surfaceTree = model.focusedPaneTree
            self.workspace = model
        } else {
            self.surfaceTree = tree ?? .init(view: XGhostty.SurfaceView(xghostty_app, baseConfig: base))

            // Wrap the initial pane tree into the project layer. Phase 0 keeps a
            // single default project whose pane tree mirrors `surfaceTree`.
            self.workspace = WorkspaceModel(wrapping: self.surfaceTree)
        }

        // Persist state-only project-layer mutations. `resize_project` /
        // `equalize_projects` / `rename_project` (both the inline editor and the
        // `set_project_title` action) change `workspace.state` without touching
        // `surfaceTree`, so they never reach `surfaceTreeDidChange`'s
        // `invalidateRestorableState`. Mirror that hook on the project layer's
        // source of truth so canonical project ratios and names survive relaunch.
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
            selector: #selector(ghosttyDidExitChild(_:)),
            name: XGhostty.Notification.ghosttyChildExited,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(ghosttyDidPressKeyOnExitedSurface(_:)),
            name: XGhostty.Notification.ghosttyExitedSurfaceKeyDown,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(ghosttyDidNewSplit(_:)),
            name: XGhostty.Notification.ghosttyNewSplit,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(ghosttyDidNewProjectSplit(_:)),
            name: XGhostty.Notification.ghosttyNewProjectSplit,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(ghosttyDidRenameProject(_:)),
            name: XGhostty.Notification.ghosttyRenameProject,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(ghosttyDidEditProjectNote(_:)),
            name: XGhostty.Notification.ghosttyEditProjectNote,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(ghosttyDidToggleNoteOverview(_:)),
            name: XGhostty.Notification.ghosttyToggleNoteOverview,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(ghosttyDidSetPrimary(_:)),
            name: XGhostty.Notification.ghosttySetPrimary,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(ghosttyDidSortProjectsByPriority(_:)),
            name: XGhostty.Notification.ghosttySortProjectsByPriority,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(ghosttyDidSortProjectsByDeadline(_:)),
            name: XGhostty.Notification.ghosttySortProjectsByDeadline,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(ghosttyDidSetProjectTitle(_:)),
            name: XGhostty.Notification.ghosttySetProjectTitle,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(ghosttyDidGotoProject(_:)),
            name: XGhostty.Notification.ghosttyGotoProject,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(ghosttyDidGotoProjectIndex(_:)),
            name: XGhostty.Notification.ghosttyGotoProjectIndex,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(ghosttyDidMoveProject(_:)),
            name: XGhostty.Notification.ghosttyMoveProject,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(ghosttyDidResizeProject(_:)),
            name: XGhostty.Notification.ghosttyResizeProject,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(ghosttyDidEqualizeProjects(_:)),
            name: XGhostty.Notification.ghosttyEqualizeProjects,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(ghosttyDidToggleProjectZoom(_:)),
            name: XGhostty.Notification.ghosttyToggleProjectZoom,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(ghosttyDidHideProject(_:)),
            name: XGhostty.Notification.ghosttyHideProject,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(ghosttyDidShowProject(_:)),
            name: XGhostty.Notification.ghosttyShowProject,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(ghosttyDidCloseProject(_:)),
            name: XGhostty.Notification.ghosttyCloseProject,
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
        // Pane operations are zoom-only (SPEC §22.5): in the overall view only
        // the primary pane is rendered, so a split would create an invisible
        // pane. The action layer already declines to post outside zoom; this
        // is the backstop for direct callers (menu items, drops, undo).
        guard workspace.paneOperationsEnabled else { return nil }

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

    /// Create a new project as a sibling of the focused project, with a single
    /// initial pane, and move focus into it (`SPEC.md` §11.1).
    ///
    /// Registers a project-aware undo ("New Project"): because the focused project
    /// switches here, `replaceSurfaceTree`'s `surfaceTree`-only undo can't be
    /// reused (it would mirror the old panes into the new project). Instead we
    /// snapshot the whole `WorkspaceState` before/after and register a
    /// `registerWorkspaceUndo` that restores them atomically.
    @discardableResult
    func newProjectSplit(
        at oldView: XGhostty.SurfaceView,
        direction: SplitTree<ProjectRef>.NewDirection,
        baseConfig config: XGhostty.SurfaceConfiguration? = nil
    ) -> XGhostty.SurfaceView? {
        // The anchor surface must be in our (the focused project's) tree, and we
        // need a focused project to anchor the new sibling against.
        guard surfaceTree.root?.node(view: oldView) != nil else { return nil }
        guard workspace.state.focusedProject != nil else { return nil }
        // At most `WorkspaceState.maxVisibleProjects` projects can be visible, since
        // each one needs a number. At the cap this is a silent no-op (no toast,
        // no beep) — checked here, before a `SurfaceView` (and its shell process)
        // would be spawned only to be thrown away.
        guard workspace.canAddVisibleProject else { return nil }
        guard let xghostty_app = ghostty.app else { return nil }

        // Build the new project's single initial pane.
        let newView = XGhostty.SurfaceView(xghostty_app, baseConfig: config)
        let newPaneTree = SplitTree<XGhostty.SurfaceView>(view: newView)

        // Name and assemble the new project, focused on its initial pane.
        let now = Date()
        let existingNames = Set(workspace.state.projects.values.map(\.name))
        let newProject = ProjectState(
            id: ProjectID(),
            name: ProjectNameGenerator.make(existing: existingNames),
            paneTree: newPaneTree,
            focusedSurface: SurfaceID(rawValue: newView.id),
            createdAt: now,
            lastFocusedAt: now)

        // Snapshot before the switch so the undo can restore the outgoing project.
        let before = workspace.state

        // Single project-switch point: persist the outgoing pane tree, insert the
        // new project next to the focused one, and switch focus (un-zooms first).
        do {
            try workspace.openNewProject(
                newProject,
                direction: direction,
                savingOutgoingPaneTree: surfaceTree)
        } catch {
            XGhostty.logger.warning("failed to open new project split: \(error, privacy: .public)")
            return nil
        }

        // Swap the source-of-truth pane tree to the new project's tree. The
        // resulting `surfaceTreeDidChange` mirrors it back into the now-focused
        // new project (a no-op) and re-renders the workspace.
        surfaceTree = newPaneTree
        DispatchQueue.main.async {
            XGhostty.moveFocus(to: newView, from: oldView)
        }

        // The post-mirror state is the redo target; it retains the new pane.
        registerWorkspaceUndo("New Project", undo: before, redo: workspace.state)

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
        // Mirror the focused project's pane tree into the project layer (Phase 0).
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
            // A nil response means a confirmation sheet was already up, so the
            // user never answered *this* request. That is emphatically not
            // consent: every call site here is destructive (close surface, close
            // project, close window), so we must not proceed. The user still has
            // the sheet in front of them and can retry afterwards.
            guard let response = await confirmCloseAsync(messageText: messageText, informativeText: informativeText, confirmButtonTitle: confirmButtonTitle) else {
                return
            }
            if [.alertFirstButtonReturn, .OK].contains(response) {
                completion()
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

        // In the overall view keyboard focus always lands on the primary pane
        // (SPEC §22.4): the requested focus target may not even be rendered.
        // This retarget covers every tree replacement outside zoom — pane
        // close (shell exit / Cmd+W promotes a new primary) and undo restores
        // alike. The model's stored focus was snapped by the mirror already.
        var focusView = newView
        if !workspace.paneOperationsEnabled,
           let primaryID = workspace.focusedProjectState?.primaryPane,
           let primaryNode = newTree.find(id: primaryID.rawValue),
           case .leaf(let primaryView) = primaryNode {
            focusView = primaryView
        }
        if let focusView {
            DispatchQueue.main.async {
                XGhostty.moveFocus(to: focusView, from: oldView)
            }
        }

        // Setup our undo
        guard let undoManager else { return }
        if let undoAction {
            undoManager.setActionName(undoAction)
        }

        // The project this pane edit belongs to. A pane undo only ever restores
        // `surfaceTree`, which `surfaceTreeDidChange` mirrors into whatever project
        // is focused *at replay time*. If the focused project has since changed,
        // replaying would mirror this project's panes into the wrong project and
        // corrupt the layer (the project-aware undo cross-cutting task). Capturing
        // the project here and skipping when it differs is the corruption guard —
        // pane undos stay valid across round-trip project switches (the guard
        // passes again once we return) but no-op while focused elsewhere.
        let projectID = workspace.state.focusedProject

        undoManager.registerUndo(
            withTarget: self,
            expiresAfter: undoExpiration
        ) { target in
            guard target.workspace.state.focusedProject == projectID else { return }

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
                guard target.workspace.state.focusedProject == projectID else { return }

                target.replaceSurfaceTree(
                    newTree,
                    moveFocusTo: newView,
                    moveFocusFrom: target.focusedSurface,
                    undoAction: undoAction)
            }
        }
    }

    // MARK: Project-aware undo (cross-cutting task)

    /// Restore a captured `WorkspaceState` snapshot and re-sync the
    /// source-of-truth `surfaceTree` to the restored focused project.
    ///
    /// Order is load-bearing: the model is restored *first* so `focusedProject` is
    /// correct before `surfaceTree` is assigned — its `surfaceTreeDidChange`
    /// mirror then writes into the restored project, not a stale one. The mirror
    /// reads the possibly-stale `self.focusedSurface`, but `replaceFocusedPaneTree`
    /// ignores a surface that isn't in the restored tree and keeps the snapshot's
    /// stored focus, so the stale value is harmless.
    private func restoreWorkspaceState(_ snapshot: WorkspaceState) {
        workspace.restoreState(snapshot)
        let focus = workspace.focusedProjectState?.focusedSurface
        surfaceTree = workspace.focusedPaneTree
        moveKeyboardFocus(toProjectSurface: focus)
    }

    /// Release every surface this controller owns, in every project.
    ///
    /// Called when the window is closed for good and the caller has already
    /// captured whatever undo state it needs. Clearing `surfaceTree` alone only
    /// empties the *focused* project: the other projects' `SurfaceView`s stay retained
    /// by `workspace.state.projects`, so their processes would outlive the close and
    /// a stale `undoState` could still be registered for the dead window. The
    /// workspace is dropped first so the `surfaceTreeDidChange` mirror that follows
    /// has no project left to write into.
    func removeAllSurfaces() {
        workspace.removeAllProjects()
        surfaceTree = .init()
    }

    /// Register a project-aware undo that swaps between two whole-`WorkspaceState`
    /// snapshots. Unlike `replaceSurfaceTree`'s undo (which restores only
    /// `surfaceTree`), this restores `focusedProject` / `canonicalProjectTree` /
    /// `projects` together, so it stays correct across focused-project switches.
    ///
    /// The snapshots are value-type copies that retain the live `SurfaceView`s,
    /// so an undo of `close_project` keeps the closed project's processes alive for
    /// the `undoExpiration` window (mirroring `close_surface` undo), and a redo of
    /// `new_project_split` can restore the new pane the post-mutation snapshot
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

        // §11.10 / §23.1: closing the last pane of a project is really closing
        // the project, so it escalates to `close_project` — which always confirms
        // (deletion protection) — even when this is the only project (there the
        // confirmed close delegates to the window close, §18.5). The core
        // never closes a surface on child exit anymore (§23.2), so every
        // close arriving here is an explicit operation.
        if surfaceTree.removing(node).isEmpty {
            closeFocusedProject()
            return
        }

        closeSurface(
            node,
            withConfirmation: (notification.userInfo?["process_alive"] as? Bool) ?? false)
    }

    /// A surface's child process exited (`SPEC.md` §23.2). The core keeps the
    /// surface open unconditionally; the model judges what the exit means:
    /// a project's last pane enters the terminated state (the project and its
    /// note stay), an exited sibling pane closes as before, and an
    /// abnormally-exited sibling stays with its error message until a key
    /// press closes it (`ghosttyDidPressKeyOnExitedSurface`).
    @objc private func ghosttyDidExitChild(_ notification: Notification) {
        guard let target = notification.object as? XGhostty.SurfaceView else { return }
        guard isInWorkspace(target) else { return }
        let abnormal = notification.userInfo?[
            XGhostty.Notification.ChildExitedAbnormalKey
        ] as? Bool ?? false

        switch workspace.childExitOutcome(
            for: SurfaceID(rawValue: target.id),
            abnormalExit: abnormal
        ) {
        case .terminated:
            workspace.markPaneTerminated(SurfaceID(rawValue: target.id))

        case .closePane:
            closeExitedPane(target)

        case .keepPaneAwaitingKey, nil:
            break
        }
    }

    /// A key was pressed on a surface whose child process has exited
    /// (`SPEC.md` §23.2–23.3). A terminated pane (its project's protected last
    /// pane) reacts only to Enter, which starts a new shell in the same pane;
    /// any other exited pane keeps the upstream contract — the first key
    /// press closes it. The outcome is re-judged at key time: sibling panes
    /// may have closed since the exit, making this the last pane, which then
    /// enters the terminated state instead of closing.
    @objc private func ghosttyDidPressKeyOnExitedSurface(_ notification: Notification) {
        guard let target = notification.object as? XGhostty.SurfaceView else { return }
        guard isInWorkspace(target) else { return }
        let isReturn = notification.userInfo?[
            XGhostty.Notification.ExitedSurfaceKeyIsReturnKey
        ] as? Bool ?? false
        let paneID = SurfaceID(rawValue: target.id)

        if let projectID = workspace.projectID(containing: paneID),
           workspace.isProjectTerminated(projectID) {
            if isReturn { restartTerminatedPane(in: projectID) }
            return
        }

        switch workspace.childExitOutcome(for: paneID, abnormalExit: true) {
        case .terminated:
            workspace.markPaneTerminated(paneID)

        case .closePane, .keepPaneAwaitingKey:
            closeExitedPane(target)

        case nil:
            break
        }
    }

    /// Close the exited pane `view` — a pane among several, so never a
    /// project-close. The focused project's panes are `surfaceTree`, so they go
    /// through the existing close path (focus move, undo); a pane in any
    /// other (e.g. hidden) project is removed model-side.
    private func closeExitedPane(_ view: XGhostty.SurfaceView) {
        if let node = surfaceTree.root?.node(view: view) {
            closeSurface(node, withConfirmation: false)
        } else {
            workspace.removeExitedPane(SurfaceID(rawValue: view.id))
        }
    }

    /// Start a new shell in a terminated project's pane slot (`SPEC.md` §23.3):
    /// the Enter-restart path. Builds a fresh surface (a fresh shell), swaps
    /// it into the project via the model, and — when the project is focused —
    /// re-syncs `surfaceTree` and moves keyboard focus into the new pane.
    func restartTerminatedPane(in projectID: ProjectID) {
        guard workspace.isProjectTerminated(projectID) else { return }
        guard let xghostty_app = ghostty.app else { return }

        let newView = XGhostty.SurfaceView(xghostty_app, baseConfig: nil)
        guard workspace.restartTerminatedPane(in: projectID, with: newView) else { return }

        if projectID == workspace.state.focusedProject {
            surfaceTree = workspace.focusedPaneTree
            moveKeyboardFocus(toProjectSurface: SurfaceID(rawValue: newView.id))
        }
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

    @objc private func ghosttyDidNewProjectSplit(_ notification: Notification) {
        // The anchor surface must be within our tree.
        guard let oldView = notification.object as? XGhostty.SurfaceView else { return }
        guard surfaceTree.root?.node(view: oldView) != nil else { return }

        // Notification must contain our base config.
        let configAny = notification.userInfo?[XGhostty.Notification.NewSurfaceConfigKey]
        let config = configAny as? XGhostty.SurfaceConfiguration

        // Determine the direction the new project should be placed in.
        guard let directionAny = notification.userInfo?["direction"] else { return }
        guard let direction = directionAny as? xghostty_action_split_direction_e else { return }
        let splitDirection: SplitTree<ProjectRef>.NewDirection
        switch direction {
        case XGHOSTTY_SPLIT_DIRECTION_RIGHT: splitDirection = .right
        case XGHOSTTY_SPLIT_DIRECTION_LEFT: splitDirection = .left
        case XGHOSTTY_SPLIT_DIRECTION_DOWN: splitDirection = .down
        case XGHOSTTY_SPLIT_DIRECTION_UP: splitDirection = .up
        default: return
        }

        newProjectSplit(at: oldView, direction: splitDirection, baseConfig: config)
    }

    // Returns true when `view` belongs to any project in this workspace.
    //
    // After a project switch the macOS first-responder is updated asynchronously,
    // so the previously focused surface (now in the outgoing project) may still
    // fire action notifications while `surfaceTree` already reflects the newly
    // focused project. Accepting any workspace-member view prevents those actions
    // from silently dropping during that async window.
    private func isInWorkspace(_ view: XGhostty.SurfaceView) -> Bool {
        if surfaceTree.contains(view) { return true }
        return workspace.state.projects.values.contains { $0.paneTree.contains(view) }
    }

    /// The project that owns `view`, or nil when it belongs to no project here.
    ///
    /// `surfaceTree` is checked first because it is the focused project's
    /// source of truth; the workspace's copy of it is only a mirror and can lag
    /// by a change cycle.
    func projectID(containing view: XGhostty.SurfaceView) -> ProjectID? {
        if surfaceTree.contains(view) { return workspace.state.focusedProject }
        return workspace.state.projects.first { $0.value.paneTree.contains(view) }?.key
    }

    @objc private func ghosttyDidRenameProject(_ notification: Notification) {
        // The triggering surface must be within our workspace (not just the
        // currently focused project's tree, to survive the async focus window).
        guard let view = notification.object as? XGhostty.SurfaceView else { return }
        guard isInWorkspace(view) else { return }

        // `rename_project` targets the focused project; enter inline-rename mode.
        workspace.beginRenamingFocusedProject()
    }

    @objc private func ghosttyDidEditProjectNote(_ notification: Notification) {
        // The triggering surface must be within our workspace (not just the
        // currently focused project's tree, to survive the async focus window).
        guard let view = notification.object as? XGhostty.SurfaceView else { return }
        guard isInWorkspace(view) else { return }

        // `edit_project_note` targets the focused project; open the note editor.
        workspace.beginNoteEditingFocusedProject()
    }

    @objc private func ghosttyDidToggleNoteOverview(_ notification: Notification) {
        // The triggering surface must be within our workspace (not just the
        // currently focused project's tree, to survive the async focus window).
        guard let view = notification.object as? XGhostty.SurfaceView else { return }
        guard isInWorkspace(view) else { return }

        // Entering hands the keyboard to the overlay layer so Escape reaches
        // it instead of the terminal (same reasoning as the command palette);
        // the workspace view hands focus back when the overview closes.
        if workspace.toggleNoteOverview() {
            _ = focusedSurface?.resignFirstResponder()
        }
    }

    @objc private func ghosttyDidSetPrimary(_ notification: Notification) {
        // The triggering surface must be within our workspace (not just the
        // currently focused project's tree, to survive the async focus window).
        guard let view = notification.object as? XGhostty.SurfaceView else { return }
        guard isInWorkspace(view) else { return }

        // `set_primary` moves the primary flag to the focused pane; the model
        // enforces the zoom-only rule and rejects a no-op reassignment
        // (SPEC §22.4). Keyboard focus is untouched — the pane is focused
        // already — and the mark overlay re-renders via the state change.
        workspace.setPrimaryToFocusedPane()
    }

    @objc private func ghosttyDidSortProjectsByPriority(_ notification: Notification) {
        // The triggering surface must be within our workspace (not just the
        // currently focused project's tree, to survive the async focus window).
        guard let view = notification.object as? XGhostty.SurfaceView else { return }
        guard isInWorkspace(view) else { return }

        // The model applies the priority ordering to the real layout
        // (SPEC §24.4); focus is id-keyed and untouched, and the ordinals
        // follow the new traversal order automatically.
        workspace.sortVisibleProjectsByPriority()
    }

    @objc private func ghosttyDidSortProjectsByDeadline(_ notification: Notification) {
        // The triggering surface must be within our workspace (not just the
        // currently focused project's tree, to survive the async focus window).
        guard let view = notification.object as? XGhostty.SurfaceView else { return }
        guard isInWorkspace(view) else { return }

        // Same as the priority sort, consuming the deadline ordering.
        workspace.sortVisibleProjectsByDeadline()
    }

    @objc private func ghosttyDidSetProjectTitle(_ notification: Notification) {
        guard let view = notification.object as? XGhostty.SurfaceView else { return }
        guard isInWorkspace(view) else { return }
        guard let title = notification.userInfo?["title"] as? String else { return }
        guard let id = workspace.state.focusedProject else { return }

        // `set_project_title:<name>` sets the focused project's name directly.
        workspace.renameProject(id, to: title)
    }

    @objc private func ghosttyDidGotoProject(_ notification: Notification) {
        // The triggering surface must be within our workspace (not just the
        // currently focused project's tree, to survive the async focus window).
        guard let view = notification.object as? XGhostty.SurfaceView else { return }
        guard isInWorkspace(view) else { return }

        guard let direction = notification.userInfo?[
            XGhostty.Notification.ProjectDirectionKey] as? XGhostty.SplitFocusDirection else { return }

        // Resolve the visible neighbor project in that direction (`SPEC.md` §11.3)
        // and reuse the label-click focus switch, which restores the target
        // project's last-focused pane.
        let treeDirection: SplitTree<ProjectRef>.FocusDirection = direction.toSplitTreeFocusDirection()
        guard let target = workspace.gotoProjectTarget(treeDirection) else { return }
        focusProject(target)
    }

    @objc private func ghosttyDidGotoProjectIndex(_ notification: Notification) {
        // The triggering surface must be within our workspace (not just the
        // currently focused project's tree, to survive the async focus window).
        guard let view = notification.object as? XGhostty.SurfaceView else { return }
        guard isInWorkspace(view) else { return }

        guard let ordinal = notification.userInfo?[
            XGhostty.Notification.GotoProjectIndexKey] as? Int else { return }

        gotoProject(index: ordinal)
    }

    @objc private func ghosttyDidMoveProject(_ notification: Notification) {
        // The triggering surface must be within our workspace (not just the
        // currently focused project's tree, to survive the async focus window).
        guard let view = notification.object as? XGhostty.SurfaceView else { return }
        guard isInWorkspace(view) else { return }

        guard let direction = notification.userInfo?[
            XGhostty.Notification.MoveProjectDirectionKey] as? XGhostty.SplitFocusDirection else { return }

        moveFocusedProject(direction.toSplitTreeFocusDirection())
    }

    @objc private func ghosttyDidResizeProject(_ notification: Notification) {
        // The triggering surface must be within our workspace (not just the
        // currently focused project's tree, to survive the async focus window).
        guard let view = notification.object as? XGhostty.SurfaceView else { return }
        guard isInWorkspace(view) else { return }

        guard let direction = notification.userInfo?[
            XGhostty.Notification.ResizeProjectDirectionKey] as? XGhostty.SplitResizeDirection else { return }
        guard let amount = notification.userInfo?[
            XGhostty.Notification.ResizeProjectAmountKey] as? UInt16 else { return }

        let spatialDirection: SplitTree<ProjectRef>.Spatial.Direction
        switch direction {
        case .up: spatialDirection = .up
        case .down: spatialDirection = .down
        case .left: spatialDirection = .left
        case .right: spatialDirection = .right
        }

        // Convert the pixel amount to a normalized ratio delta against the
        // workspace's content area (the region all visible projects divide). This
        // is exact for a single top-level project split (the common 2-project case)
        // and a graceful approximation for nested project splits, where the LCA
        // split's container is smaller — the divider simply moves a little less
        // than `amount`px. `adjustRatio` clamps the result to [0.1, 0.9].
        let size = window?.contentView?.bounds.size ?? surfaceTree.viewBounds()
        let dimension: CGFloat = switch spatialDirection {
        case .left, .right: size.width
        case .up, .down: size.height
        }
        guard dimension > 0 else { return }
        let ratioDelta = Double(amount) / Double(dimension)

        workspace.resizeFocusedProject(spatialDirection, ratioDelta: ratioDelta)
    }

    @objc private func ghosttyDidEqualizeProjects(_ notification: Notification) {
        // The triggering surface must be within our workspace (not just the
        // currently focused project's tree, to survive the async focus window).
        guard let view = notification.object as? XGhostty.SurfaceView else { return }
        guard isInWorkspace(view) else { return }

        equalizeProjects()
    }

    @objc private func ghosttyDidToggleProjectZoom(_ notification: Notification) {
        // The triggering surface must be within our workspace (not just the
        // currently focused project's tree, to survive the async focus window).
        guard let view = notification.object as? XGhostty.SurfaceView else { return }
        guard isInWorkspace(view) else { return }

        // Toggle project zoom; rendering reacts via `effectiveVisibleProjectTree`
        // (`SPEC.md` §11.6). The focused project stays focused, so `surfaceTree`
        // is untouched. Toggling reshapes the project view tree (split↔single
        // leaf), which re-hosts the same surface views, so re-assert keyboard
        // focus on the triggering surface (mirrors `ghosttyDidToggleSplitZoom`).
        //
        // If the triggering view is from the previously focused project (async
        // focus window), fall back to the first surface in the current project
        // so focus lands inside the window rather than on a stale view.
        workspace.toggleProjectZoom()
        window?.makeKeyAndOrderFront(nil)

        // Releasing the zoom lands in the overall view, where only the primary
        // pane is rendered and keyboard focus belongs on it (SPEC §22.4). The
        // model has already snapped its stored focus; mirror that with the
        // AppKit first responder. While zoomed, the previous behavior holds.
        let focusTarget: XGhostty.SurfaceView
        if workspace.state.zoomedProject == nil,
           let primaryID = workspace.focusedProjectState?.primaryPane,
           let primaryNode = surfaceTree.find(id: primaryID.rawValue),
           case .leaf(let primaryView) = primaryNode {
            focusTarget = primaryView
        } else {
            focusTarget = surfaceTree.contains(view) ? view : (surfaceTree.first ?? view)
        }
        DispatchQueue.main.async {
            XGhostty.moveFocus(to: focusTarget)
        }
    }

    @objc private func ghosttyDidHideProject(_ notification: Notification) {
        // The triggering surface must be within our workspace (not just the
        // currently focused project's tree, to survive the async focus window).
        guard let view = notification.object as? XGhostty.SurfaceView else { return }
        guard isInWorkspace(view) else { return }

        // `hide_project` opens the hide-selection screen (`SPEC.md` §25);
        // the actual hiding happens on the screen's confirm
        // (`confirmHideSelection`).
        workspace.beginHideSelection()
    }

    @objc private func ghosttyDidShowProject(_ notification: Notification) {
        // The triggering surface must be within our workspace (not just the
        // currently focused project's tree, to survive the async focus window).
        guard let view = notification.object as? XGhostty.SurfaceView else { return }
        guard isInWorkspace(view) else { return }

        guard let name = notification.userInfo?[
            XGhostty.Notification.ShowProjectNameKey] as? String else { return }
        guard let id = workspace.hiddenProjectID(named: name) else { return }
        showProject(id)
    }

    @objc private func ghosttyDidCloseProject(_ notification: Notification) {
        // The triggering surface must be within our workspace (not just the
        // currently focused project's tree, to survive the async focus window).
        guard let view = notification.object as? XGhostty.SurfaceView else { return }
        guard isInWorkspace(view) else { return }

        closeFocusedProject()
    }

    @objc private func ghosttyDidEqualizeSplits(_ notification: Notification) {
        // Pane operations are zoom-only (SPEC §22.5).
        guard workspace.paneOperationsEnabled else { return }
        guard let target = notification.object as? XGhostty.SurfaceView else { return }

        // Check if target surface is in current controller's tree
        guard surfaceTree.contains(target) else { return }

        // Equalize the splits
        surfaceTree = surfaceTree.equalized()
    }

    @objc private func ghosttyDidFocusSplit(_ notification: Notification) {
        // Inter-pane focus movement is zoom-only (SPEC §22.5): in the overall
        // view keyboard focus stays on the primary pane.
        guard workspace.paneOperationsEnabled else { return }

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
        // Pane zoom is zoom-only (SPEC §22.5): the overall view already shows
        // exactly one pane per project.
        guard workspace.paneOperationsEnabled else { return }

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
        // reset zoom titlebar button while unfocused that we become focused.
        window?.makeKeyAndOrderFront(nil)

        // Ensure focus stays on the target surface. We lose focus when we do
        // this so we need to grab it again.
        DispatchQueue.main.async {
            XGhostty.moveFocus(to: target)
        }
    }

    @objc private func ghosttyDidResizeSplit(_ notification: Notification) {
        // Pane resize is zoom-only (SPEC §22.5).
        guard workspace.paneOperationsEnabled else { return }

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

        // The target may live in another project — the command palette's "Focus:"
        // entries cover every project's panes — so make its project the focused one
        // first. A hidden project has to be re-shown; a merely unfocused one just
        // needs a focus switch. Both swap `surfaceTree` to the target's panes.
        if !surfaceTree.contains(target) {
            guard let projectID = projectID(containing: target) else { return }
            if workspace.state.hiddenProjectIDs.contains(projectID) {
                showProject(projectID)
            } else {
                focusProject(projectID)
            }

            // `showProject` is a silent no-op at the visible-project cap, so confirm
            // the swap actually happened before we try to focus into it.
            guard surfaceTree.contains(target) else { return }
        }

        // Bring the window to front and focus the surface.
        window?.makeKeyAndOrderFront(nil)

        // In the overall view only the primary pane is rendered, so a
        // non-primary target's view is detached and cannot take focus; focus
        // goes to the project's primary instead (SPEC §22.4).
        var focusTarget = target
        if !workspace.paneOperationsEnabled,
           let primaryID = workspace.focusedProjectState?.primaryPane,
           let primaryNode = surfaceTree.find(id: primaryID.rawValue),
           case .leaf(let primaryView) = primaryNode {
            focusTarget = primaryView
        }

        // We use a small delay to ensure this runs after any UI cleanup
        // (e.g., command palette restoring focus to its original surface).
        XGhostty.moveFocus(to: focusTarget)
        XGhostty.moveFocus(to: focusTarget, delay: 0.1)

        // Show a brief highlight to help the user locate the presented terminal.
        focusTarget.highlight()
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
        // Pane operations (divider resize, pane drop) are zoom-only
        // (SPEC §22.5). The overall view renders no pane dividers or drop
        // zones anyway; this keeps the rule total.
        guard workspace.paneOperationsEnabled else { return }

        switch action {
        case .resize(let resize):
            splitDidResize(node: resize.node, to: resize.ratio)
        case .drop(let drop):
            splitDidDrop(source: drop.payload, destination: drop.destination, zone: drop.zone)
        }
    }

    /// Switch the focused project in response to a project-label click
    /// (`SPEC.md` §7.1). Mirrors `newProjectSplit`'s swap: persist the outgoing
    /// pane tree, flip the focused project, swap `surfaceTree` to the target's
    /// panes, and move keyboard focus into its last-focused pane (§14.12).
    ///
    /// Like `newProjectSplit`, this registers no undo: `replaceSurfaceTree`'s undo
    /// only restores `surfaceTree`, which would mirror the wrong pane tree into
    /// the wrong project after a focus switch. Project-aware undo is a deferred
    /// follow-up (see `TODO.md`).
    func focusProject(_ id: ProjectID) {
        guard workspace.state.focusedProject != id else { return }
        guard workspace.state.projects[id] != nil else { return }

        // Persist the current panes into the outgoing project and flip focus.
        let targetFocus = workspace.switchFocusedProject(
            to: id,
            savingOutgoingPaneTree: surfaceTree)

        // Swap the source-of-truth pane tree to the newly focused project. The
        // resulting `surfaceTreeDidChange` mirrors it back (a no-op) and
        // re-renders the workspace.
        surfaceTree = workspace.focusedPaneTree

        moveKeyboardFocus(toProjectSurface: targetFocus)
    }

    /// Jump to the `index`-th visible project in response to `goto_project:<N>`
    /// (Cmd+1..9). Mirrors `focusProject`'s swap, with one extra twist: unlike the
    /// directional `goto_project`, an index jump also works while zoomed — the
    /// model clears the zoom and moves focus in a single state write, so the
    /// un-zoomed layout and the new focused project render together.
    ///
    /// No-op when the number resolves to nothing, to the zoomed project, or (when
    /// nothing is zoomed) to the already-focused project. Like `focusProject` this
    /// registers no undo: it is a focus change, not a structural mutation.
    func gotoProject(index: Int) {
        guard let result = workspace.gotoProject(
            index: index,
            savingOutgoingPaneTree: surfaceTree) else { return }

        // Swap the source-of-truth pane tree to the newly focused project. When
        // only the zoom was cleared this is the same tree, and the workspace's
        // own change re-renders the project layout.
        surfaceTree = workspace.focusedPaneTree
        moveKeyboardFocus(toProjectSurface: result.focus)
    }

    /// Swap the focused project with its neighbor in `direction` in response to
    /// `move_project`. Only the canonical project tree changes: the focused project and
    /// its panes are untouched (it simply occupies its neighbor's slot), so there
    /// is no `surfaceTree` swap and no keyboard-focus move.
    ///
    /// Registers a project-aware undo ("Move Project") like the other structural
    /// project mutations. No-op when there is no neighbor in that direction.
    func moveFocusedProject(_ direction: SplitTree<ProjectRef>.FocusDirection) {
        let before = workspace.state
        guard workspace.moveFocusedProject(direction) else { return }
        registerWorkspaceUndo("Move Project", undo: before, redo: workspace.state)
    }

    /// Equalize the project layout in response to `equalize_projects` or a
    /// double-click on a project divider (`SPEC.md` §11.5).
    ///
    /// Both entry points land here so they behave identically. Like
    /// `equalize_splits`, this is a ratio-only change and registers no undo.
    func equalizeProjects() {
        workspace.equalizeProjects()
    }

    /// Confirm the hide-selection screen (Enter, `SPEC.md` §25). The model
    /// hides every selected project in one batch and resolves the next focus;
    /// here we swap `surfaceTree` to the surviving focused project's panes and
    /// move keyboard focus, mirroring `focusProject`. No-op when the confirm
    /// is rejected (every visible project selected — the screen stays up) or
    /// when the selection was empty (the screen just closes). Registers a
    /// project-aware undo ("Hide Projects") so the batch hide can be
    /// reversed; the snapshot keeps the hidden projects' panes (their
    /// processes already stay alive via `projects`, §14.7).
    func confirmHideSelection() {
        let before = workspace.state
        guard let result = workspace.confirmHideSelection(
            savingOutgoingPaneTree: surfaceTree) else { return }

        surfaceTree = workspace.focusedPaneTree
        moveKeyboardFocus(toProjectSurface: result.focus)
        registerWorkspaceUndo("Hide Projects", undo: before, redo: workspace.state)
    }

    /// Show the hidden project `id` in response to a shelf pill click or the
    /// `show_project` action (`SPEC.md` §11.8). The model un-hides it, clears any
    /// zoom, and focuses it; here we swap `surfaceTree` to its panes and move
    /// keyboard focus into its last-focused pane. Registers a project-aware undo
    /// ("Show Project") so the reveal can be reversed.
    ///
    /// Silent no-op when `WorkspaceState.maxVisibleProjects` projects are already
    /// visible: the pill just stays on the shelf.
    func showProject(_ id: ProjectID) {
        guard workspace.canShowProject(id) else { return }
        let before = workspace.state
        let targetFocus = workspace.showProject(id, savingOutgoingPaneTree: surfaceTree)

        surfaceTree = workspace.focusedPaneTree
        moveKeyboardFocus(toProjectSurface: targetFocus)
        registerWorkspaceUndo("Show Project", undo: before, redo: workspace.state)
    }

    /// Close the focused project in response to `close_project` or a last-pane
    /// `Cmd+W` (`SPEC.md` §11.9, §11.10, §23.1). This is destructive — it is
    /// the single sanctioned path that loses a project and its information
    /// (note, name, layout slot) — so it always confirms first, regardless of
    /// whether any process is running (deletion protection; the judgment
    /// lives on the model so tests can pin it).
    ///
    /// The `.switched` close registers a project-aware undo ("Close Project"); the
    /// pre-close snapshot retains the closed project's `SurfaceView`s, so its
    /// processes stay alive for the `undoExpiration` window (mirroring
    /// `close_surface` undo). The §18.5 last-project case delegates to the window
    /// close (which quits the app), so it is not wrapped in an undo.
    func closeFocusedProject() {
        guard let project = workspace.focusedProjectState else { return }

        // The focused project's panes are exactly `surfaceTree`.
        let anyLiveProcess = surfaceTree.contains(where: { $0.needsConfirmQuit })
        guard workspace.closeProjectRequiresConfirmation(anyLiveProcess: anyLiveProcess) else {
            performCloseFocusedProject()
            return
        }

        let paneCount = surfaceTree.reduce(into: 0) { count, _ in count += 1 }
        let pane = paneCount == 1 ? "pane" : "panes"
        confirmClose(
            messageText: "Close Project “\(project.name)”?",
            informativeText: "This will close \(paneCount) \(pane) and terminate their processes.",
            confirmButtonTitle: "Close Project"
        ) { [weak self] in
            self?.performCloseFocusedProject()
        }
    }

    /// Apply a confirmed `close_project`: prune the focused project from the project
    /// structure and either swap `surfaceTree` to the nearest remaining project
    /// (terminating the closed project's surfaces as they fall out of scope, §14.8)
    /// or, when it was the only project, delegate to the window close (§18.5).
    private func performCloseFocusedProject() {
        let before = workspace.state
        switch workspace.closeFocusedProject() {
        case .switched(_, let focus):
            surfaceTree = workspace.focusedPaneTree
            moveKeyboardFocus(toProjectSurface: focus)
            registerWorkspaceUndo("Close Project", undo: before, redo: workspace.state)

        case .closedLast:
            // §18.5: emptying the tree routes through `replaceSurfaceTree`, whose
            // `TerminalController` override closes the window (which quits the app).
            replaceSurfaceTree(.init())

        case nil:
            break
        }
    }

    /// Move keyboard focus to `surfaceID` within the (now current) `surfaceTree`,
    /// falling back to its first leaf. Shared tail of every project focus switch
    /// (`focusProject` / `goto_project` / `hide_project` / `show_project`, §14.12).
    private func moveKeyboardFocus(toProjectSurface surfaceID: SurfaceID?) {
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

        // We are a single-window app, so a surface that isn't in our tree isn't
        // anywhere we can move it from.
        XGhostty.logger.warning("source surface not found in this window during drop")
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

        // If we have no surfaces in any project, close. Closing this window tears
        // down every project, not just the focused one, so both the emptiness check
        // and the confirmation check below span all of them (`SPEC.md` §14.7).
        let surfaces = allSurfaces
        if surfaces.isEmpty { return true }

        // If we already have an alert, continue with it
        guard alert == nil else { return false }

        // If our surfaces don't require confirmation, close.
        if !surfaces.contains(where: { $0.needsConfirmQuit }) { return true }

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
        focusedSurface?.findPrevious(sender)
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

        // Pane operations are zoom-only (SPEC §22.5): their menu items gray
        // out in the overall view, matching the action-layer no-op guards.
        case #selector(splitRight), #selector(splitLeft),
             #selector(splitDown), #selector(splitUp),
             #selector(splitZoom),
             #selector(splitMoveFocusPrevious), #selector(splitMoveFocusNext),
             #selector(splitMoveFocusAbove), #selector(splitMoveFocusBelow),
             #selector(splitMoveFocusLeft), #selector(splitMoveFocusRight),
             #selector(equalizeSplits(_:)),
             #selector(moveSplitDividerUp), #selector(moveSplitDividerDown),
             #selector(moveSplitDividerLeft), #selector(moveSplitDividerRight):
            return workspace.paneOperationsEnabled

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
