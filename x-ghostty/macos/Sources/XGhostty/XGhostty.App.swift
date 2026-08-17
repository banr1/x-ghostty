import SwiftUI
import UserNotifications
import XGhosttyKit

protocol GhosttyAppDelegate: AnyObject {
    #if os(macOS)
    /// Called when a callback needs access to a specific surface. This should return nil
    /// when the surface is no longer valid.
    func findSurface(forUUID uuid: UUID) -> XGhostty.SurfaceView?
    #endif
}

extension XGhostty {
    // IMPORTANT: THIS IS NOT DONE.
    // This is a refactor/redo of XGhostty.AppState so that it supports both macOS and iOS
    class App: ObservableObject {
        enum Readiness: String {
            case loading, error, ready
        }

        /// Optional delegate
        weak var delegate: GhosttyAppDelegate?

        /// The readiness value of the state.
        @Published var readiness: Readiness = .loading

        /// The global app configuration. This defines the app level configuration plus any behavior
        /// for new windows, tabs, etc. Note that when creating a new window, it may inherit some
        /// configuration (i.e. font size) from the previously focused window. This would override this.
        @Published private(set) var config: Config

        /// Preferred config file than the default ones
        private var configPath: String?
        /// The ghostty app instance. We only have one of these for the entire app, although I guess
        /// in theory you can have multiple... I don't know why you would...
        @Published var app: xghostty_app_t? {
            didSet {
                guard let old = oldValue else { return }
                xghostty_app_free(old)
            }
        }

        /// True if we need to confirm before quitting.
        var needsConfirmQuit: Bool {
            guard let app = app else { return false }
            return xghostty_app_needs_confirm_quit(app)
        }

        init(configPath: String? = nil) {
            self.configPath = configPath
            // Initialize the global configuration.
            self.config = Config(at: configPath)
            if self.config.config == nil {
                readiness = .error
                return
            }

            // Create our "runtime" config. The "runtime" is the configuration that ghostty
            // uses to interface with the application runtime environment.
            var runtime_cfg = xghostty_runtime_config_s(
                userdata: Unmanaged.passUnretained(self).toOpaque(),
                supports_selection_clipboard: true,
                wakeup_cb: { userdata in App.wakeup(userdata) },
                action_cb: { app, target, action in App.action(app!, target: target, action: action) },
                read_clipboard_cb: { userdata, loc, state in App.readClipboard(userdata, location: loc, state: state) },
                confirm_read_clipboard_cb: { userdata, str, state, request in App.confirmReadClipboard(userdata, string: str, state: state, request: request ) },
                write_clipboard_cb: { userdata, loc, content, len, confirm in
                    App.writeClipboard(userdata, location: loc, content: content, len: len, confirm: confirm) },
                close_surface_cb: { userdata, processAlive in App.closeSurface(userdata, processAlive: processAlive) }
            )

            // Create the ghostty app.
            guard let app = xghostty_app_new(&runtime_cfg, config.config) else {
                logger.critical("xghostty_app_new failed")
                readiness = .error
                return
            }
            self.app = app

#if os(macOS)
            // Set our initial focus state
            xghostty_app_set_focus(app, NSApp.isActive)

            let center = NotificationCenter.default
            center.addObserver(
                self,
                selector: #selector(keyboardSelectionDidChange(notification:)),
                name: NSTextInputContext.keyboardSelectionDidChangeNotification,
                object: nil)
            center.addObserver(
                self,
                selector: #selector(applicationDidBecomeActive(notification:)),
                name: NSApplication.didBecomeActiveNotification,
                object: nil)
            center.addObserver(
                self,
                selector: #selector(applicationDidResignActive(notification:)),
                name: NSApplication.didResignActiveNotification,
                object: nil)
#endif

            self.readiness = .ready
        }

        deinit {
            // This will force the didSet callbacks to run which free.
            self.app = nil

#if os(macOS)
            NotificationCenter.default.removeObserver(self)
#endif
        }

        // MARK: App Operations

        func appTick() {
            guard let app = self.app else { return }
            xghostty_app_tick(app)
        }

        private static func openConfig(_ app: xghostty_app_t) {
            guard let app_ud = xghostty_app_userdata(app) else { return }
            let app = Unmanaged<App>.fromOpaque(app_ud).takeUnretainedValue()
            app.openConfig()
        }

        func openConfig() {
            let str = configPath ?? XGhostty.AllocatedString(xghostty_config_open_path()).string
            guard !str.isEmpty else { return }
            #if os(macOS)
            let fileURL = URL(fileURLWithPath: str).absoluteString
            var action = xghostty_action_open_url_s()
            action.kind = XGHOSTTY_ACTION_OPEN_URL_KIND_TEXT
            fileURL.withCString { cStr in
                action.url = cStr
                action.len = UInt(fileURL.count)
                _ = App.openURL(action)
            }
            #else
            fatalError("Unsupported platform for opening config file")
            #endif
        }

        /// Reload the configuration.
        func reloadConfig(soft: Bool = false) {
            guard let app = self.app else { return }

            // Soft updates just call with our existing config
            if soft {
                xghostty_app_update_config(app, config.config!)
                return
            }

            // Hard or full updates have to reload the full configuration
            let newConfig = Config(at: configPath)
            guard newConfig.loaded else {
                XGhostty.logger.warning("failed to reload configuration")
                return
            }

            xghostty_app_update_config(app, newConfig.config!)
            /// applied config will be updated in ``Self.configChange(_:target:v:)``
        }

        func reloadConfig(surface: xghostty_surface_t, soft: Bool = false) {
            // Soft updates just call with our existing config
            if soft {
                xghostty_surface_update_config(surface, config.config!)
                return
            }

            // Hard or full updates have to reload the full configuration.
            // NOTE: We never set this on self.config because this is a surface-only
            // config. We free it after the call.
            let newConfig = Config(at: configPath)
            guard newConfig.loaded else {
                XGhostty.logger.warning("failed to reload configuration")
                return
            }

            xghostty_surface_update_config(surface, newConfig.config!)
        }

        /// Request that the given surface is closed. This will trigger the full normal surface close event
        /// cycle which will call our close surface callback.
        func requestClose(surface: xghostty_surface_t) {
            xghostty_surface_request_close(surface)
        }

        func split(surface: xghostty_surface_t, direction: xghostty_action_split_direction_e) {
            xghostty_surface_split(surface, direction)
        }

        func splitMoveFocus(surface: xghostty_surface_t, direction: SplitFocusDirection) {
            xghostty_surface_split_focus(surface, direction.toNative())
        }

        func splitResize(surface: xghostty_surface_t, direction: SplitResizeDirection, amount: UInt16) {
            xghostty_surface_split_resize(surface, direction.toNative(), amount)
        }

        func splitEqualize(surface: xghostty_surface_t) {
            xghostty_surface_split_equalize(surface)
        }

        func splitToggleZoom(surface: xghostty_surface_t) {
            let action = "toggle_split_zoom"
            if !xghostty_surface_binding_action(surface, action, UInt(action.lengthOfBytes(using: .utf8))) {
                logger.warning("action failed action=\(action, privacy: .public)")
            }
        }

        func toggleFullscreen(surface: xghostty_surface_t) {
            let action = "toggle_fullscreen"
            if !xghostty_surface_binding_action(surface, action, UInt(action.lengthOfBytes(using: .utf8))) {
                logger.warning("action failed action=\(action, privacy: .public)")
            }
        }

        enum FontSizeModification {
            case increase(Int)
            case decrease(Int)
            case reset
        }

        func changeFontSize(surface: xghostty_surface_t, _ change: FontSizeModification) {
            let action: String
            switch change {
            case .increase(let amount):
                action = "increase_font_size:\(amount)"
            case .decrease(let amount):
                action = "decrease_font_size:\(amount)"
            case .reset:
                action = "reset_font_size"
            }
            if !xghostty_surface_binding_action(surface, action, UInt(action.lengthOfBytes(using: .utf8))) {
                logger.warning("action failed action=\(action, privacy: .public)")
            }
        }

        func toggleTerminalInspector(surface: xghostty_surface_t) {
            let action = "inspector:toggle"
            if !xghostty_surface_binding_action(surface, action, UInt(action.lengthOfBytes(using: .utf8))) {
                logger.warning("action failed action=\(action, privacy: .public)")
            }
        }

        func resetTerminal(surface: xghostty_surface_t) {
            let action = "reset"
            if !xghostty_surface_binding_action(surface, action, UInt(action.lengthOfBytes(using: .utf8))) {
                logger.warning("action failed action=\(action, privacy: .public)")
            }
        }

        #if os(iOS)
        // MARK: XGhostty Callbacks (iOS)

        static func wakeup(_ userdata: UnsafeMutableRawPointer?) {}
        static func action(_ app: xghostty_app_t, target: xghostty_target_s, action: xghostty_action_s) -> Bool { return false }
        static func readClipboard(
            _ userdata: UnsafeMutableRawPointer?,
            location: xghostty_clipboard_e,
            state: UnsafeMutableRawPointer?
        ) -> Bool {
            return false
        }

