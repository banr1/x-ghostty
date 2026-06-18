import Foundation

/// The persistent + runtime state of the group layer for a single terminal
/// window/tab.
///
/// `canonicalGroupTree` is the single source of truth for group placement.
/// Visibility (`hiddenGroupIDs`) and `zoomedGroup` are derived display state
/// that must never be persisted (see `SPEC.md` §4.1, §12.2, §13).
struct WorkspaceState {
    static let currentVersion = 1

    var version: Int

    /// Canonical placement of every group. Always the source of truth.
    var canonicalGroupTree: SplitTree<GroupRef>

    /// All groups keyed by id. Invariant: every leaf in `canonicalGroupTree`
    /// has a matching entry here, and vice versa (`SPEC.md` §14.1–2).
    var groups: [GroupID: GroupState]

    // MARK: Runtime-only (never persisted; cleared on decode)

    var hiddenGroupIDs: Set<GroupID> = []
    var focusedGroup: GroupID?
    var zoomedGroup: GroupID? = nil

    init(
        canonicalGroupTree: SplitTree<GroupRef>,
        groups: [GroupID: GroupState],
        hiddenGroupIDs: Set<GroupID> = [],
        focusedGroup: GroupID? = nil,
        zoomedGroup: GroupID? = nil,
        version: Int = WorkspaceState.currentVersion
    ) {
        self.version = version
        self.canonicalGroupTree = canonicalGroupTree
        self.groups = groups
        self.hiddenGroupIDs = hiddenGroupIDs
        self.focusedGroup = focusedGroup
        self.zoomedGroup = zoomedGroup
    }

    /// The tree used for rendering / focus / hit-testing. Derived from
    /// `canonicalGroupTree`, applying zoom and hidden filtering (`SPEC.md` §13).
    ///
    /// - Returns `nil` when a zoomed group is no longer renderable (hidden or
    ///   missing from the canonical tree).
    var effectiveVisibleGroupTree: SplitTree<GroupRef>? {
        if let zoomedGroup {
            guard !hiddenGroupIDs.contains(zoomedGroup),
                  canonicalGroupTree.find(id: zoomedGroup) != nil
            else { return nil }
            return canonicalGroupTree.treeContainingOnly(GroupRef(id: zoomedGroup))
        }

        return canonicalGroupTree.pruningLeaves { hiddenGroupIDs.contains($0.id) }
    }

    // MARK: Mutations

    /// Persist `paneTree` into the focused group. No-op when nothing is focused.
    /// Called before every focused-group switch so the outgoing group's layout
    /// is not lost.
    mutating func saveOutgoingPaneTree(_ paneTree: SplitTree<Ghostty.SurfaceView>) {
        guard let id = focusedGroup, var group = groups[id] else { return }
        group.paneTree = paneTree
        groups[id] = group
    }

    // MARK: Restore (SPEC §12.3)

    /// Zero-out the runtime-only fields that must never be persisted or survive
    /// a restore (`SPEC.md` §12.2). Called from both the Codable init and
    /// `restoring(_:)` so the list of reset fields is defined once.
    private mutating func clearRuntimeState() {
        hiddenGroupIDs = []
        zoomedGroup = nil
    }

    /// Apply restore semantics to a decoded/saved workspace (`SPEC.md` §12.3).
    ///
    /// Everything comes back visible and non-zoomed. `focusedGroup` is validated
    /// against the surviving groups and the canonical tree; if it no longer
    /// points at a real group it falls back to the canonical tree's first leaf.
    static func restoring(_ saved: WorkspaceState) -> WorkspaceState {
        var restored = saved
        restored.clearRuntimeState()

        let focusValid = restored.focusedGroup.map { id in
            restored.groups[id] != nil && restored.canonicalGroupTree.find(id: id) != nil
        } ?? false
        if !focusValid {
            restored.focusedGroup = restored.canonicalGroupTree.firstLeaf?.id
        }

        return restored
    }
}

// MARK: Codable

extension WorkspaceState: Codable {
    enum CodingKeys: String, CodingKey {
        // Runtime-only fields (`hiddenGroupIDs`, `zoomedGroup`) are intentionally
        // omitted; `focusedGroup` is persisted per `SPEC.md` §12.1.
        case version
        case canonicalGroupTree
        case groups
        case focusedGroup
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try c.decodeIfPresent(Int.self, forKey: .version)
            ?? WorkspaceState.currentVersion
        self.canonicalGroupTree = try c.decode(SplitTree<GroupRef>.self, forKey: .canonicalGroupTree)

        // Dictionaries with non-String/Int keys encode as JSON arrays by
        // default; we persist `groups` as a keyed object using uuid strings so
        // the JSON stays a readable object (see `encode(to:)`).
        let keyed = try c.decode([String: GroupState].self, forKey: .groups)
        self.groups = Dictionary(uniqueKeysWithValues: keyed.compactMap { key, value in
            UUID(uuidString: key).map { (GroupID(rawValue: $0), value) }
        })

        self.focusedGroup = try c.decodeIfPresent(GroupID.self, forKey: .focusedGroup)

        // Runtime-only state is always reset on decode (`SPEC.md` §12.2).
        self.clearRuntimeState()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(canonicalGroupTree, forKey: .canonicalGroupTree)

        let keyed = Dictionary(
            uniqueKeysWithValues: groups.map { ($0.key.rawValue.uuidString, $0.value) }
        )
        try c.encode(keyed, forKey: .groups)

        try c.encodeIfPresent(focusedGroup, forKey: .focusedGroup)
    }
}
