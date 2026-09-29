import Foundation

/// Stable identifier for a project, the upper layer of the two-level split model.
///
/// See `SPEC.md` §5.1.
struct ProjectID: Codable, Hashable, Identifiable {
    let rawValue: UUID
    var id: UUID { rawValue }

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

/// Stable identifier for a terminal surface within a project's pane tree.
///
/// In Phase 0 the pane tree continues to store `XGhostty.SurfaceView` values
/// directly, so `SurfaceID` is the value-type projection of `SurfaceView.id`.
struct SurfaceID: Codable, Hashable, Identifiable {
    let rawValue: UUID
    var id: UUID { rawValue }

    init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

/// Leaf element of the canonical project tree (`SplitTree<ProjectRef>`).
struct ProjectRef: Codable, Hashable, Identifiable {
    let id: ProjectID
}

/// Leaf element of a project's pane tree in the spec's value-type model.
///
/// Reserved for later phases. Phase 0 keeps `ProjectState.paneTree` typed as
/// `SplitTree<XGhostty.SurfaceView>` (see the `SPEC.md` §5.3 deviation note), so
/// this type is currently unused by the runtime but documents the intended
/// model and keeps the ID vocabulary complete.
struct SurfaceRef: Codable, Hashable, Identifiable {
    let id: SurfaceID
}