        static func confirmReadClipboard(
            _ userdata: UnsafeMutableRawPointer?,
            string: UnsafePointer<CChar>?,
            state: UnsafeMutableRawPointer?,
            request: xghostty_clipboard_request_e
        ) {}

        static func writeClipboard(
            _ userdata: UnsafeMutableRawPointer?,
            location: xghostty_clipboard_e,
            content: UnsafePointer<xghostty_clipboard_content_s>?,
            len: Int,
            confirm: Bool
        ) {}

        static func closeSurface(_ userdata: UnsafeMutableRawPointer?, processAlive: Bool) {}
        #endif

        #if os(macOS)

        // MARK: Notifications

        // Called when the selected keyboard changes. We have to notify XGhostty so that
        // it can reload the keyboard mapping for input.
        @objc private func keyboardSelectionDidChange(notification: NSNotification) {
            guard let app = self.app else { return }
            xghostty_app_keyboard_changed(app)
        }

        // Called when the app becomes active.
        @objc private func applicationDidBecomeActive(notification: NSNotification) {
            guard let app = self.app else { return }
            xghostty_app_set_focus(app, true)
        }

        // Called when the app becomes inactive.
        @objc private func applicationDidResignActive(notification: NSNotification) {
            guard let app = self.app else { return }
            xghostty_app_set_focus(app, false)
        }

        // MARK: XGhostty Callbacks (macOS)

        static func closeSurface(_ userdata: UnsafeMutableRawPointer?, processAlive: Bool) {
            let surface = self.surfaceUserdata(from: userdata)
            NotificationCenter.default.post(name: Notification.ghosttyCloseSurface, object: surface, userInfo: [
                "process_alive": processAlive,
            ])
        }

        static func readClipboard(
            _ userdata: UnsafeMutableRawPointer?,
            location: xghostty_clipboard_e,
            state: UnsafeMutableRawPointer?
        ) -> Bool {
            let surfaceView = self.surfaceUserdata(from: userdata)
            guard let surface = surfaceView.surface else { return false }

            // Get our pasteboard
            guard let pasteboard = NSPasteboard.ghostty(location) else { return false }

            // Return false if there is no text-like clipboard content so
            // performable paste bindings can pass through to the terminal.
            guard let str = pasteboard.getOpinionatedStringContents() else { return false }

            completeClipboardRequest(surface, data: str, state: state)
            return true
        }

        static func confirmReadClipboard(
            _ userdata: UnsafeMutableRawPointer?,
            string: UnsafePointer<CChar>?,
            state: UnsafeMutableRawPointer?,
            request: xghostty_clipboard_request_e
        ) {
            let surface = self.surfaceUserdata(from: userdata)
            guard let valueStr = String(cString: string!, encoding: .utf8) else { return }
            guard let request = XGhostty.ClipboardRequest.from(request: request) else { return }
            NotificationCenter.default.post(
                name: Notification.confirmClipboard,
                object: surface,
                userInfo: [
                    Notification.ConfirmClipboardStrKey: valueStr,
                    Notification.ConfirmClipboardStateKey: state as Any,
                    Notification.ConfirmClipboardRequestKey: request,
                ]
            )
        }

        static func completeClipboardRequest(
            _ surface: xghostty_surface_t,
            data: String,
            state: UnsafeMutableRawPointer?,
            confirmed: Bool = false
        ) {
            data.withCString { ptr in
                xghostty_surface_complete_clipboard_request(surface, ptr, state, confirmed)
            }
        }

        static func writeClipboard(
            _ userdata: UnsafeMutableRawPointer?,
            location: xghostty_clipboard_e,
            content: UnsafePointer<xghostty_clipboard_content_s>?,
            len: Int,
            confirm: Bool
        ) {
            let surface = self.surfaceUserdata(from: userdata)
            guard let pasteboard = NSPasteboard.ghostty(location) else { return }
            guard let content = content, len > 0 else { return }

            // Convert the C array to Swift array
            let contentArray = (0..<len).compactMap { i in
                XGhostty.ClipboardContent.from(content: content[i])
            }
            guard !contentArray.isEmpty else { return }

            // Assert there is only one text/plain entry. For security reasons we need
            // to guarantee this for now since our confirmation dialog only shows one.
            assert(contentArray.filter({ $0.mime == "text/plain" }).count <= 1,
                   "clipboard contents should have at most one text/plain entry")

            if !confirm {
                // Declare all types
                let types = contentArray.compactMap { item in
                    NSPasteboard.PasteboardType(mimeType: item.mime)
                }
                pasteboard.declareTypes(types, owner: nil)

                // Set data for each type
                for item in contentArray {
                    guard let type = NSPasteboard.PasteboardType(mimeType: item.mime) else { continue }
                    pasteboard.setString(item.data, forType: type)
                }
                return
            }

            // For confirmation, use the text/plain content if it exists
            guard let textPlainContent = contentArray.first(where: { $0.mime == "text/plain" }) else {
                return
            }

            NotificationCenter.default.post(
                name: Notification.confirmClipboard,
                object: surface,
                userInfo: [
                    Notification.ConfirmClipboardStrKey: textPlainContent.data,
                    Notification.ConfirmClipboardRequestKey: XGhostty.ClipboardRequest.osc_52_write(pasteboard),
                ]
            )
        }

        static func wakeup(_ userdata: UnsafeMutableRawPointer?) {
            let state = Unmanaged<App>.fromOpaque(userdata!).takeUnretainedValue()

            // Wakeup can be called from any thread so we schedule the app tick
            // from the main thread. There is probably some improvements we can make
            // to coalesce multiple ticks but I don't think it matters from a performance
            // standpoint since we don't do this much.
            DispatchQueue.main.async { state.appTick() }
        }

        /// Determine if a given notification should be presented to the user when XGhostty is running in the foreground.
        func shouldPresentNotification(notification: UNNotification) -> Bool {
            let userInfo = notification.request.content.userInfo

            // We always require the notification to be attached to a surface.
            guard let uuidString = userInfo["surface"] as? String,
                  let uuid = UUID(uuidString: uuidString),
                  let surface = delegate?.findSurface(forUUID: uuid),
                  let window = surface.window else { return false }

            // If we don't require focus then we're good!
            let requireFocus = userInfo["requireFocus"] as? Bool ?? true
            if !requireFocus { return true }

            return !window.isKeyWindow || !surface.focused
        }

        /// Returns the GhosttyState from the given userdata value.
        static private func appState(fromView view: SurfaceView) -> App? {
            guard let surface = view.surface else { return nil }
            guard let app = xghostty_surface_app(surface) else { return nil }
            guard let app_ud = xghostty_app_userdata(app) else { return nil }
            return Unmanaged<App>.fromOpaque(app_ud).takeUnretainedValue()
        }

        /// Returns the surface view from the userdata.
        static private func surfaceUserdata(from userdata: UnsafeMutableRawPointer?) -> SurfaceView {
            return Unmanaged<SurfaceView>.fromOpaque(userdata!).takeUnretainedValue()
        }

        static private func surfaceView(from surface: xghostty_surface_t) -> SurfaceView? {
            guard let surface_ud = xghostty_surface_userdata(surface) else { return nil }
            return Unmanaged<SurfaceView>.fromOpaque(surface_ud).takeUnretainedValue()
        }

        // MARK: Actions (macOS)

