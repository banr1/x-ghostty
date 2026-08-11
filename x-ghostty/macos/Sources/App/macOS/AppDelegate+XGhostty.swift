import AppKit

// MARK: XGhostty Delegate

/// This implements the XGhostty app delegate protocol which is used by the XGhostty
/// APIs for app-global information.
extension AppDelegate: XGhostty.Delegate {
    func ghosttySurface(id: UUID) -> XGhostty.SurfaceView? {
        // Search every project, not just the focused one: hidden and unfocused
        // projects own live surfaces too, and drop resolution has to reach them.
        // Mirrors `AppDelegate.findSurface(forUUID:)`.
        TerminalController.shared?.allSurfaces.first { $0.id == id }
    }
}
