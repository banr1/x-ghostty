import Foundation
import Cocoa
import SwiftUI
import Combine
import XGhosttyKit

/// The controller for the app's one and only terminal window.
///
/// XGhostty is a single-window app: exactly one `TerminalController` exists for the
/// process lifetime, created at launch (or by state restoration). Projects and splits
/// provide all layout within that window, and closing it quits the app.
class TerminalController: BaseTerminalController {
    override var windowNibName: NSNib.Name? {
        let defaultValue = "Terminal"

        guard let appDelegate = NSApp.delegate as? AppDelegate else { return defaultValue }
        let config = appDelegate.ghostty.config

        // If we have no window decorations, there's no reason to do anything but
        // the default titlebar (because there will be no titlebar).
        if !config.windowDecorations {
            return defaultValue
        }

        return switch config.macosTitlebarStyle {
        case .native: "Terminal"
        case .hidden: "TerminalHiddenTitlebar"
        case .transparent: "TerminalTransparentTitlebar"
        }
    }

    /// The single terminal controller for this app, if one has been created.
    ///
    /// This is a **strong** reference and it is the app's only owner of the
    /// controller: the sole other strong chain is the retain cycle through the
    /// window's `contentView` → `NSHostingView` → `TerminalView` → the
    /// `@ObservedObject` view model (us), and `BaseTerminalController.windowWillClose`
    /// tears that down by niling `contentView`.
    ///
    /// It is assigned at the *end of `init`* (not `windowDidLoad`) so that it is
    /// non-nil the instant a controller exists. Every creation path — launch
    /// `create()`, the `openFile` seed, and `TerminalWindowRestoration` — goes
    /// through `init`, so the `shared == nil` guards elsewhere are synchronous
    /// and reliable even before the nib has loaded (nib loading is deferred by a
    /// runloop turn via `scheduleInitialPresentation`).
    static private(set) var shared: TerminalController?

    /// The initial window presentation is deferred by one runloop turn so AppKit can
    /// settle window state first. Closing must cancel it to avoid re-showing a window
    /// that was already closed.
    private var pendingInitialPresentation: DispatchWorkItem?

    /// Set once we begin tearing the window down so the surface-tree observer doesn't
    /// try to close the window a second time.
    private var isClosing: Bool = false

    /// This is set to false by init if the window managed by this controller should not be restorable.
    /// For example, terminals executing custom scripts are not restorable.
    private var restorable: Bool = true

    /// The configuration derived from the XGhostty config so we don't need to rely on references.
    private(set) var derivedConfig: DerivedConfig

    /// The notification cancellable for focused surface property changes.
    private var surfaceAppearanceCancellables: Set<AnyCancellable> = []

    init(_ ghostty: XGhostty.App,
         withBaseConfig base: XGhostty.SurfaceConfiguration? = nil,
         withSurfaceTree tree: SplitTree<XGhostty.SurfaceView>? = nil,
         withWorkspace workspace: WorkspaceState? = nil,
         parent: NSWindow? = nil
    ) {
        // The window we manage is not restorable if we've specified a command
        // to execute. We do this because the restored window is meaningless at the
        // time of writing this: it'd just restore to a shell in the same directory
        // as the script. We may want to revisit this behavior when we have scrollback
        // restoration.
        self.restorable = (base?.command ?? "") == ""

        // Setup our initial derived config based on the current app config
        self.derivedConfig = DerivedConfig(ghostty.config)

        super.init(ghostty, baseConfig: base, surfaceTree: tree, workspace: workspace)

        // Setup our notifications for behaviors
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(onToggleFullscreen),
            name: XGhostty.Notification.ghosttyToggleFullscreen,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(onResetWindowSize),
            name: .ghosttyResetWindowSize,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(ghosttyConfigDidChange(_:)),
            name: .ghosttyConfigDidChange,
            object: nil
        )

