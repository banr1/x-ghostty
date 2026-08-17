import os
import SwiftUI
import XGhosttyKit

// MARK: C Extensions

/// A command is fully self-contained so it is Sendable.
extension xghostty_command_s: @unchecked @retroactive Sendable {}

/// A surface is sendable because it is just a reference type. Using the surface in parameters
/// may be unsafe but the value itself is safe to send across threads.
extension xghostty_surface_t: @unchecked @retroactive Sendable {}

extension XGhostty {
    // The user notification category identifier
    static let userNotificationCategory = "com.mitchellh.xghostty.userNotification"

    // The user notification "Show" action
    static let userNotificationActionShow = "com.mitchellh.xghostty.userNotification.Show"
}

// MARK: Build Info

extension XGhostty {
    struct Info {
        var mode: xghostty_build_mode_e
        var version: String
    }

    static var info: Info {
        let raw = xghostty_info()
        let version = NSString(
            bytes: raw.version,
            length: Int(raw.version_len),
            encoding: NSUTF8StringEncoding
        ) ?? "unknown"

        return Info(mode: raw.build_mode, version: String(version))
    }
}

// MARK: General Helpers

extension XGhostty {
    enum LaunchSource: String {
        case cli
        case app
        case zig_run
    }

    /// Returns the mechanism that launched the app. This is based on an env var so
    /// its up to the env var being set in the correct circumstance.
    static var launchSource: LaunchSource {
        guard let envValue = ProcessInfo.processInfo.environment["XGHOSTTY_MAC_LAUNCH_SOURCE"] else {
            // We default to the CLI because the app bundle always sets the
            // source. If its unset we assume we're in a CLI environment.
            return .cli
        }

        // If the env var is set but its unknown then we default back to the app.
        return LaunchSource(rawValue: envValue) ?? .app
    }
}

// MARK: Swift Types for C Types

extension XGhostty {
    class AllocatedString {
        private let cString: xghostty_string_s

        init(_ c: xghostty_string_s) {
            self.cString = c
        }

        var string: String {
            guard let ptr = cString.ptr else { return "" }
            let data = Data(bytes: ptr, count: Int(cString.len))
            return String(data: data, encoding: .utf8) ?? ""
        }

        deinit {
            xghostty_string_free(cString)
        }
    }
}

extension XGhostty {
    enum SetFloatWIndow {
        case on
        case off
        case toggle

        static func from(_ c: xghostty_action_float_window_e) -> Self? {
            switch c {
            case XGHOSTTY_FLOAT_WINDOW_ON:
                return .on

            case XGHOSTTY_FLOAT_WINDOW_OFF:
                return .off

            case XGHOSTTY_FLOAT_WINDOW_TOGGLE:
                return .toggle

            default:
                return nil
            }
        }
    }

    enum SetSecureInput {
        case on
        case off
        case toggle

        static func from(_ c: xghostty_action_secure_input_e) -> Self? {
            switch c {
            case XGHOSTTY_SECURE_INPUT_ON:
                return .on

            case XGHOSTTY_SECURE_INPUT_OFF:
                return .off

            case XGHOSTTY_SECURE_INPUT_TOGGLE:
                return .toggle

            default:
                return nil
            }
        }
    }

    /// An enum that is used for the directions that a split focus event can change.
    enum SplitFocusDirection {
        case previous, next, up, down, left, right

        /// Initialize from a XGhostty API enum.
        static func from(direction: xghostty_action_goto_split_e) -> Self? {
            switch direction {
            case XGHOSTTY_GOTO_SPLIT_PREVIOUS:
                return .previous

            case XGHOSTTY_GOTO_SPLIT_NEXT:
                return .next

            case XGHOSTTY_GOTO_SPLIT_UP:
                return .up

            case XGHOSTTY_GOTO_SPLIT_DOWN:
                return .down

            case XGHOSTTY_GOTO_SPLIT_LEFT:
                return .left

            case XGHOSTTY_GOTO_SPLIT_RIGHT:
                return .right

            default:
                return nil
            }
        }