        static func action(_ app: xghostty_app_t, target: xghostty_target_s, action: xghostty_action_s) -> Bool {
            // Make sure it a target we understand so all our action handlers can assert
            switch target.tag {
            case XGHOSTTY_TARGET_APP, XGHOSTTY_TARGET_SURFACE:
                break

            default:
                XGhostty.logger.warning("unknown action target=\(target.tag.rawValue, privacy: .public)")
                return false
            }

            // Action dispatch
            switch action.tag {
            case XGHOSTTY_ACTION_QUIT:
                quit(app)

            case XGHOSTTY_ACTION_NEW_SPLIT:
                newSplit(app, target: target, direction: action.action.new_split)

            case XGHOSTTY_ACTION_NEW_PROJECT_SPLIT:
                newProjectSplit(app, target: target, direction: action.action.new_project_split)

            case XGHOSTTY_ACTION_RENAME_PROJECT:
                renameProject(app, target: target)

            case XGHOSTTY_ACTION_EDIT_PROJECT_NOTE:
                editProjectNote(app, target: target)

            case XGHOSTTY_ACTION_TOGGLE_NOTE_OVERVIEW:
                toggleNoteOverview(app, target: target)

            case XGHOSTTY_ACTION_SET_PRIMARY:
                return setPrimary(app, target: target)

            case XGHOSTTY_ACTION_SORT_PROJECTS_BY_PRIORITY:
                return sortProjects(app, target: target, notification: Notification.ghosttySortProjectsByPriority)

            case XGHOSTTY_ACTION_SORT_PROJECTS_BY_DEADLINE:
                return sortProjects(app, target: target, notification: Notification.ghosttySortProjectsByDeadline)

            case XGHOSTTY_ACTION_CHOOSE_PROJECT_LAYOUT:
                return chooseProjectLayout(app, target: target)

            case XGHOSTTY_ACTION_LIST_PROJECTS:
                return listProjects(app, target: target)

            case XGHOSTTY_ACTION_SET_PROJECT_TITLE:
                setProjectTitle(app, target: target, v: action.action.set_project_title)

            case XGHOSTTY_ACTION_GOTO_PROJECT:
                return gotoProject(app, target: target, direction: action.action.goto_project)

            case XGHOSTTY_ACTION_GOTO_PROJECT_INDEX:
                return gotoProjectIndex(app, target: target, index: action.action.goto_project_index)

            case XGHOSTTY_ACTION_MOVE_PROJECT:
                return moveProject(app, target: target, direction: action.action.move_project)

            case XGHOSTTY_ACTION_TOGGLE_PROJECT_ZOOM:
                return toggleProjectZoom(app, target: target)

            case XGHOSTTY_ACTION_HIDE_PROJECT:
                return hideProject(app, target: target)

            case XGHOSTTY_ACTION_SHOW_PROJECT:
                return showProject(app, target: target, v: action.action.show_project)

            case XGHOSTTY_ACTION_CLOSE_PROJECT:
                closeProject(app, target: target)

            case XGHOSTTY_ACTION_TOGGLE_FULLSCREEN:
                toggleFullscreen(app, target: target, mode: action.action.toggle_fullscreen)

            case XGHOSTTY_ACTION_GOTO_SPLIT:
                return gotoSplit(app, target: target, direction: action.action.goto_split)

            case XGHOSTTY_ACTION_RESIZE_SPLIT:
                return resizeSplit(app, target: target, resize: action.action.resize_split)

            case XGHOSTTY_ACTION_EQUALIZE_SPLITS:
                equalizeSplits(app, target: target)

            case XGHOSTTY_ACTION_TOGGLE_SPLIT_ZOOM:
                return toggleSplitZoom(app, target: target)

            case XGHOSTTY_ACTION_INSPECTOR:
                controlInspector(app, target: target, mode: action.action.inspector)

            case XGHOSTTY_ACTION_RENDER_INSPECTOR:
                renderInspector(app, target: target)

            case XGHOSTTY_ACTION_DESKTOP_NOTIFICATION:
                showDesktopNotification(app, target: target, n: action.action.desktop_notification)

            case XGHOSTTY_ACTION_SET_TITLE:
                setTitle(app, target: target, v: action.action.set_title)

            case XGHOSTTY_ACTION_PROMPT_TITLE:
                return promptTitle(app, target: target)

            case XGHOSTTY_ACTION_PWD:
                pwdChanged(app, target: target, v: action.action.pwd)

            case XGHOSTTY_ACTION_OPEN_CONFIG:
                openConfig(app)

            case XGHOSTTY_ACTION_FLOAT_WINDOW:
                toggleFloatWindow(app, target: target, mode: action.action.float_window)

            case XGHOSTTY_ACTION_SECURE_INPUT:
                toggleSecureInput(app, target: target, mode: action.action.secure_input)

            case XGHOSTTY_ACTION_MOUSE_SHAPE:
                setMouseShape(app, target: target, shape: action.action.mouse_shape)

            case XGHOSTTY_ACTION_MOUSE_VISIBILITY:
                setMouseVisibility(app, target: target, v: action.action.mouse_visibility)

            case XGHOSTTY_ACTION_MOUSE_OVER_LINK:
                setMouseOverLink(app, target: target, v: action.action.mouse_over_link)

            case XGHOSTTY_ACTION_INITIAL_SIZE:
                setInitialSize(app, target: target, v: action.action.initial_size)

            case XGHOSTTY_ACTION_RESET_WINDOW_SIZE:
                resetWindowSize(app, target: target)

            case XGHOSTTY_ACTION_CELL_SIZE:
                setCellSize(app, target: target, v: action.action.cell_size)

            case XGHOSTTY_ACTION_RENDERER_HEALTH:
                rendererHealth(app, target: target, v: action.action.renderer_health)

            case XGHOSTTY_ACTION_TOGGLE_COMMAND_PALETTE:
                toggleCommandPalette(app, target: target)

            case XGHOSTTY_ACTION_TOGGLE_MAXIMIZE:
                toggleMaximize(app, target: target)

            case XGHOSTTY_ACTION_TOGGLE_BACKGROUND_OPACITY:
                toggleBackgroundOpacity(app, target: target)

            case XGHOSTTY_ACTION_KEY_SEQUENCE:
                keySequence(app, target: target, v: action.action.key_sequence)

            case XGHOSTTY_ACTION_KEY_TABLE:
                keyTable(app, target: target, v: action.action.key_table)

            case XGHOSTTY_ACTION_PROGRESS_REPORT:
                progressReport(app, target: target, v: action.action.progress_report)

            case XGHOSTTY_ACTION_CONFIG_CHANGE:
                configChange(app, target: target, v: action.action.config_change)

            case XGHOSTTY_ACTION_RELOAD_CONFIG:
                configReload(app, target: target, v: action.action.reload_config)

            case XGHOSTTY_ACTION_COLOR_CHANGE:
                colorChange(app, target: target, change: action.action.color_change)

            case XGHOSTTY_ACTION_RING_BELL:
                ringBell(app, target: target)

            case XGHOSTTY_ACTION_SELECTION_CHANGED:
                selectionChanged(app, target: target)

            case XGHOSTTY_ACTION_READONLY:
                setReadonly(app, target: target, v: action.action.readonly)

            case XGHOSTTY_ACTION_CHECK_FOR_UPDATES:
                checkForUpdates(app)

            case XGHOSTTY_ACTION_OPEN_URL:
                return openURL(action.action.open_url)

            case XGHOSTTY_ACTION_UNDO:
                return undo(app, target: target)

            case XGHOSTTY_ACTION_REDO:
                return redo(app, target: target)

            case XGHOSTTY_ACTION_SCROLLBAR:
                scrollbar(app, target: target, v: action.action.scrollbar)

            case XGHOSTTY_ACTION_START_SEARCH:
                startSearch(app, target: target, v: action.action.start_search)

            case XGHOSTTY_ACTION_END_SEARCH:
                return endSearch(app, target: target)

            case XGHOSTTY_ACTION_SEARCH_TOTAL:
                searchTotal(app, target: target, v: action.action.search_total)

            case XGHOSTTY_ACTION_SEARCH_SELECTED:
                searchSelected(app, target: target, v: action.action.search_selected)

            case XGHOSTTY_ACTION_COMMAND_FINISHED:
                commandFinished(app, target: target, v: action.action.command_finished)

            case XGHOSTTY_ACTION_PRESENT_TERMINAL:
                return presentTerminal(app, target: target)

            case XGHOSTTY_ACTION_SIZE_LIMIT, XGHOSTTY_ACTION_QUIT_TIMER:
                // Unimplemented on macOS. These are listed explicitly so they
                // can't fall through into a case that would read the wrong
                // member of the action union.
                return false

            case XGHOSTTY_ACTION_SHOW_CHILD_EXITED:
                return showChildExited(app, target: target, v: action.action.child_exited)
            case XGHOSTTY_ACTION_COPY_TITLE_TO_CLIPBOARD:
                return copyTitleToClipboard(app, target: target)
            default:
                XGhostty.logger.warning("unknown action action=\(action.tag.rawValue, privacy: .public)")
                return false
            }

            // If we reached here then we assume performed since all unknown actions
            // are captured in the switch and return false.
            return true
        }

        private static func quit(_ app: xghostty_app_t) {
            // On iOS, applications do not terminate programmatically like they do
            // on macOS. On iOS, applications are only terminated when a user physically
            // closes the application (i.e. going to the home screen). If we request
            // exit on iOS we ignore it.
            #if os(iOS)
            logger.info("quit request received, ignoring on iOS")
            #endif

            #if os(macOS)
            // We want to quit, start that process
            NSApplication.shared.terminate(nil)
            #endif
        }

        private static func checkForUpdates(
            _ app: xghostty_app_t
        ) {
            if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                appDelegate.checkForUpdates(nil)
            }
        }

        private static func openURL(
            _ v: xghostty_action_open_url_s
        ) -> Bool {
            let action = XGhostty.Action.OpenURL(c: v)

            // If the URL doesn't have a valid scheme we assume its a file path. The URL
            // initializer will gladly take invalid URLs (e.g. plain file paths) and turn
            // them into schema-less URLs, but these won't open properly in text editors.
            // See: https://github.com/ghostty-org/ghostty/issues/8763
            let url: URL
            if let candidate = URL(string: action.url), candidate.scheme != nil {
                url = candidate
            } else {
                // Expand ~ to the user's home directory so that file paths
                // like ~/Documents/file.txt resolve correctly.
                let expandedPath = NSString(string: action.url).standardizingPath
                url = URL(filePath: expandedPath)
            }

            switch action.kind {
            case .text:
                // Open with the default editor for `*.ghostty` file or just system text editor
                let editor = NSWorkspace.shared.defaultApplicationURL(forExtension: url.pathExtension) ?? NSWorkspace.shared.defaultTextEditor
                if let textEditor = editor {
                    NSWorkspace.shared.open([url], withApplicationAt: textEditor, configuration: NSWorkspace.OpenConfiguration())
                    return true
                }

            case .html:
                // The extension will be HTML and we do the right thing automatically.
                break

            case .unknown:
                break
            }

            // Open with the default application for the URL
            NSWorkspace.shared.open(url)
            return true
        }