        // Record ourselves as the app's single terminal controller. This must
        // happen here rather than in `windowDidLoad` so that `shared` is non-nil
        // for callers that run before the nib loads (see the `shared` docs).
        Self.shared = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported for this view")
    }

    deinit {
        // Remove all of our notificationcenter subscriptions
        let center = NotificationCenter.default
        center.removeObserver(self)
    }

    private func cancelPendingInitialPresentation() {
        pendingInitialPresentation?.cancel()
        pendingInitialPresentation = nil
    }

    private func scheduleInitialPresentation(_ block: @escaping () -> Void) {
        cancelPendingInitialPresentation()

        var scheduledWorkItem: DispatchWorkItem?
        scheduledWorkItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            defer { self.pendingInitialPresentation = nil }
            guard pendingInitialPresentation?.isCancelled == false else { return }
            block()
        }

        let workItem = scheduledWorkItem!
        pendingInitialPresentation = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    // MARK: Base Controller Overrides

    override func surfaceTreeDidChange(from: SplitTree<XGhostty.SurfaceView>, to: SplitTree<XGhostty.SurfaceView>) {
        super.surfaceTreeDidChange(from: from, to: to)

        // Whenever our surface tree changes in any way (new split, close split, etc.)
        // we want to invalidate our state.
        invalidateRestorableState()

        // Update our zoom state
        if let window = window as? TerminalWindow {
            window.surfaceIsZoomed = to.zoomed != nil
        }

        // If our surface tree is now empty then we close our window (which quits).
        if to.isEmpty && !isClosing {
            self.window?.close()
        }
    }

    override func replaceSurfaceTree(
        _ newTree: SplitTree<XGhostty.SurfaceView>,
        moveFocusTo newView: XGhostty.SurfaceView? = nil,
        moveFocusFrom oldView: XGhostty.SurfaceView? = nil,
        undoAction: String? = nil
    ) {
        // An empty tree means there's nothing left to show, so we close the window
        // (which terminates the app). Callers that reach here have already confirmed.
        if newTree.isEmpty {
            closeWindowImmediately()
            return
        }

        super.replaceSurfaceTree(
            newTree,
            moveFocusTo: newView,
            moveFocusFrom: oldView,
            undoAction: undoAction)
    }

    // MARK: Terminal Creation

    /// Create the app's single terminal window and show it.
    ///
    /// This is only ever called once per process: at launch when state restoration
    /// didn't already produce a window. Everything else (projects, splits) happens
    /// inside the window this returns.
    @discardableResult
    static func create(
        _ ghostty: XGhostty.App,
        withBaseConfig baseConfig: XGhostty.SurfaceConfiguration? = nil
    ) -> TerminalController {
        let c = TerminalController(ghostty, withBaseConfig: baseConfig)

        // Apply the configured fullscreen mode, if any.
        if let fullscreenMode = ghostty.config.windowFullscreen {
            switch fullscreenMode {
            case .native:
                // Native has to be done immediately so that our stylemask contains
                // fullscreen for the logic later in this method.
                c.toggleFullscreen(mode: .native)

            case .nonNative, .nonNativeVisibleMenu, .nonNativePaddedNotch:
                // If we're non-native then we have to do it on a later loop
                // so that the content view is setup.
                DispatchQueue.main.async {
                    c.toggleFullscreen(mode: fullscreenMode)
                }
            }
        }

        // We defer presentation by a runloop turn so AppKit has settled the window
        // state (content view, toolbar, default size) before we show it.
        c.scheduleInitialPresentation {
            c.showWindow(self)
            NSApp.activate(ignoringOtherApps: true)
        }

        return c
    }

    // MARK: - Methods

    @objc private func ghosttyConfigDidChange(_ notification: Notification) {
        // Get our managed configuration object out
        guard let config = notification.userInfo?[
            Notification.Name.GhosttyConfigChangeKey
        ] as? XGhostty.Config else { return }

        // If this is an app-level config update then we update some things.
        if notification.object == nil {
            // Update our derived config
            self.derivedConfig = DerivedConfig(config)

            // If we have no surfaces in our window (is that possible?) then we update
            // our window appearance based on the root config. If we have surfaces, we
            // don't call this because focused surface changes will trigger appearance updates.
            if surfaceTree.isEmpty {
                syncAppearance(.init(config))
            }

            return
        }
        /// Surface-level config will be updated in
        /// ``XGhostty/XGhostty/SurfaceView/derivedConfig`` then
        /// ``TerminalController/focusedSurfaceDidChange(to:)``
    }

    override func syncAppearance() {
        // When our focus changes, we update our window appearance based on the
        // currently focused surface.
        guard let focusedSurface else { return }
        syncAppearance(focusedSurface.derivedConfig)
    }

    private func syncAppearance(_ surfaceConfig: XGhostty.SurfaceView.DerivedConfig) {
        // Let our window handle its own appearance
        guard let window = window as? TerminalWindow else { return }

        // Sync our zoom state for splits
        window.surfaceIsZoomed = surfaceTree.zoomed != nil

        // Set the font for the window and tab titles.
        if let titleFontName = surfaceConfig.windowTitleFontFamily {
            window.titlebarFont = NSFont(name: titleFontName, size: NSFont.systemFontSize)
        } else {
            window.titlebarFont = nil
        }

        // Call this last in case it uses any of the properties above.
        window.syncAppearance(surfaceConfig)
        terminalViewContainer?.ghosttyConfigDidChange(ghostty.config, preferredBackgroundColor: window.preferredBackgroundColor)
    }

    /// Adjusts the given frame for the configured window position.
    func adjustForWindowPosition(frame: NSRect, on screen: NSScreen) -> NSRect {
        guard let x = derivedConfig.windowPositionX else { return frame }
        guard let y = derivedConfig.windowPositionY else { return frame }

        // Convert top-left coordinates to bottom-left origin using our utility extension
        let origin = screen.origin(
            fromTopLeftOffsetX: CGFloat(x),
            offsetY: CGFloat(y),
            windowSize: frame.size)

        // Clamp the origin to ensure the window stays fully visible on screen
        var safeOrigin = origin
        let vf = screen.visibleFrame
        safeOrigin.x = min(max(safeOrigin.x, vf.minX), vf.maxX - frame.width)
        safeOrigin.y = min(max(safeOrigin.y, vf.minY), vf.maxY - frame.height)

        // Return our new origin
        var result = frame
        result.origin = safeOrigin
        return result
    }

    /// This is called anytime a node in the surface tree is being removed.
    override func closeSurface(
        _ node: SplitTree<XGhostty.SurfaceView>.Node,
        withConfirmation: Bool = true
    ) {
        // If this isn't the root then we're dealing with a split closure.
        if surfaceTree.root != node {
            super.closeSurface(node, withConfirmation: withConfirmation)
            return
        }

        // We're closing the root of the tree, which means the whole window.
        closeWindow(nil)
    }

    // MARK: - NSWindowController

    override func windowWillLoad() {
        // We do NOT want to cascade because we handle this manually from the manager.
        shouldCascadeWindows = false
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        guard let window else { return }

        // I copy this because we may change the source in the future but also because
        // I regularly audit our codebase for "ghostty.config" access because generally
        // you shouldn't use it. Its safe in this case because for a new window we should
        // use whatever the latest app-level config is.
        let config = ghostty.config

        // Setting all three of these is required for restoration to work.
        window.isRestorable = restorable
        if restorable {
            window.restorationClass = TerminalWindowRestoration.self
            window.identifier = .init(String(describing: TerminalWindowRestoration.self))
        }

        // If we have only a single surface (no splits) and there is a default size then
        // we should resize to that default size.
        if case let .leaf(view) = surfaceTree.root {
            // If this is our first surface then our focused surface will be nil
            // so we force the focused surface to the leaf.
            focusedSurface = view
        }

        // Initialize our content view to the SwiftUI root
        let container = TerminalViewContainer {
            TerminalView(ghostty: ghostty, viewModel: self, delegate: self)
        }

        // Set the initial content size on the container so that
        // intrinsicContentSize returns the correct value immediately,
        // without waiting for @FocusedValue to propagate through the
        // SwiftUI focus chain.
        container.initialContentSize = focusedSurface?.initialSize

        window.contentView = container

        // If we have a default size, we want to apply it.
        if let defaultSize {
            defaultSize.apply(to: window)

            if case .contentIntrinsicSize = defaultSize {
                if let screen = window.screen ?? NSScreen.main {
                    let frame = self.adjustForWindowPosition(frame: window.frame, on: screen)
                    window.setFrameOrigin(frame.origin)
                }
            }
        }

        // XGhostty is a single-window app: never let AppKit tab this window with
        // anything, no matter the system "prefer tabs" setting.
        window.tabbingMode = .disallowed

        // Apply any additional appearance-related properties to the new window. We
        // apply this based on the root config but change it later based on surface
        // config (see focused surface change callback).
        syncAppearance(.init(config))
    }

    /// Setup correct window frame before showing the window
    override func showWindow(_ sender: Any?) {
        guard let terminalWindow = window as? TerminalWindow else { return }

        // Set the initial window position. This must happen after the window
        // is fully set up (content view, toolbar, default size) so that
        // decorations added by subclass awakeFromNib (e.g. toolbar for tabs
        // style) don't change the frame after the position is restored.
        let originChanged = terminalWindow.setInitialWindowPosition(
            x: derivedConfig.windowPositionX,
            y: derivedConfig.windowPositionY,
        )
        let restored = LastWindowPosition.shared.restore(
            terminalWindow,
            origin: !originChanged,
            size: defaultSize == nil,
        )

        // If nothing is changed for the frame,
        // we should center the window
        if !originChanged, !restored {
            // This doesn't work in `windowDidLoad` somehow
            terminalWindow.center()
        }

        super.showWindow(sender)
    }

    // MARK: NSWindowDelegate

    override func windowShouldClose(_ sender: NSWindow) -> Bool {
        // We always close explicitly (after confirmation) rather than letting
        // AppKit do it, so that we can tear down every project's surfaces first.
        closeWindow(nil)
        return false
    }

    override func windowWillClose(_ notification: Notification) {
        // NOTE: `super.windowWillClose` nils out `window.contentView`, which breaks
        // the SwiftUI retain cycle that would otherwise keep us alive. `Self.shared`
        // is the app's strong owner and it is deliberately released LAST, below,
        // so everything in between runs against a live `self`.
        super.windowWillClose(notification)
        cancelPendingInitialPresentation()

        // We are the app's only window, so its closure ends the app. Every surface
        // has already been released by `closeWindowImmediately` (or the tree emptied
        // on its own), so termination won't ask for confirmation again.
        (NSApp.delegate as? AppDelegate)?.terminalWindowWillClose()

        // Drop the app's ownership of us. `shared` must read nil from here on, but
        // the actual release is handed to the next runloop turn so that unwinding
        // the AppKit close machinery still on the stack beneath us can never touch
        // a deallocated controller. In practice the app terminates first (the
        // delegate above async-terminates), so this block simply never runs and we
        // are freed by process exit.
        guard Self.shared === self else { return }
        let lastStrongRef = self
        Self.shared = nil
        DispatchQueue.main.async { withExtendedLifetime(lastStrongRef) {} }
    }

    override func windowDidBecomeKey(_ notification: Notification) {
        super.windowDidBecomeKey(notification)
        terminalViewContainer?.updateGlassTintOverlay(isKeyWindow: true)
    }

    override func windowDidResignKey(_ notification: Notification) {
        super.windowDidResignKey(notification)
        terminalViewContainer?.updateGlassTintOverlay(isKeyWindow: false)
    }

    override func windowDidMove(_ notification: Notification) {
        super.windowDidMove(notification)

        // Whenever we move save our last position for the next start.
        LastWindowPosition.shared.save(window)
    }

    override func windowDidResize(_ notification: Notification) {
        super.windowDidResize(notification)

        // Whenever we resize save our last position and size for the next start.
        LastWindowPosition.shared.save(window)
    }

    func windowDidBecomeMain(_ notification: Notification) {
        // Whenever we get focused, use that as our last window position for
        // restart. This differs from Terminal.app but matches iTerm2 behavior
        // and I think its sensible.
        LastWindowPosition.shared.save(window)
    }

    // Called when the window will be encoded. We handle the data encoding here in the
    // window controller.
    func window(_ window: NSWindow, willEncodeRestorableState state: NSCoder) {
        let data = TerminalRestorableState(from: self)
        data.encode(with: state)
    }

    // MARK: First Responder

    @IBAction func returnToDefaultSize(_ sender: Any?) {
        guard let window, let defaultSize else { return }
        defaultSize.apply(to: window)
    }

    /// Close the window, asking for confirmation if any project still has a running
    /// process. Closing the window quits the app.
    @IBAction override func closeWindow(_ sender: Any?) {
        guard window != nil else { return }

        // Every project dies with the window, not just the focused one. This is
        // checked before the re-entrancy guard so that a close that no longer
        // needs confirmation (e.g. the last process exited while a confirmation
        // sheet was up) still closes the window.
        guard needsCloseConfirmation else {
            closeWindowImmediately()
            return
        }

        // Re-entrancy guard: if a confirmation sheet is already up, a second
        // entry (another Cmd+W, the red X, a `close_surface` on the root) must
        // never stack a new sheet nor bypass the pending one.
        guard !isShowingConfirmation else { return }

        confirmClose(
            messageText: "Quit XGhostty?",
            informativeText: "All terminal sessions will be terminated.",
            confirmButtonTitle: "Quit",
        ) {
            self.closeWindowImmediately()
        }
    }

    /// Close the window immediately and without confirmation, releasing every
    /// project's surfaces first so no shell outlives the window.
    func closeWindowImmediately() {
        guard let window else { return }
        guard !isClosing else { return }
        isClosing = true

        cancelPendingInitialPresentation()

        // Release every project's surfaces. It must clear all projects, not just
        // `surfaceTree`: the unfocused and hidden projects' surfaces are owned by
        // the workspace, and leaving them retained would keep their shells
        // running after the window is gone.
        removeAllSurfaces()

        window.close()
    }

    @IBAction func toggleGhosttyFullScreen(_ sender: Any?) {
        guard let surface = focusedSurface?.surface else { return }
        ghostty.toggleFullscreen(surface: surface)
    }

    @IBAction func toggleTerminalInspector(_ sender: Any?) {
        guard let surface = focusedSurface?.surface else { return }
        ghostty.toggleTerminalInspector(surface: surface)
    }

    // MARK: - TerminalViewDelegate

    override func focusedSurfaceDidChange(to: XGhostty.SurfaceView?) {
        super.focusedSurfaceDidChange(to: to)

        // We always cancel our event listener
        surfaceAppearanceCancellables.removeAll()

        // When our focus changes, we update our window appearance based on the
        // currently focused surface.
        guard let focusedSurface else { return }
        syncAppearance(focusedSurface.derivedConfig)

        // We also want to get notified of certain changes to update our appearance.
        focusedSurface.$derivedConfig
            .dropFirst()
            .sink { [weak self, weak focusedSurface] _ in self?.syncAppearanceOnPropertyChange(focusedSurface) }
            .store(in: &surfaceAppearanceCancellables)
        focusedSurface.$backgroundColor
            .dropFirst()
            .sink { [weak self, weak focusedSurface] _ in self?.syncAppearanceOnPropertyChange(focusedSurface) }
            .store(in: &surfaceAppearanceCancellables)
    }

    private func syncAppearanceOnPropertyChange(_ surface: XGhostty.SurfaceView?) {
        guard let surface else { return }
        DispatchQueue.main.async { [weak self, weak surface] in
            guard let surface else { return }
            guard let self else { return }
            guard self.focusedSurface == surface else { return }
            self.syncAppearance(surface.derivedConfig)
        }
    }

    // MARK: - Notifications

    @objc private func onResetWindowSize(notification: SwiftUI.Notification) {
        guard let target = notification.object as? XGhostty.SurfaceView else { return }
        guard surfaceTree.contains(target) else { return }
        returnToDefaultSize(nil)
    }

    @objc private func onToggleFullscreen(notification: SwiftUI.Notification) {
        guard let target = notification.object as? XGhostty.SurfaceView else { return }
        guard target == self.focusedSurface else { return }

        // Get the fullscreen mode we want to toggle
        let fullscreenMode: FullscreenMode
        if let any = notification.userInfo?[XGhostty.Notification.FullscreenModeKey],
           let mode = any as? FullscreenMode {
            fullscreenMode = mode
        } else {
            XGhostty.logger.warning("no fullscreen mode specified or invalid mode, doing nothing")
            return
        }

        toggleFullscreen(mode: fullscreenMode)
    }

    struct DerivedConfig {
        let backgroundColor: Color
        let macosWindowButtons: XGhostty.MacOSWindowButtons
        let macosTitlebarStyle: XGhostty.Config.MacOSTitlebarStyle
        let maximize: Bool
        let windowPositionX: Int16?
        let windowPositionY: Int16?

        init() {
            self.backgroundColor = Color(NSColor.windowBackgroundColor)
            self.macosWindowButtons = .visible
            self.macosTitlebarStyle = .default
            self.maximize = false
            self.windowPositionX = nil
            self.windowPositionY = nil
        }

        init(_ config: XGhostty.Config) {
            self.backgroundColor = config.backgroundColor
            self.macosWindowButtons = config.macosWindowButtons
            self.macosTitlebarStyle = config.macosTitlebarStyle
            self.maximize = config.maximize
            self.windowPositionX = config.windowPositionX
            self.windowPositionY = config.windowPositionY
        }
    }
}