        func toNative() -> xghostty_action_goto_split_e {
            switch self {
            case .previous:
                return XGHOSTTY_GOTO_SPLIT_PREVIOUS

            case .next:
                return XGHOSTTY_GOTO_SPLIT_NEXT

            case .up:
                return XGHOSTTY_GOTO_SPLIT_UP

            case .down:
                return XGHOSTTY_GOTO_SPLIT_DOWN

            case .left:
                return XGHOSTTY_GOTO_SPLIT_LEFT

            case .right:
                return XGHOSTTY_GOTO_SPLIT_RIGHT
            }
        }
    }

    /// Enum used for resizing splits. This is the direction the split divider will move.
    enum SplitResizeDirection {
        case up, down, left, right

        static func from(direction: xghostty_action_resize_split_direction_e) -> Self? {
            switch direction {
            case XGHOSTTY_RESIZE_SPLIT_UP:
                return .up
            case XGHOSTTY_RESIZE_SPLIT_DOWN:
                return .down
            case XGHOSTTY_RESIZE_SPLIT_LEFT:
                return .left
            case XGHOSTTY_RESIZE_SPLIT_RIGHT:
                return .right
            default:
                return nil
            }
        }

        func toNative() -> xghostty_action_resize_split_direction_e {
            switch self {
            case .up:
                return XGHOSTTY_RESIZE_SPLIT_UP
            case .down:
                return XGHOSTTY_RESIZE_SPLIT_DOWN
            case .left:
                return XGHOSTTY_RESIZE_SPLIT_LEFT
            case .right:
                return XGHOSTTY_RESIZE_SPLIT_RIGHT
            }
        }
    }
}

#if canImport(AppKit)
// MARK: SplitFocusDirection Extensions

extension XGhostty.SplitFocusDirection {
    /// Convert to a SplitTree.FocusDirection for the given ViewType.
    func toSplitTreeFocusDirection<ViewType>() -> SplitTree<ViewType>.FocusDirection {
        switch self {
        case .previous:
            return .previous

        case .next:
            return .next

        case .up:
            return .spatial(.up)

        case .down:
            return .spatial(.down)

        case .left:
            return .spatial(.left)

        case .right:
            return .spatial(.right)
        }
    }
}
#endif

extension XGhostty {
    /// The type of a clipboard request
    enum ClipboardRequest {
        /// A direct paste of clipboard contents
        case paste

        /// An application is attempting to read from the clipboard using OSC 52
        case osc_52_read

        /// An application is attempting to write to the clipboard using OSC 52
        case osc_52_write(OSPasteboard?)

        /// The text to show in the clipboard confirmation prompt for a given request type
        func text() -> String {
            switch self {
            case .paste:
                return """
                Pasting this text to the terminal may be dangerous as it looks like some commands may be executed.
                """
            case .osc_52_read:
                return """
                An application is attempting to read from the clipboard.
                The current clipboard contents are shown below.
                """
            case .osc_52_write:
                return """
                An application is attempting to write to the clipboard.
                The content to write is shown below.
                """
            }
        }

        static func from(request: xghostty_clipboard_request_e) -> ClipboardRequest? {
            switch request {
            case XGHOSTTY_CLIPBOARD_REQUEST_PASTE:
                return .paste
            case XGHOSTTY_CLIPBOARD_REQUEST_OSC_52_READ:
                return .osc_52_read
            case XGHOSTTY_CLIPBOARD_REQUEST_OSC_52_WRITE:
                return .osc_52_write(nil)
            default:
                return nil
            }
        }
    }

    struct ClipboardContent {
        let mime: String
        let data: String

        static func from(content: xghostty_clipboard_content_s) -> ClipboardContent? {
            guard let mimePtr = content.mime,
                  let dataPtr = content.data else {
                return nil
            }

            return ClipboardContent(
                mime: String(cString: mimePtr),
                data: String(cString: dataPtr)
            )
        }
    }

    /// Enum for the macos-window-buttons config option
    enum MacOSWindowButtons: String {
        case visible
        case hidden
    }

    /// Enum for the macos-titlebar-proxy-icon config option
    enum MacOSTitlebarProxyIcon: String {
        case visible
        case hidden
    }

    /// Enum for auto-update-channel config option
    enum AutoUpdateChannel: String {
        case tip
        case stable
    }
}

// MARK: Surface Notification

