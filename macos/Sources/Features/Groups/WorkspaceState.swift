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

    var hiddenGroupIDs: Set<GroupID>
    var focusedGroup: GroupID?
    var zoomedGroup: GroupID?

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
        self.hiddenGroupIDs = []
        self.zoomedGroup = nil
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