// MARK: NSMenuItemValidation

extension TerminalController {
    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(returnToDefaultSize):
            guard let window else { return false }

            // Native fullscreen windows can't revert to default size.
            if window.styleMask.contains(.fullScreen) {
                return false
            }

            // If we're fullscreen at all then we can't change size
            if fullscreenStyle?.isFullscreen ?? false {
                return false
            }

            // If our window is already the default size or we don't have a
            // default size, then disable.
            return defaultSize?.isChanged(for: window) ?? false

        default:
            return super.validateMenuItem(item)
        }
    }
}

// MARK: Default Size

extension TerminalController {
    /// The possible default sizes for a terminal. The size can't purely be known as a
    /// window frame because if we set `window-width/height` then it is based
    /// on content size.
    enum DefaultSize {
        /// A frame, set with `window.setFrame`
        case frame(NSRect)

        /// A content size, set with `window.setContentSize`
        case contentIntrinsicSize

        func isChanged(for window: NSWindow) -> Bool {
            switch self {
            case .frame(let rect):
                return window.frame != rect
            case .contentIntrinsicSize:
                guard let view = window.contentView else {
                    return false
                }

                return view.frame.size != view.intrinsicContentSize
            }
        }

        func apply(to window: NSWindow) {
            switch self {
            case .frame(let rect):
                window.setFrame(rect, display: true)
            case .contentIntrinsicSize:
                guard let size = window.contentView?.intrinsicContentSize else {
                    return
                }

                window.setContentSize(size)
                window.constrainToScreen()
            }
        }
    }

    private var defaultSize: DefaultSize? {
        if derivedConfig.maximize, let screen = window?.screen ?? NSScreen.main {
            // Maximize takes priority, we take up the full screen we're on.
            return .frame(screen.visibleFrame)
        } else if focusedSurface?.initialSize != nil {
            // Initial size as requested by the configuration (e.g. `window-width`)
            // takes next priority.
            return .contentIntrinsicSize
        } else {
            return nil
        }
    }
}