extension Notification.Name {
    /// Configuration change. If the object is nil then it is app-wide. Otherwise its surface-specific.
    static let ghosttyConfigDidChange = Notification.Name("com.mitchellh.xghostty.configDidChange")
    static let GhosttyConfigChangeKey = ghosttyConfigDidChange.rawValue

    /// Color change. Object is the surface changing.
    static let ghosttyColorDidChange = Notification.Name("com.mitchellh.xghostty.ghosttyColorDidChange")
    static let GhosttyColorChangeKey = ghosttyColorDidChange.rawValue

    /// Resize the window to a default size.
    static let ghosttyResetWindowSize = Notification.Name("com.mitchellh.xghostty.resetWindowSize")

    /// Ring the bell
    static let ghosttyBellDidRing = Notification.Name("com.mitchellh.xghostty.ghosttyBellDidRing")

    /// The active selection changed
    static let ghosttySelectionDidChange = Notification.Name("com.mitchellh.xghostty.ghosttySelectionDidChange")

    /// Readonly mode changed
    static let ghosttyDidChangeReadonly = Notification.Name("com.mitchellh.xghostty.didChangeReadonly")
    static let ReadonlyKey = ghosttyDidChangeReadonly.rawValue + ".readonly"
    static let ghosttyCommandPaletteDidToggle = Notification.Name("com.mitchellh.xghostty.commandPaletteDidToggle")

    /// Toggle maximize of current window
    static let ghosttyMaximizeDidToggle = Notification.Name("com.mitchellh.xghostty.maximizeDidToggle")

    /// Notification sent when scrollbar updates
    static let ghosttyDidUpdateScrollbar = Notification.Name("com.mitchellh.xghostty.didUpdateScrollbar")
    static let ScrollbarKey = ghosttyDidUpdateScrollbar.rawValue + ".scrollbar"

    /// Focus the search field
    static let ghosttySearchFocus = Notification.Name("com.mitchellh.xghostty.searchFocus")
}

// NOTE: I am moving all of these to Notification.Name extensions over time. This
// namespace was the old namespace.
extension XGhostty.Notification {
    /// Used to pass a configuration along when creating a new tab/window/split.
    static let NewSurfaceConfigKey = "com.mitchellh.xghostty.newSurfaceConfig"

    /// Posted when a new split is requested. The sending object will be the surface that had focus. The
    /// userdata has one key "direction" with the direction to split to.
    static let ghosttyNewSplit = Notification.Name("com.mitchellh.xghostty.newSplit")

    /// Posted when a new project split is requested. Like `ghosttyNewSplit`, the sending object is the
    /// surface that had focus and the userinfo carries a "direction" key, but this creates a sibling
    /// project in the workspace's project tree rather than a split within the focused project (`SPEC.md` §11.1).
    static let ghosttyNewProject = Notification.Name("com.mitchellh.xghostty.newProject")

    /// Posted when `rename_project` is requested. The sending object is the surface that had focus;
    /// the focused project enters inline-rename mode (`SPEC.md` §7.1).
    static let ghosttyRenameProject = Notification.Name("com.mitchellh.xghostty.renameProject")

    /// Posted when `set_project_title:<name>` is requested. The sending object is the surface that
    /// had focus; the userinfo carries a "title" key with the new name (`SPEC.md` §9.1).
    static let ghosttySetProjectTitle = Notification.Name("com.mitchellh.xghostty.setProjectTitle")

    /// Posted when `goto_project` is requested. The sending object is the surface that had focus;
    /// the userinfo carries a `ProjectDirectionKey` (a `SplitFocusDirection`). Focus moves to the
    /// visible neighbor project in that direction (`SPEC.md` §11.3).
    static let ghosttyGotoProject = Notification.Name("com.mitchellh.xghostty.gotoProject")
    static let ProjectDirectionKey = ghosttyGotoProject.rawValue + ".direction"

    /// Posted when `goto_project:<1-9>` is requested. The sending object is the surface that had
    /// focus; the userinfo carries a `GotoProjectIndexKey` with the 1-based project number (an `Int`).
    /// Focus moves to that numbered visible project, clearing any project zoom on the way
    /// (`SPEC.md` §11.3). Kept separate from `ghosttyGotoProject` because the semantics differ:
    /// the directional form is a no-op while zoomed, the indexed form un-zooms and jumps.
    static let ghosttyGotoProjectIndex = Notification.Name("com.mitchellh.xghostty.gotoProjectIndex")
    static let GotoProjectIndexKey = ghosttyGotoProjectIndex.rawValue + ".index"

