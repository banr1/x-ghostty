import XGhosttyKit

extension FullscreenMode {
    /// Initialize from a XGhostty fullscreen action.
    static func from(ghostty: xghostty_action_fullscreen_e) -> Self? {
        return switch ghostty {
        case XGHOSTTY_FULLSCREEN_NATIVE:
                .native

        case XGHOSTTY_FULLSCREEN_MACOS_NON_NATIVE:
                .nonNative

        case XGHOSTTY_FULLSCREEN_MACOS_NON_NATIVE_VISIBLE_MENU:
                .nonNativeVisibleMenu

        case XGHOSTTY_FULLSCREEN_MACOS_NON_NATIVE_PADDED_NOTCH:
                .nonNativePaddedNotch

        default:
            nil
        }
    }
}