        private static func undo(_ app: xghostty_app_t, target: xghostty_target_s) -> Bool {
            let undoManager: UndoManager?
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                undoManager = (NSApp.delegate as? AppDelegate)?.undoManager

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return false }
                guard let surfaceView = self.surfaceView(from: surface) else { return false }
                undoManager = surfaceView.undoManager

            default:
                assertionFailure()
                return false
            }

            guard let undoManager, undoManager.canUndo else { return false }
            undoManager.undo()
            return true
        }

        private static func redo(_ app: xghostty_app_t, target: xghostty_target_s) -> Bool {
            let undoManager: UndoManager?
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                undoManager = (NSApp.delegate as? AppDelegate)?.undoManager

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return false }
                guard let surfaceView = self.surfaceView(from: surface) else { return false }
                undoManager = surfaceView.undoManager

            default:
                assertionFailure()
                return false
            }

            guard let undoManager, undoManager.canRedo else { return false }
            undoManager.redo()
            return true
        }

        private static func newSplit(
            _ app: xghostty_app_t,
            target: xghostty_target_s,
            direction: xghostty_action_split_direction_e) {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                // New split does nothing with an app target
                XGhostty.logger.warning("new split does nothing with an app target")
                return

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return }
                guard let surfaceView = self.surfaceView(from: surface) else { return }

                // Pane operations are zoom-only (SPEC §22.5): in the overall
                // view a split would create a pane the view never renders.
                guard let controller = surfaceView.window?.windowController as? BaseTerminalController,
                      controller.workspace.paneOperationsEnabled else { return }

                var config = SurfaceConfiguration(
                    from: xghostty_surface_inherited_config(surface, XGHOSTTY_SURFACE_CONTEXT_SPLIT))

                // Remote split (SPEC §29): when the pane being split is on
                // another host, the new pane reconnects to it at the same path.
                // Only splits do this - a new project always starts here.
                let launch = surfaceView.paneSplitLaunch()
                XGhostty.logger.debug("split launch decision=\(String(describing: launch), privacy: .public)")
                if let reconnect = launch.initialInput {
                    config.initialInput = reconnect
                }

                NotificationCenter.default.post(
                    name: Notification.ghosttyNewSplit,
                    object: surfaceView,
                    userInfo: [
                        "direction": direction,
                        Notification.NewSurfaceConfigKey: config,
                    ]
                )

            default:
                assertionFailure()
            }
        }

        private static func newProjectSplit(
            _ app: xghostty_app_t,
            target: xghostty_target_s,
            direction: xghostty_action_split_direction_e) {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                // A new project split does nothing with an app target.
                XGhostty.logger.warning("new project split does nothing with an app target")
                return

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return }
                guard let surfaceView = self.surfaceView(from: surface) else { return }

                NotificationCenter.default.post(
                    name: Notification.ghosttyNewProjectSplit,
                    object: surfaceView,
                    userInfo: [
                        "direction": direction,
                        Notification.NewSurfaceConfigKey: SurfaceConfiguration(from: xghostty_surface_inherited_config(surface, XGHOSTTY_SURFACE_CONTEXT_PROJECT)),
                    ]
                )

            default:
                assertionFailure()
            }
        }

        private static func renameProject(
            _ app: xghostty_app_t,
            target: xghostty_target_s) {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("rename project does nothing with an app target")
                return

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return }
                guard let surfaceView = self.surfaceView(from: surface) else { return }

                NotificationCenter.default.post(
                    name: Notification.ghosttyRenameProject,
                    object: surfaceView)

            default:
                assertionFailure()
            }
        }

        private static func editProjectNote(
            _ app: xghostty_app_t,
            target: xghostty_target_s) {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("edit project note does nothing with an app target")
                return

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return }
                guard let surfaceView = self.surfaceView(from: surface) else { return }

                NotificationCenter.default.post(
                    name: Notification.ghosttyEditProjectNote,
                    object: surfaceView)

            default:
                assertionFailure()
            }
        }

        private static func setPrimary(
            _ app: xghostty_app_t,
            target: xghostty_target_s) -> Bool {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("set primary does nothing with an app target")
                return false

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return false }
                guard let surfaceView = self.surfaceView(from: surface) else { return false }
                guard let controller = surfaceView.window?.windowController as? BaseTerminalController else { return false }

                // Only performable while zoomed with a focused pane that is
                // not already the primary (SPEC §22.4); otherwise the keybind
                // falls through unconsumed.
                guard controller.workspace.canSetPrimaryToFocusedPane else { return false }

                NotificationCenter.default.post(
                    name: Notification.ghosttySetPrimary,
                    object: surfaceView)
                return true

            default:
                assertionFailure()
                return false
            }
        }

        private static func sortProjects(
            _ app: xghostty_app_t,
            target: xghostty_target_s,
            notification: Foundation.Notification.Name) -> Bool {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("sort projects does nothing with an app target")
                return false

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return false }
                guard let surfaceView = self.surfaceView(from: surface) else { return false }
                guard let controller = surfaceView.window?.windowController as? BaseTerminalController else { return false }

                // Only performable with something to reorder (two or more
                // visible projects) outside the viewing-only note overview
                // (SPEC §24.4); otherwise the keybind falls through
                // unconsumed.
                guard controller.workspace.canSortVisibleProjects else { return false }

                NotificationCenter.default.post(
                    name: notification,
                    object: surfaceView)
                return true

            default:
                assertionFailure()
                return false
            }
        }

        private static func chooseProjectLayout(
            _ app: xghostty_app_t,
            target: xghostty_target_s) -> Bool {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("choose project layout does nothing with an app target")
                return false

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return false }
                guard let surfaceView = self.surfaceView(from: surface) else { return false }
                guard let controller = surfaceView.window?.windowController as? BaseTerminalController else { return false }

                // Only performable when the layout selector can open: at
                // least one visible project and no other overlay owning the
                // keyboard (`SPEC.md` §26.2); otherwise the keybind falls
                // through unconsumed.
                guard controller.workspace.canBeginLayoutSelection else { return false }

                NotificationCenter.default.post(
                    name: Notification.ghosttyChooseProjectLayout,
                    object: surfaceView)
                return true

            default:
                assertionFailure()
                return false
            }
        }

        private static func listProjects(
            _ app: xghostty_app_t,
            target: xghostty_target_s) -> Bool {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("list projects does nothing with an app target")
                return false

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return false }
                guard let surfaceView = self.surfaceView(from: surface) else { return false }
                guard let controller = surfaceView.window?.windowController as? BaseTerminalController else { return false }

                // Only performable when the list can open: at least one
                // project and no other overlay owning the keyboard
                // (`SPEC.md` §27.1); otherwise the keybind falls through
                // unconsumed.
                guard controller.workspace.canBeginProjectList else { return false }

                NotificationCenter.default.post(
                    name: Notification.ghosttyListProjects,
                    object: surfaceView)
                return true

            default:
                assertionFailure()
                return false
            }
        }

        private static func toggleNoteOverview(
            _ app: xghostty_app_t,
            target: xghostty_target_s) {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("toggle note overview does nothing with an app target")
                return

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return }
                guard let surfaceView = self.surfaceView(from: surface) else { return }

                NotificationCenter.default.post(
                    name: Notification.ghosttyToggleNoteOverview,
                    object: surfaceView)

            default:
                assertionFailure()
            }
        }

        private static func setProjectTitle(
            _ app: xghostty_app_t,
            target: xghostty_target_s,
            v: xghostty_action_set_title_s) {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("set project title does nothing with an app target")
                return

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return }
                guard let surfaceView = self.surfaceView(from: surface) else { return }
                guard let title = String(cString: v.title!, encoding: .utf8) else { return }

                NotificationCenter.default.post(
                    name: Notification.ghosttySetProjectTitle,
                    object: surfaceView,
                    userInfo: ["title": title])

            default:
                assertionFailure()
            }
        }

        private static func gotoProject(
            _ app: xghostty_app_t,
            target: xghostty_target_s,
            direction: xghostty_action_goto_split_e) -> Bool {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("goto project does nothing with an app target")
                return false

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return false }
                guard let surfaceView = self.surfaceView(from: surface) else { return false }
                guard let controller = surfaceView.window?.windowController as? BaseTerminalController else { return false }

                // Convert the C API direction to our Swift type.
                guard let focusDirection = SplitFocusDirection.from(direction: direction) else { return false }

                // Only performable when there is actually a visible neighbor project
                // to move to; this keeps the keybind from consuming the key event
                // when nothing would happen.
                let treeDirection: SplitTree<ProjectRef>.FocusDirection =
                    focusDirection.toSplitTreeFocusDirection()
                guard controller.workspace.gotoProjectTarget(treeDirection) != nil else { return false }

                NotificationCenter.default.post(
                    name: Notification.ghosttyGotoProject,
                    object: surfaceView,
                    userInfo: [Notification.ProjectDirectionKey: focusDirection])
                return true

            default:
                assertionFailure()
                return false
            }
        }

        private static func gotoProjectIndex(
            _ app: xghostty_app_t,
            target: xghostty_target_s,
            index: xghostty_action_goto_project_e) -> Bool {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("goto project index does nothing with an app target")
                return false

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return false }
                guard let surfaceView = self.surfaceView(from: surface) else { return false }
                guard let controller = surfaceView.window?.windowController as? BaseTerminalController else { return false }

                // The value is always a 1-based project number (libghostty rejects
                // anything outside 1..9 at parse time), so the enum's negative
                // sentinels never apply here.
                let ordinal = Int(index.rawValue)

                // The Cmd+1..9 binding is `performable`, so only consume the key
                // when the jump would actually change something: the number must
                // resolve to a visible project that isn't already the zoomed one
                // (or, when nothing is zoomed, the focused one).
                guard controller.workspace.gotoProjectIndexTarget(ordinal) != nil else { return false }

                NotificationCenter.default.post(
                    name: Notification.ghosttyGotoProjectIndex,
                    object: surfaceView,
                    userInfo: [Notification.GotoProjectIndexKey: ordinal])
                return true

            default:
                assertionFailure()
                return false
            }
        }

        private static func moveProject(
            _ app: xghostty_app_t,
            target: xghostty_target_s,
            direction: xghostty_action_goto_split_e) -> Bool {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("move project does nothing with an app target")
                return false

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return false }
                guard let surfaceView = self.surfaceView(from: surface) else { return false }
                guard let controller = surfaceView.window?.windowController as? BaseTerminalController else { return false }

                // Convert the C API direction to our Swift type.
                guard let focusDirection = SplitFocusDirection.from(direction: direction) else { return false }

                // Only performable when there is actually a neighbor project to
                // swap with; this keeps the keybind from consuming the key event
                // when nothing would happen (mirrors `goto_project`).
                let treeDirection: SplitTree<ProjectRef>.FocusDirection =
                    focusDirection.toSplitTreeFocusDirection()
                guard controller.workspace.canMoveFocusedProject(treeDirection) else { return false }

                NotificationCenter.default.post(
                    name: Notification.ghosttyMoveProject,
                    object: surfaceView,
                    userInfo: [Notification.MoveProjectDirectionKey: focusDirection])
                return true

            default:
                assertionFailure()
                return false
            }
        }

        private static func toggleProjectZoom(
            _ app: xghostty_app_t,
            target: xghostty_target_s) -> Bool {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("toggle project zoom does nothing with an app target")
                return false

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return false }
                guard let surfaceView = self.surfaceView(from: surface) else { return false }
                guard let controller = surfaceView.window?.windowController as? BaseTerminalController else { return false }

                // Only performable when zooming would change something (more than
                // one visible project, or a zoom to clear); otherwise let the key
                // fall through (mirrors toggle_split_zoom's `isSplit` gate).
                guard controller.workspace.canToggleProjectZoom else { return false }

                NotificationCenter.default.post(
                    name: Notification.ghosttyToggleProjectZoom,
                    object: surfaceView)
                return true

            default:
                assertionFailure()
                return false
            }
        }

        private static func hideProject(
            _ app: xghostty_app_t,
            target: xghostty_target_s) -> Bool {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("hide project does nothing with an app target")
                return false

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return false }
                guard let surfaceView = self.surfaceView(from: surface) else { return false }
                guard let controller = surfaceView.window?.windowController as? BaseTerminalController else { return false }

                // `hide_project` hides the focused project immediately
                // (`SPEC.md` §25). Only performable when the hide would
                // succeed: at least one other project stays visible, and no
                // overlay owning the keyboard.
                guard controller.workspace.canHideFocusedProject else { return false }

                NotificationCenter.default.post(
                    name: Notification.ghosttyHideProject,
                    object: surfaceView)
                return true

            default:
                assertionFailure()
                return false
            }
        }

        private static func showProject(
            _ app: xghostty_app_t,
            target: xghostty_target_s,
            v: xghostty_action_set_title_s) -> Bool {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("show project does nothing with an app target")
                return false

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return false }
                guard let surfaceView = self.surfaceView(from: surface) else { return false }
                guard let controller = surfaceView.window?.windowController as? BaseTerminalController else { return false }
                guard let name = String(cString: v.title!, encoding: .utf8) else { return false }

                // Only performable when a hidden project with that name exists and
                // there is room for it under the visible-project cap; at the cap
                // the reveal is a silent no-op, so leave the key unconsumed.
                guard let id = controller.workspace.hiddenProjectID(named: name),
                      controller.workspace.canShowProject(id) else { return false }

                NotificationCenter.default.post(
                    name: Notification.ghosttyShowProject,
                    object: surfaceView,
                    userInfo: [Notification.ShowProjectNameKey: name])
                return true

            default:
                assertionFailure()
                return false
            }
        }

        private static func closeProject(
            _ app: xghostty_app_t,
            target: xghostty_target_s) {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("close project does nothing with an app target")
                return

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return }
                guard let surfaceView = self.surfaceView(from: surface) else { return }

                // Always meaningful: there is always a focused project to close.
                // The controller shows the destructive-action confirmation and
                // handles the §18.5 last-project → tab/window close delegation.
                NotificationCenter.default.post(
                    name: Notification.ghosttyCloseProject,
                    object: surfaceView)

            default:
                assertionFailure()
            }
        }

        private static func presentTerminal(
            _ app: xghostty_app_t,
            target: xghostty_target_s
        ) -> Bool {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                return false

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return false }
                guard let surfaceView = self.surfaceView(from: surface) else { return false }

                NotificationCenter.default.post(
                    name: Notification.ghosttyPresentTerminal,
                    object: surfaceView
                )
                return true

            default:
                assertionFailure()
                return false
            }
        }

        private static func toggleFullscreen(
            _ app: xghostty_app_t,
            target: xghostty_target_s,
            mode raw: xghostty_action_fullscreen_e) {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("toggle fullscreen does nothing with an app target")
                return

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return }
                guard let surfaceView = self.surfaceView(from: surface) else { return }
                guard let mode = FullscreenMode.from(ghostty: raw) else {
                    XGhostty.logger.warning("unknown fullscreen mode raw=\(raw.rawValue, privacy: .public)")
                    return
                }
                NotificationCenter.default.post(
                    name: Notification.ghosttyToggleFullscreen,
                    object: surfaceView,
                    userInfo: [
                        Notification.FullscreenModeKey: mode,
                    ]
                )

            default:
                assertionFailure()
            }
        }

        private static func toggleCommandPalette(
            _ app: xghostty_app_t,
            target: xghostty_target_s) {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("toggle command palette does nothing with an app target")
                return

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return }
                guard let surfaceView = self.surfaceView(from: surface) else { return }
                NotificationCenter.default.post(
                    name: .ghosttyCommandPaletteDidToggle,
                    object: surfaceView
                )

            default:
                assertionFailure()
            }
        }

        private static func toggleMaximize(
            _ app: xghostty_app_t,
            target: xghostty_target_s
        ) {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("toggle maximize does nothing with an app target")
                return

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return }
                guard let surfaceView = self.surfaceView(from: surface) else { return }
                NotificationCenter.default.post(
                    name: .ghosttyMaximizeDidToggle,
                    object: surfaceView
                )

            default:
                assertionFailure()
            }
        }

        private static func ringBell(
            _ app: xghostty_app_t,
            target: xghostty_target_s) {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                // Technically we could still request app attention here but there
                // are no known cases where the bell is rang with an app target so
                // I think its better to warn.
                XGhostty.logger.warning("ring bell does nothing with an app target")
                return

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return }
                guard let surfaceView = self.surfaceView(from: surface) else { return }
                NotificationCenter.default.post(
                    name: .ghosttyBellDidRing,
                    object: surfaceView
                )

            default:
                assertionFailure()
            }
        }

        private static func selectionChanged(
            _ app: xghostty_app_t,
            target: xghostty_target_s) {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("selection changed does nothing with an app target")
                return

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return }
                guard let surfaceView = self.surfaceView(from: surface) else { return }
                NotificationCenter.default.post(
                    name: .ghosttySelectionDidChange,
                    object: surfaceView
                )

            default:
                assertionFailure()
            }
        }

        private static func setReadonly(
            _ app: xghostty_app_t,
            target: xghostty_target_s,
            v: xghostty_action_readonly_e) {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("set readonly does nothing with an app target")
                return

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return }
                guard let surfaceView = self.surfaceView(from: surface) else { return }
                NotificationCenter.default.post(
                    name: .ghosttyDidChangeReadonly,
                    object: surfaceView,
                    userInfo: [
                        SwiftUI.Notification.Name.ReadonlyKey: v == XGHOSTTY_READONLY_ON,
                    ]
                )

            default:
                assertionFailure()
            }
        }

        private static func gotoSplit(
            _ app: xghostty_app_t,
            target: xghostty_target_s,
            direction: xghostty_action_goto_split_e) -> Bool {
                switch target.tag {
                case XGHOSTTY_TARGET_APP:
                    XGhostty.logger.warning("goto split does nothing with an app target")
                    return false

                case XGHOSTTY_TARGET_SURFACE:
                    guard let surface = target.target.surface else { return false }
                    guard let surfaceView = self.surfaceView(from: surface) else { return false }
                    guard let controller = surfaceView.window?.windowController as? BaseTerminalController else { return false }

                    // Inter-pane focus movement is zoom-only (SPEC §22.5); in
                    // the overall view the keybind falls through unconsumed.
                    guard controller.workspace.paneOperationsEnabled else { return false }

                    // If the window has no splits, the action is not performable
                    guard controller.surfaceTree.isSplit else { return false }

                    // Convert the C API direction to our Swift type
                    guard let splitDirection = SplitFocusDirection.from(direction: direction) else { return false }

                    // Find the current node in the tree
                    guard let targetNode = controller.surfaceTree.root?.node(view: surfaceView) else { return false }

                    // Check if a split actually exists in the target direction before
                    // returning true. This ensures performable keybinds only consume
                    // the key event when we actually perform navigation.
                    let focusDirection: SplitTree<XGhostty.SurfaceView>.FocusDirection = splitDirection.toSplitTreeFocusDirection()
                    guard controller.surfaceTree.focusTarget(for: focusDirection, from: targetNode) != nil else {
                        return false
                    }

                    // We have a valid target, post the notification to perform the navigation
                    NotificationCenter.default.post(
                        name: Notification.ghosttyFocusSplit,
                        object: surfaceView,
                        userInfo: [
                            Notification.SplitDirectionKey: splitDirection as Any,
                        ]
                    )

                    return true

                default:
                    assertionFailure()
                    return false
                }
        }

        private static func resizeSplit(
            _ app: xghostty_app_t,
            target: xghostty_target_s,
            resize: xghostty_action_resize_split_s) -> Bool {
                switch target.tag {
                case XGHOSTTY_TARGET_APP:
                    XGhostty.logger.warning("resize split does nothing with an app target")
                    return false

                case XGHOSTTY_TARGET_SURFACE:
                    guard let surface = target.target.surface else { return false }
                    guard let surfaceView = self.surfaceView(from: surface) else { return false }
                    guard let controller = surfaceView.window?.windowController as? BaseTerminalController else { return false }

                    // Pane resize is zoom-only (SPEC §22.5).
                    guard controller.workspace.paneOperationsEnabled else { return false }

                    // If the window has no splits, the action is not performable
                    guard controller.surfaceTree.isSplit else { return false }

                    guard let resizeDirection = SplitResizeDirection.from(direction: resize.direction) else { return false }
                    NotificationCenter.default.post(
                        name: Notification.didResizeSplit,
                        object: surfaceView,
                        userInfo: [
                            Notification.ResizeSplitDirectionKey: resizeDirection,
                            Notification.ResizeSplitAmountKey: resize.amount,
                        ]
                    )
                    return true

                default:
                    assertionFailure()
                    return false
                }
        }

        private static func equalizeSplits(
            _ app: xghostty_app_t,
            target: xghostty_target_s) {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("equalize splits does nothing with an app target")
                return

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return }
                guard let surfaceView = self.surfaceView(from: surface) else { return }

                // Pane equalize is zoom-only (SPEC §22.5).
                guard let controller = surfaceView.window?.windowController as? BaseTerminalController,
                      controller.workspace.paneOperationsEnabled else { return }

                NotificationCenter.default.post(
                    name: Notification.didEqualizeSplits,
                    object: surfaceView
                )

            default:
                assertionFailure()
            }
        }

        private static func toggleSplitZoom(
            _ app: xghostty_app_t,
            target: xghostty_target_s) -> Bool {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("toggle split zoom does nothing with an app target")
                return false

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return false }
                guard let surfaceView = self.surfaceView(from: surface) else { return false }
                guard let controller = surfaceView.window?.windowController as? BaseTerminalController else { return false }

                // Pane zoom is zoom-only (SPEC §22.5); in the overall view the
                // keybind falls through unconsumed.
                guard controller.workspace.paneOperationsEnabled else { return false }

                // If the window has no splits, the action is not performable
                guard controller.surfaceTree.isSplit else { return false }

                NotificationCenter.default.post(
                    name: Notification.didToggleSplitZoom,
                    object: surfaceView
                )
                return true

            default:
                assertionFailure()
                return false
            }
        }

        private static func controlInspector(
            _ app: xghostty_app_t,
            target: xghostty_target_s,
            mode: xghostty_action_inspector_e) {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("toggle inspector does nothing with an app target")
                return

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return }
                guard let surfaceView = self.surfaceView(from: surface) else { return }
                NotificationCenter.default.post(
                    name: Notification.didControlInspector,
                    object: surfaceView,
                    userInfo: ["mode": mode]
                )

            default:
                assertionFailure()
            }
        }

        private static func showDesktopNotification(
            _ app: xghostty_app_t,
            target: xghostty_target_s,
            n: xghostty_action_desktop_notification_s) {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("desktop notification does nothing with an app target")
                return

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return }
                guard let surfaceView = self.surfaceView(from: surface) else { return }
                guard let title = String(cString: n.title!, encoding: .utf8) else { return }
                guard let body = String(cString: n.body!, encoding: .utf8) else { return }
                showDesktopNotification(surfaceView, title: title, body: body)

            default:
                assertionFailure()
            }
        }

        private static func showDesktopNotification(
            _ surfaceView: SurfaceView,
            title: String,
            body: String,
            requireFocus: Bool = true) {
            let center = UNUserNotificationCenter.current()
            center.requestAuthorization(options: [.alert, .sound]) { _, error in
                if let error = error {
                    XGhostty.logger.error("Error while requesting notification authorization: \(error, privacy: .public)")
                }
            }

            center.getNotificationSettings { settings in
                guard settings.authorizationStatus == .authorized else { return }
                surfaceView.showUserNotification(
                    title: title,
                    body: body,
                    requireFocus: requireFocus
                )
            }
        }

        private static func commandFinished(
            _ app: xghostty_app_t,
            target: xghostty_target_s,
            v: xghostty_action_command_finished_s
        ) {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("command finished does nothing with an app target")
                return

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return }
                guard let surfaceView = self.surfaceView(from: surface) else { return }

                // A finished command can mean the pane just came back from a
                // remote session (SPEC §29). This is deliberately ahead of the
                // notification config below: whether the human wants to be
                // notified says nothing about where the pane now is.
                surfaceView.paneCommandFinished()

                // Determine if we even care about command finish notifications
                guard let config = (NSApplication.shared.delegate as? AppDelegate)?.ghostty.config else { return }
                switch config.notifyOnCommandFinish {
                case .never:
                    return

                case .unfocused:
                    if surfaceView.focused { return }

                case .always:
                    break
                }

                // Determine if the command was slow enough
                let duration = Duration.nanoseconds(v.duration)
                guard Duration.nanoseconds(v.duration) >= config.notifyOnCommandFinishAfter else { return }

                let actions = config.notifyOnCommandFinishAction

                if actions.contains(.bell) {
                    NotificationCenter.default.post(
                        name: .ghosttyBellDidRing,
                        object: surfaceView
                    )
                }

                if actions.contains(.notify) {
                    let title: String
                    if v.exit_code < 0 {
                        title = "Command Finished"
                    } else if v.exit_code == 0 {
                        title = "Command Succeeded"
                    } else {
                        title = "Command Failed"
                    }

                    let body: String
                    let formattedDuration = duration.formatted(
                        .units(
                            allowed: [.hours, .minutes, .seconds, .milliseconds],
                            width: .abbreviated,
                            fractionalPart: .hide
                        )
                    )
                    if v.exit_code < 0 {
                        body = "Command took \(formattedDuration)."
                    } else {
                        body = "Command took \(formattedDuration) and exited with code \(v.exit_code)."
                    }

                    showDesktopNotification(
                        surfaceView,
                        title: title,
                        body: body,
                        requireFocus: false
                    )
                }

            default:
                assertionFailure()
            }
        }

        private static func toggleFloatWindow(
            _ app: xghostty_app_t,
            target: xghostty_target_s,
            mode mode_raw: xghostty_action_float_window_e
        ) {
            guard let mode = SetFloatWIndow.from(mode_raw) else { return }

            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("toggle float window does nothing with an app target")
                return

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return }
                guard let surfaceView = self.surfaceView(from: surface) else { return }
                guard let window = surfaceView.window as? TerminalWindow else { return }

                switch mode {
                case .on:
                    window.level = .floating

                case .off:
                    window.level = .normal

                case .toggle:
                    window.level = window.level == .floating ? .normal : .floating
                }

                if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                    appDelegate.syncFloatOnTopMenu(window)
                }

            default:
                assertionFailure()
            }
        }

        private static func toggleBackgroundOpacity(
            _ app: xghostty_app_t,
            target: xghostty_target_s
        ) {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("toggle background opacity does nothing with an app target")
                return

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface,
                    let surfaceView = self.surfaceView(from: surface),
                    let controller = surfaceView.window?.windowController as? BaseTerminalController else { return }

                controller.toggleBackgroundOpacity()

            default:
                assertionFailure()
            }
        }

        private static func toggleSecureInput(
            _ app: xghostty_app_t,
            target: xghostty_target_s,
            mode mode_raw: xghostty_action_secure_input_e
        ) {
            guard let mode = SetSecureInput.from(mode_raw) else { return }

            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else { return }
                appDelegate.setSecureInput(mode)

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return }
                guard let surfaceView = self.surfaceView(from: surface) else { return }
                guard let appState = self.appState(fromView: surfaceView) else { return }
                guard appState.config.autoSecureInput else { return }

                switch mode {
                case .on:
                    surfaceView.passwordInput = true

                case .off:
                    surfaceView.passwordInput = false

                case .toggle:
                    surfaceView.passwordInput = !surfaceView.passwordInput
                }

            default:
                assertionFailure()
            }
        }

        private static func setTitle(
            _ app: xghostty_app_t,
            target: xghostty_target_s,
            v: xghostty_action_set_title_s) {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("set title does nothing with an app target")
                return

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return }
                guard let surfaceView = self.surfaceView(from: surface) else { return }
                guard let title = String(cString: v.title!, encoding: .utf8) else { return }
                surfaceView.setTitle(title)

            default:
                assertionFailure()
            }
        }

        private static func showChildExited(
            _ app: xghostty_app_t,
            target: xghostty_target_s,
            v: xghostty_surface_message_childexited_s,
        ) -> Bool {
            switch target.tag {
            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return false }
                guard let surfaceView = self.surfaceView(from: surface) else { return false }
                // The shell that reported a location is gone, so the report is
                // gone with it: whatever runs in this pane next starts here
                // (SPEC §29). This covers the terminated pane an Enter restarts,
                // and is ahead of every config-dependent guard below.
                surfaceView.resetPaneLocation()

                guard let config = (NSApplication.shared.delegate as? AppDelegate)?.ghostty.config else { return false }

                // The project layer owns what a child exit means for the pane
                // (close an exited sibling pane, keep a project's last pane as a
                // terminated pane), so it is notified unconditionally — even
                // for a window-less (hidden-project) or instantly-exited pane.
                NotificationCenter.default.post(
                    name: Notification.ghosttyChildExited,
                    object: surfaceView,
                    userInfo: [
                        Notification.ChildExitedAbnormalKey:
                            config.abnormalCommandExitRuntime >= .milliseconds(v.timetime_ms),
                    ])

                // The message bar keeps the upstream guards: only shown when
                // the window is visible and timetime_ms is greater than 0,
                // which rules out exit codes on launch.
                guard surfaceView.window != nil, v.timetime_ms > 0 else { return false }
                surfaceView.setChildExitedMessage(.init(v, threshold: config.abnormalCommandExitRuntime))
                return true
            default:
                return false
            }
        }

        private static func copyTitleToClipboard(
            _ app: xghostty_app_t,
            target: xghostty_target_s) -> Bool {
            switch target.tag {
            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return false }
                guard let surfaceView = self.surfaceView(from: surface) else { return false }
                let title = surfaceView.title
                if title.isEmpty { return false }
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(title, forType: .string)
                return true

            default:
                return false
            }
        }

        private static func promptTitle(
            _ app: xghostty_app_t,
            target: xghostty_target_s) -> Bool {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("set title prompt does nothing with an app target")
                return false

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return false }
                guard let surfaceView = self.surfaceView(from: surface) else { return false }
                surfaceView.promptTitle()
                return true

            default:
                assertionFailure()
                return false
            }
        }

        private static func pwdChanged(
            _ app: xghostty_app_t,
            target: xghostty_target_s,
            v: xghostty_action_pwd_s) {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("pwd change does nothing with an app target")
                return

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return }
                guard let surfaceView = self.surfaceView(from: surface) else { return }
                guard let pwd = String(cString: v.pwd!, encoding: .utf8) else { return }

                // A non-empty host means another machine reported this path, so
                // it is not a path here: only the report is kept, `pwd` stays
                // on the last local one (SPEC §29).
                let host = v.host.flatMap { String(cString: $0, encoding: .utf8) } ?? ""
                surfaceView.recordPaneLocation(.init(host: host, path: pwd))
                if host.isEmpty { surfaceView.pwd = pwd }

                // The one place the whole OSC 7 chain becomes visible on
                // device: without it, telling "the report never arrived" from
                // "the report arrived and was judged local" means reading the
                // Zig core, the C API and this layer (SPEC §29).
                XGhostty.logger.debug(
                    "pwd report received host=\(host, privacy: .public) path=\(pwd, privacy: .public)")

            default:
                assertionFailure()
            }
        }

        private static func setMouseShape(
            _ app: xghostty_app_t,
            target: xghostty_target_s,
            shape: xghostty_action_mouse_shape_e) {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("set mouse shapes nothing with an app target")
                return

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return }
                guard let surfaceView = self.surfaceView(from: surface) else { return }
                surfaceView.setCursorShape(shape)

            default:
                assertionFailure()
            }
        }

        private static func setMouseVisibility(
            _ app: xghostty_app_t,
            target: xghostty_target_s,
            v: xghostty_action_mouse_visibility_e) {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("set mouse shapes nothing with an app target")
                return

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return }
                guard let surfaceView = self.surfaceView(from: surface) else { return }
                switch v {
                case XGHOSTTY_MOUSE_VISIBLE:
                    surfaceView.setCursorVisibility(true)

                case XGHOSTTY_MOUSE_HIDDEN:
                    surfaceView.setCursorVisibility(false)

                default:
                    return
                }

            default:
                assertionFailure()
            }
        }

        private static func setMouseOverLink(
            _ app: xghostty_app_t,
            target: xghostty_target_s,
            v: xghostty_action_mouse_over_link_s) {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("mouse over link does nothing with an app target")
                return

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return }
                guard let surfaceView = self.surfaceView(from: surface) else { return }
                guard v.len > 0 else {
                    surfaceView.hoverUrl = nil
                    return
                }

                let buffer = Data(bytes: v.url!, count: v.len)
                surfaceView.hoverUrl = String(data: buffer, encoding: .utf8)

            default:
                assertionFailure()
            }
        }

        private static func setInitialSize(
            _ app: xghostty_app_t,
            target: xghostty_target_s,
            v: xghostty_action_initial_size_s) {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("initial size does nothing with an app target")
                return

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return }
                guard let surfaceView = self.surfaceView(from: surface) else { return }
                surfaceView.initialSize = NSSize(width: Double(v.width), height: Double(v.height))

            default:
                assertionFailure()
            }
        }

        private static func resetWindowSize(
            _ app: xghostty_app_t,
            target: xghostty_target_s) {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("reset window size does nothing with an app target")
                return

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return }
                guard let surfaceView = self.surfaceView(from: surface) else { return }
                NotificationCenter.default.post(
                    name: .ghosttyResetWindowSize,
                    object: surfaceView
                )

            default:
                assertionFailure()
            }
        }

        private static func setCellSize(
            _ app: xghostty_app_t,
            target: xghostty_target_s,
            v: xghostty_action_cell_size_s) {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("mouse over link does nothing with an app target")
                return

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return }
                guard let surfaceView = self.surfaceView(from: surface) else { return }
                let backingSize = NSSize(width: Double(v.width), height: Double(v.height))
                DispatchQueue.main.async { [weak surfaceView] in
                    guard let surfaceView else { return }
                    surfaceView.cellSize = surfaceView.convertFromBacking(backingSize)
                }

            default:
                assertionFailure()
            }
        }

        private static func renderInspector(
            _ app: xghostty_app_t,
            target: xghostty_target_s) {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("mouse over link does nothing with an app target")
                return

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return }
                guard let surfaceView = self.surfaceView(from: surface) else { return }
                NotificationCenter.default.post(
                    name: Notification.inspectorNeedsDisplay,
                    object: surfaceView
                )

            default:
                assertionFailure()
            }
        }

        private static func rendererHealth(
            _ app: xghostty_app_t,
            target: xghostty_target_s,
            v: xghostty_action_renderer_health_e) {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("mouse over link does nothing with an app target")
                return

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return }
                guard let surfaceView = self.surfaceView(from: surface) else { return }
                NotificationCenter.default.post(
                    name: Notification.didUpdateRendererHealth,
                    object: surfaceView,
                    userInfo: [
                        "health": v,
                    ]
                )

            default:
                assertionFailure()
            }
        }

        private static func keySequence(
            _ app: xghostty_app_t,
            target: xghostty_target_s,
            v: xghostty_action_key_sequence_s) {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("key sequence does nothing with an app target")
                return

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return }
                guard let surfaceView = self.surfaceView(from: surface) else { return }
                if v.active {
                    NotificationCenter.default.post(
                        name: Notification.didContinueKeySequence,
                        object: surfaceView,
                        userInfo: [
                            Notification.KeySequenceKey: keyboardShortcut(for: v.trigger) as Any
                        ]
                    )
                } else {
                    NotificationCenter.default.post(
                        name: Notification.didEndKeySequence,
                        object: surfaceView
                    )
                }

            default:
                assertionFailure()
            }
        }

        private static func keyTable(
            _ app: xghostty_app_t,
            target: xghostty_target_s,
            v: xghostty_action_key_table_s) {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("key table does nothing with an app target")
                return

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return }
                guard let surfaceView = self.surfaceView(from: surface) else { return }
                guard let action = XGhostty.Action.KeyTable(c: v) else { return }

                NotificationCenter.default.post(
                    name: Notification.didChangeKeyTable,
                    object: surfaceView,
                    userInfo: [Notification.KeyTableKey: action]
                )

            default:
                assertionFailure()
            }
        }

        private static func progressReport(
            _ app: xghostty_app_t,
            target: xghostty_target_s,
            v: xghostty_action_progress_report_s) {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("progress report does nothing with an app target")
                return

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return }
                guard let surfaceView = self.surfaceView(from: surface) else { return }
                guard let config = (NSApplication.shared.delegate as? AppDelegate)?.ghostty.config else { return }

                guard config.progressStyle else {
                    XGhostty.logger.debug("progress_report action blocked by config")
                    DispatchQueue.main.async {
                        surfaceView.progressReport = nil
                    }
                    return
                }

                let progressReport = XGhostty.Action.ProgressReport(c: v)
                DispatchQueue.main.async {
                    if progressReport.state == .remove {
                        surfaceView.progressReport = nil
                    } else {
                        surfaceView.progressReport = progressReport
                    }
                }

            default:
                assertionFailure()
            }
        }

        private static func scrollbar(
            _ app: xghostty_app_t,
            target: xghostty_target_s,
            v: xghostty_action_scrollbar_s) {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("scrollbar does nothing with an app target")
                return

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return }
                guard let surfaceView = self.surfaceView(from: surface) else { return }

                let scrollbar = XGhostty.Action.Scrollbar(c: v)
                NotificationCenter.default.post(
                    name: .ghosttyDidUpdateScrollbar,
                    object: surfaceView,
                    userInfo: [
                        SwiftUI.Notification.Name.ScrollbarKey: scrollbar
                    ]
                )

            default:
                assertionFailure()
            }
        }

        private static func startSearch(
            _ app: xghostty_app_t,
            target: xghostty_target_s,
            v: xghostty_action_start_search_s) {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("start_search does nothing with an app target")
                return

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return }
                guard let surfaceView = self.surfaceView(from: surface) else { return }

                let startSearch = XGhostty.Action.StartSearch(c: v)
                DispatchQueue.main.async {
                    if let searchState = surfaceView.searchState {
                        if let needle = startSearch.needle, !needle.isEmpty {
                            searchState.needle = needle
                        }
                    } else {
                        surfaceView.searchState = XGhostty.SurfaceView.SearchState(from: startSearch)
                    }

                    NotificationCenter.default.post(name: .ghosttySearchFocus, object: surfaceView)
                }

            default:
                assertionFailure()
            }
        }

        private static func endSearch(
            _ app: xghostty_app_t,
            target: xghostty_target_s) -> Bool {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("end_search does nothing with an app target")
                return false

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return false }
                guard let surfaceView = self.surfaceView(from: surface) else { return false }

                DispatchQueue.main.async {
                    surfaceView.endSearch()
                }
                return true
            default:
                assertionFailure()
                return false
            }
        }

        private static func searchTotal(
            _ app: xghostty_app_t,
            target: xghostty_target_s,
            v: xghostty_action_search_total_s) {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("search_total does nothing with an app target")
                return

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return }
                guard let surfaceView = self.surfaceView(from: surface) else { return }

                let total: UInt? = v.total >= 0 ? UInt(v.total) : nil
                DispatchQueue.main.async {
                    surfaceView.searchState?.total = total
                }

            default:
                assertionFailure()
            }
        }

        private static func searchSelected(
            _ app: xghostty_app_t,
            target: xghostty_target_s,
            v: xghostty_action_search_selected_s) {
            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                XGhostty.logger.warning("search_selected does nothing with an app target")
                return

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return }
                guard let surfaceView = self.surfaceView(from: surface) else { return }

                let selected: UInt? = v.selected >= 0 ? UInt(v.selected) : nil
                DispatchQueue.main.async {
                    surfaceView.searchState?.selected = selected
                }

            default:
                assertionFailure()
            }
        }

        private static func configReload(
            _ app: xghostty_app_t,
            target: xghostty_target_s,
            v: xghostty_action_reload_config_s) {
            logger.info("config reload notification")

            guard let app_ud = xghostty_app_userdata(app) else { return }
            let ghostty = Unmanaged<App>.fromOpaque(app_ud).takeUnretainedValue()

            switch target.tag {
            case XGHOSTTY_TARGET_APP:
                ghostty.reloadConfig(soft: v.soft)
                return

            case XGHOSTTY_TARGET_SURFACE:
                guard let surface = target.target.surface else { return }
                ghostty.reloadConfig(surface: surface, soft: v.soft)

            default:
                assertionFailure()
            }
        }

        private static func configChange(
            _ app: xghostty_app_t,
            target: xghostty_target_s,
            v: xghostty_action_config_change_s) {
                logger.info("config change notification")

                // Clone the config so we own the memory. It'd be nicer to not have to do
                // this but since we async send the config out below we have to own the lifetime.
                // A future improvement might be to add reference counting to config or
                // something so apprt's do not have to do this.
                let config = Config(clone: v.config)

                switch target.tag {
                case XGHOSTTY_TARGET_APP:
                    // Notify the world that the app config changed
                    NotificationCenter.default.post(
                        name: .ghosttyConfigDidChange,
                        object: nil,
                        userInfo: [
                            SwiftUI.Notification.Name.GhosttyConfigChangeKey: config,
                        ]
                    )

                    // We also REPLACE our app-level config when this happens. This lets
                    // all the various things that depend on this but are still theme specific
                    // such as split border color work.
                    guard let app_ud = xghostty_app_userdata(app) else { return }
                    let ghostty = Unmanaged<App>.fromOpaque(app_ud).takeUnretainedValue()
                    ghostty.config = config

                    return

                case XGHOSTTY_TARGET_SURFACE:
                    guard let surface = target.target.surface else { return }
                    guard let surfaceView = self.surfaceView(from: surface) else { return }
                    NotificationCenter.default.post(
                        name: .ghosttyConfigDidChange,
                        object: surfaceView,
                        userInfo: [
                            SwiftUI.Notification.Name.GhosttyConfigChangeKey: config,
                        ]
                    )

                default:
                    assertionFailure()
                }
            }

        private static func colorChange(
            _ app: xghostty_app_t,
            target: xghostty_target_s,
            change: xghostty_action_color_change_s) {
                switch target.tag {
                case XGHOSTTY_TARGET_APP:
                    XGhostty.logger.warning("color change does nothing with an app target")
                    return

                case XGHOSTTY_TARGET_SURFACE:
                    guard let surface = target.target.surface else { return }
                    guard let surfaceView = self.surfaceView(from: surface) else { return }
                    NotificationCenter.default.post(
                        name: .ghosttyColorDidChange,
                        object: surfaceView,
                        userInfo: [
                            SwiftUI.Notification.Name.GhosttyColorChangeKey: Action.ColorChange(c: change)
                        ]
                    )

                default:
                    assertionFailure()
                }
        }

        // MARK: User Notifications

        /// Handle a received user notification. This is called when a user notification is clicked or dismissed by the user
        func handleUserNotification(response: UNNotificationResponse) {
            let userInfo = response.notification.request.content.userInfo
            guard let uuidString = userInfo["surface"] as? String,
                  let uuid = UUID(uuidString: uuidString),
                  let surface = delegate?.findSurface(forUUID: uuid) else { return }

            switch response.actionIdentifier {
            case UNNotificationDefaultActionIdentifier, XGhostty.userNotificationActionShow:
                // The user clicked on a notification
                surface.handleUserNotification(notification: response.notification, focus: true)
            case UNNotificationDismissActionIdentifier:
                // The user dismissed the notification
                surface.handleUserNotification(notification: response.notification, focus: false)
            default:
                break
            }
        }

        #endif
    }
}