    /// Posted when `move_project` is requested. The sending object is the surface that had focus;
    /// the userinfo carries a `MoveProjectDirectionKey` (a `SplitFocusDirection`). The focused project
    /// swaps places with its neighbor in that direction (`SPEC.md` §11.3).
    static let ghosttyMoveProject = Notification.Name("com.mitchellh.xghostty.moveProject")
    static let MoveProjectDirectionKey = ghosttyMoveProject.rawValue + ".direction"

    /// Posted when `toggle_project_zoom` is requested. The sending object is the surface that had
    /// focus; the focused project's zoom is toggled (`SPEC.md` §11.6).
    static let ghosttyToggleProjectZoom = Notification.Name("com.mitchellh.xghostty.toggleProjectZoom")

    /// Posted when `hide_project` is requested. The sending object is the surface that had focus;
    /// the focused project is hidden and focus moves to a visible neighbor (`SPEC.md` §11.7).
    static let ghosttyHideProject = Notification.Name("com.mitchellh.xghostty.hideProject")

    /// Posted when `show_project:<name>` is requested. The sending object is the surface that had
    /// focus; the userinfo carries a `ShowProjectNameKey` with the target project's name. The matching
    /// hidden project is shown and focused (`SPEC.md` §11.8).
    static let ghosttyShowProject = Notification.Name("com.mitchellh.xghostty.showProject")
    static let ShowProjectNameKey = ghosttyShowProject.rawValue + ".name"

    /// Posted when `close_project` is requested. The sending object is the surface that had focus;
    /// the focused project is closed after confirmation and focus moves to the nearest remaining
    /// project, or the tab/window closes when it was the only project (`SPEC.md` §11.9, §18.5).
    static let ghosttyCloseProject = Notification.Name("com.mitchellh.xghostty.closeProject")

    /// Posted when `edit_project_note` is requested. The sending object is the surface that had
    /// focus; the focused project's note editor overlay opens.
    static let ghosttyEditProjectNote = Notification.Name("com.mitchellh.xghostty.editProjectNote")

    /// Posted when `toggle_note_overview` is requested. The sending object is the surface that
    /// had focus; the read-only note overview over all visible projects is toggled.
    static let ghosttyToggleNoteOverview = Notification.Name("com.mitchellh.xghostty.toggleNoteOverview")

    /// Posted when `set_primary` is requested. The sending object is the surface that had
    /// focus; the focused pane becomes its project's primary pane (zoom-only, `SPEC.md` §22.4).
    static let ghosttySetPrimary = Notification.Name("com.mitchellh.xghostty.setPrimary")

    /// Posted when `sort_projects_by_priority` is requested. The sending object is the surface
    /// that had focus; the visible projects' layout reorders by priority (`SPEC.md` §24.4).
    static let ghosttySortProjectsByPriority = Notification.Name("com.mitchellh.xghostty.sortProjectsByPriority")

    /// Posted when `sort_projects_by_deadline` is requested. The sending object is the surface
    /// that had focus; the visible projects' layout reorders by deadline (`SPEC.md` §24.4).
    static let ghosttySortProjectsByDeadline = Notification.Name("com.mitchellh.xghostty.sortProjectsByDeadline")

    /// Posted when `choose_project_layout` is requested. The sending object is the surface
    /// that had focus; the layout-selection overlay opens (`SPEC.md` §26.2).
    static let ghosttyChooseProjectLayout = Notification.Name("com.mitchellh.xghostty.chooseProjectLayout")

    /// Posted when `list_projects` is requested. The sending object is the surface
    /// that had focus; the project-list overlay opens (`SPEC.md` §27.1).
    static let ghosttyListProjects = Notification.Name("com.mitchellh.xghostty.listProjects")

    /// Close the calling surface.
    static let ghosttyCloseSurface = Notification.Name("com.mitchellh.xghostty.closeSurface")

