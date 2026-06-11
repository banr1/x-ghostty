import Foundation

/// State for a single group: a named container around a pane split tree.
///
/// See `SPEC.md` §5.3. Per the Phase 0 design decision, `paneTree` keeps the
/// existing `SplitTree<Ghostty.SurfaceView>` element type rather than the
/// `SplitTree<SurfaceRef>` shown in the spec, so the existing rendering,
/// action, restore and drag-and-drop pipelines work unchanged. `SurfaceID`
/// values are derived from `SurfaceView.id`.
struct GroupState: Codable, Identifiable {
    let id: GroupID
    var name: String

    /// The pane layout for this group. Element type intentionally kept as
    /// `Ghostty.SurfaceView` (see the type doc above).
    var paneTree: SplitTree<Ghostty.SurfaceView>

    /// The surface that last held focus within this group, identified by
    /// `SurfaceView.id`.
    var focusedSurface: SurfaceID?

    var createdAt: Date
    var lastFocusedAt: Date?

    init(
        id: GroupID,
        name: String,
        paneTree: SplitTree<Ghostty.SurfaceView>,
        focusedSurface: SurfaceID? = nil,
        createdAt: Date,
        lastFocusedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.paneTree = paneTree
        self.focusedSurface = focusedSurface
        self.createdAt = createdAt
        self.lastFocusedAt = lastFocusedAt
    }
}
