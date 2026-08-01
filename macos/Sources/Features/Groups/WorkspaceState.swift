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
    /// has a matching entry here (`SPEC.md` §14.1). The converse holds only for
    /// *visible* groups: hiding removes a group's leaf from the canonical tree
    /// while its `GroupState` (and its live panes) stay here, so the entries not
    /// covered by a leaf are exactly `hiddenGroupIDs` (§14.2).
    var groups: [GroupID: GroupState]

    // MARK: Runtime-only (never persisted; cleared on decode)

    var hiddenGroupIDs: Set<GroupID> = []
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
    /// `canonicalGroupTree`, applying zoom (`SPEC.md` §13).
    ///
    /// Hidden groups are already absent from `canonicalGroupTree` (hiding removes
    /// the leaf, §11.7), so the pruning pass below is only a defensive backstop
    /// against a stale `hiddenGroupIDs` entry.
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
    mutating func saveOutgoingPaneTree(_ paneTree: SplitTree<XGhostty.SurfaceView>) {
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

    /// Re-attach every group that exists in `groups` but has no leaf in
    /// `canonicalGroupTree`.
    ///
    /// Hiding removes a group's leaf from the canonical tree (`SPEC.md` §11.7)
    /// and `hiddenGroupIDs` is never persisted (§12.2), so quitting with hidden
    /// groups would otherwise leave them orphaned in `groups`: alive, restored,
    /// but unreachable. They are appended at the right edge in creation order and
    /// the whole tree is equalized, matching where `show_group` puts them
    /// (§11.8), so a restore still brings everything back visible (§12.3).
    private mutating func reconcileOrphanedGroups() {
        let placed = Set(canonicalGroupTree.map(\.id))
        let orphans = groups
            .filter { !placed.contains($0.key) }
            .sorted { ($0.value.createdAt, $0.key.rawValue.uuidString) <
                      ($1.value.createdAt, $1.key.rawValue.uuidString) }
        guard !orphans.isEmpty else { return }

        for (id, _) in orphans {
            canonicalGroupTree = canonicalGroupTree.appendingAtRightEdge(GroupRef(id: id))
        }
        canonicalGroupTree = canonicalGroupTree.equalized()
    }

    /// Apply restore semantics to a decoded/saved workspace (`SPEC.md` §12.3).
    ///
    /// Everything comes back visible and non-zoomed; groups that were hidden when
    /// the state was saved are re-attached at the right edge (see
    /// `reconcileOrphanedGroups`). `focusedGroup` is validated against the
    /// surviving groups and the canonical tree; if it no longer points at a real
    /// group it falls back to the canonical tree's first leaf.
    static func restoring(_ saved: WorkspaceState) -> WorkspaceState {
        var restored = saved
        restored.clearRuntimeState()
        restored.reconcileOrphanedGroups()

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

        // Runtime-only state is always reset on decode (`SPEC.md` §12.2), and
        // groups that were hidden when this was encoded (so absent from the
        // persisted tree) are re-attached so nothing is orphaned.
        self.clearRuntimeState()
        self.reconcileOrphanedGroups()
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