    /// Posted when a surface's child process has exited (any way: normal exit,
    /// abnormal exit, process death). The sending object is the surface. The
    /// core never closes a surface on child exit; the project layer judges what
    /// the exit means for the pane — close an exited sibling pane, or keep a
    /// project's last pane as a terminated pane (deletion protection).
    static let ghosttyChildExited = Notification.Name("com.mitchellh.xghostty.childExited")
    /// Bool: whether the exit was judged abnormal (runtime below the
    /// `abnormal-command-exit-runtime` threshold).
    static let ChildExitedAbnormalKey = ghosttyChildExited.rawValue + ".abnormal"

    /// Posted when a key is pressed on a surface whose child process has
    /// exited. The sending object is the surface. The pane no longer talks to
    /// a live pty, so the project layer owns the key: Enter restarts a
    /// terminated pane's shell; any key closes an exited sibling pane.
    static let ghosttyExitedSurfaceKeyDown = Notification.Name("com.mitchellh.xghostty.exitedSurfaceKeyDown")
    /// Bool: whether the pressed key was Return / keypad Enter.
    static let ExitedSurfaceKeyIsReturnKey = ghosttyExitedSurfaceKeyDown.rawValue + ".isReturn"

    /// Focus previous/next split. Has a SplitFocusDirection in the userinfo.
    static let ghosttyFocusSplit = Notification.Name("com.mitchellh.xghostty.focusSplit")
    static let SplitDirectionKey = ghosttyFocusSplit.rawValue

    /// Present terminal. Bring the surface's window to focus without activating the app.
    static let ghosttyPresentTerminal = Notification.Name("com.mitchellh.xghostty.presentTerminal")

    /// Toggle fullscreen of current window
    static let ghosttyToggleFullscreen = Notification.Name("com.mitchellh.xghostty.toggleFullscreen")
    static let FullscreenModeKey = ghosttyToggleFullscreen.rawValue

    /// Notification sent to toggle split maximize/unmaximize.
    static let didToggleSplitZoom = Notification.Name("com.mitchellh.xghostty.didToggleSplitZoom")

    /// Notification
    static let didReceiveInitialWindowFrame = Notification.Name("com.mitchellh.xghostty.didReceiveInitialWindowFrame")
    static let FrameKey = "com.mitchellh.xghostty.frame"

    /// Notification to render the inspector for a surface
    static let inspectorNeedsDisplay = Notification.Name("com.mitchellh.xghostty.inspectorNeedsDisplay")

    /// Notification to show/hide the inspector
    static let didControlInspector = Notification.Name("com.mitchellh.xghostty.didControlInspector")

    static let confirmClipboard = Notification.Name("com.mitchellh.xghostty.confirmClipboard")
    static let ConfirmClipboardStrKey = confirmClipboard.rawValue + ".str"
    static let ConfirmClipboardStateKey = confirmClipboard.rawValue + ".state"
    static let ConfirmClipboardRequestKey = confirmClipboard.rawValue + ".request"

    /// Notification sent to the active split view to resize the split.
    static let didResizeSplit = Notification.Name("com.mitchellh.xghostty.didResizeSplit")
    static let ResizeSplitDirectionKey = didResizeSplit.rawValue + ".direction"
    static let ResizeSplitAmountKey = didResizeSplit.rawValue + ".amount"

    /// Notification sent to the split root to equalize split sizes
    static let didEqualizeSplits = Notification.Name("com.mitchellh.xghostty.didEqualizeSplits")

    /// Notification that renderer health changed
    static let didUpdateRendererHealth = Notification.Name("com.mitchellh.xghostty.didUpdateRendererHealth")

    /// Notifications related to key sequences
    static let didContinueKeySequence = Notification.Name("com.mitchellh.xghostty.didContinueKeySequence")
    static let didEndKeySequence = Notification.Name("com.mitchellh.xghostty.didEndKeySequence")
    static let KeySequenceKey = didContinueKeySequence.rawValue + ".key"

    /// Notifications related to key tables
    static let didChangeKeyTable = Notification.Name("com.mitchellh.xghostty.didChangeKeyTable")
    static let KeyTableKey = didChangeKeyTable.rawValue + ".action"
}

// Make the input enum hashable.
extension xghostty_input_key_e: @retroactive Hashable {}
