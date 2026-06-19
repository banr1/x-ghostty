import AppKit

// MARK: XGhostty Delegate

/// This implements the XGhostty app delegate protocol which is used by the XGhostty
/// APIs for app-global information.
extension AppDelegate: XGhostty.Delegate {
    func ghosttySurface(id: UUID) -> XGhostty.SurfaceView? {
        for window in NSApp.windows {
            guard let controller = window.windowController as? BaseTerminalController else {
                continue
            }

            for surface in controller.surfaceTree where surface.id == id {
                return surface
            }
        }

        return nil
    }
}
