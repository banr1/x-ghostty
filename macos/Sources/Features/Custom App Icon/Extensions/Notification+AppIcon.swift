import AppKit

extension Notification.Name {
    /// Distributed Notification for DockTilePlugin to update icon
    ///
    /// XGhostty -> DockTilePlugin
    static let ghosttyIconDidChange = Notification.Name("com.mitchellh.ghostty.iconDidChange")
}
