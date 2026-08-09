import Foundation

/// The persistent + runtime state of the group layer for a single terminal
/// window/tab.
///
/// `canonicalGroupTree` is the single source of truth for group placement.
/// Visibility (`hiddenGroupIDs`) and `zoomedGroup` are derived display state
/// that must never be persisted (see `SPEC.md` §4.1, §12.2, §13).
///
/// Generic over the pane element for the same reason as `GroupStateOf`:
/// `WorkspaceState` is the runtime specialization, and `XGhosttyTests`
/// exercises the same code with value-type panes.
struct WorkspaceStateOf<Pane: Codable & Identifiable & Equatable> where Pane.ID == UUID {
    static var currentVersion: Int { 1 }

    /// The maximum number of simultaneously *visible* groups.
    ///
    /// Visible groups are numbered 1..9 in the header (`ordinal(of:)`) and are
    /// addressed directly by `goto_group:<1-9>` (Cmd+1..9), so nine is the
    /// hard ceiling: `new_group_split` and `show_group` are silently rejected
    /// once it is reached, and a restore caps the visible set at this many
    /// (the extras stay alive on the hidden shelf).
    static var maxVisibleGroups: Int { 9 }

    var version: Int

    /// Canonical placement of every group. Always the source of truth.
    var canonicalGroupTree: SplitTree<GroupRef>

    /// All groups keyed by id. Invariant: every leaf in `canonicalGroupTree`
    /// has a matching entry here (`SPEC.md` §14.1). The converse holds only for
    /// *visible* groups: hiding removes a group's leaf from the canonical tree
    /// while its `GroupState` (and its live panes) stay here, so the entries not
    /// covered by a leaf are exactly `hiddenGroupIDs` (§14.2).
    var groups: [GroupID: GroupStateOf<Pane>]

    // MARK: Runtime-only (never persisted; cleared on decode)

    var hiddenGroupIDs: Set<GroupID> = []
    var focusedGroup: GroupID?
    var zoomedGroup: GroupID?

    init(
        canonicalGroupTree: SplitTree<GroupRef>,
        groups: [GroupID: GroupStateOf<Pane>],
        hiddenGroupIDs: Set<GroupID> = [],
        focusedGroup: GroupID? = nil,
        zoomedGroup: GroupID? = nil,
        version: Int = Self.currentVersion
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

    // MARK: Group numbering (SPEC §4.1)

    /// Every visible group in canonical traversal order.
    ///
    /// Canonical leaves *are* the visible groups (hiding removes the leaf,
    /// §11.7 / §14.3), so iterating `canonicalGroupTree` yields exactly the
    /// visible set. The order is `SplitTree`'s in-order leaf traversal — the
    /// same order `previous`/`next` focus uses — so the numbering matches how
    /// the groups read on screen, left-to-right / top-to-bottom.
    ///
    /// Deliberately derived from the *canonical* tree rather than
    /// `effectiveVisibleGroupTree`: a zoomed group keeps the number it has in
    /// the full layout instead of collapsing to `1`.
    var visibleGroupIDs: [GroupID] {
        canonicalGroupTree.map(\.id)
    }

    /// The number of currently visible groups. Capped at `maxVisibleGroups`.
    var visibleGroupCount: Int {
        canonicalGroupTree.count
    }

    /// The 1-based display number of `id`, or `nil` when it is not visible.
    /// This is a pure display/addressing derivation — it is never stored into
    /// `GroupState.name`.
    func ordinal(of id: GroupID) -> Int? {
        visibleGroupIDs.firstIndex(of: id).map { $0 + 1 }
    }

    /// The visible group with 1-based number `ordinal`, or `nil` when there are
    /// fewer than `ordinal` visible groups. The inverse of `ordinal(of:)`.
    func visibleGroupID(ordinal: Int) -> GroupID? {
        let ids = visibleGroupIDs
        guard ordinal >= 1, ordinal <= ids.count else { return nil }
        return ids[ordinal - 1]
    }

    /// Every visible group's display number, keyed by id. Computed once per
    /// render pass so the view tree does not do a linear scan per group.
    var groupOrdinals: [GroupID: Int] {
        var result: [GroupID: Int] = [:]
        for (index, id) in visibleGroupIDs.enumerated() {
            result[id] = index + 1
        }
        return result
    }

    // MARK: Overall-view display target (SPEC §22.3)

    /// The single pane each group draws in the overall (non-zoomed) view:
    /// exactly the group's primary pane. This is the model-layer judgment the
    /// render path consumes — a group appears here iff it is visible, and its
    /// value is its one flagged pane (a group with an empty pane tree has
    /// nothing to draw and is absent). The zoomed local view does not use
    /// this: it shows the full pane layout as before.
    var overallViewPaneIDs: [GroupID: SurfaceID] {
        var result: [GroupID: SurfaceID] = [:]
        for id in visibleGroupIDs {
            if let primary = groups[id]?.primaryPane {
                result[id] = primary
            }
        }
        return result
    }

    // MARK: Primary mark (SPEC §22.6)

    /// The pane that shows the primary mark, keyed by group: the zoomed
    /// group's primary pane, and only while that group holds multiple panes.
    /// Empty in the overall view (which renders nothing but primaries, so a
    /// mark would be noise) and for single-pane groups (the only pane is
    /// trivially the primary).
    var primaryMarkPaneIDs: [GroupID: SurfaceID] {
        guard let zoomedGroup,
              let group = groups[zoomedGroup],
              group.paneTree.isSplit,
              let primary = group.primaryPane else { return [:] }
        return [zoomedGroup: primary]
    }

    // MARK: Overall-view focus & pane operations (SPEC §22.4–22.5)

    /// Whether pane-level operations (split, inter-pane focus movement, pane
    /// zoom, resize/equalize) are currently allowed: only while the focused
    /// group is zoomed (SPEC §22.5). In the overall view they are no-ops —
    /// only the primary pane is even rendered there — and a zoom on a
    /// *different* group (a transient divergence) disables them too, since
    /// they would act on an invisible tree.
    var paneOperationsEnabled: Bool {
        zoomedGroup != nil && zoomedGroup == focusedGroup
    }

    /// While in the overall (non-zoomed) view, keyboard input and focus always
    /// go to the focused group's primary pane (SPEC §22.4): it is the only
    /// pane rendered. Called after every mutation that can land the state in
    /// the overall view, so a zoom release — or any focus move outside zoom —
    /// snaps the stored focus onto the primary. No-op while zoomed, and for
    /// an empty pane tree (no primary to snap to).
    mutating func snapFocusToPrimaryInOverallView() {
        guard zoomedGroup == nil,
              let id = focusedGroup,
              var group = groups[id],
              let primary = group.primaryPane,
              group.focusedSurface != primary else { return }
        group.focusedSurface = primary
        groups[id] = group
    }

    // MARK: Mutations

    /// Persist `paneTree` into the focused group. No-op when nothing is focused.
    /// Called before every focused-group switch so the outgoing group's layout
    /// is not lost.
    mutating func saveOutgoingPaneTree(_ paneTree: SplitTree<Pane>) {
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

    /// Prune the canonical tree down to `maxVisibleGroups` leaves, moving the
    /// extras onto the hidden shelf.
    ///
    /// Only a legacy save (written before the cap existed) can carry more than
    /// nine canonical leaves. The first nine in traversal order keep their slot
    /// — and therefore their numbers 1..9 — and everything after them becomes a
    /// hidden group: still alive in `groups`, reachable from the shelf, and
    /// with no canonical leaf so invariant §14.3 keeps holding.
    private mutating func capVisibleGroups() {
        let visible = visibleGroupIDs
        guard visible.count > Self.maxVisibleGroups else { return }

        for id in visible.dropFirst(Self.maxVisibleGroups) {
            canonicalGroupTree = canonicalGroupTree.removing(.leaf(view: GroupRef(id: id)))
            hiddenGroupIDs.insert(id)
        }
    }

    /// Re-attach groups that exist in `groups` but have no leaf in
    /// `canonicalGroupTree`, up to the `maxVisibleGroups` cap.
    ///
    /// Hiding removes a group's leaf from the canonical tree (`SPEC.md` §11.7)
    /// and `hiddenGroupIDs` is never persisted (§12.2), so quitting with hidden
    /// groups would otherwise leave them orphaned in `groups`: alive, restored,
    /// but unreachable. Each one splits the trailing leaf in creation order,
    /// matching where `show_group` puts them (§11.8).
    ///
    /// Only as many orphans as fit under the visible cap are re-attached; the
    /// rest stay hidden and reachable from the shelf, exactly as if the user
    /// had hit the cap interactively.
    private mutating func reconcileOrphanedGroups() {
        let placed = Set(visibleGroupIDs)
        let orphans = groups
            .filter { !placed.contains($0.key) }
            .sorted { ($0.value.createdAt, $0.key.rawValue.uuidString) <
                      ($1.value.createdAt, $1.key.rawValue.uuidString) }

        var visibleCount = placed.count
        for (id, _) in orphans {
            guard visibleCount < Self.maxVisibleGroups else {
                hiddenGroupIDs.insert(id)
                continue
            }

            canonicalGroupTree = canonicalGroupTree.appendingAtTrailingLeaf(GroupRef(id: id))
            visibleCount += 1
        }
    }

    /// The structural half of a restore, shared by `restoring(_:)` and the
    /// `Codable` init so both paths land on the same shape: runtime state is
    /// zeroed, at most `maxVisibleGroups` groups are visible, and every group
    /// is either a canonical leaf or on the hidden shelf.
    ///
    /// It is deterministic (traversal order, then creation order), so running it
    /// twice — decode then `restoring(_:)` — produces the same result.
    private mutating func applyRestoreLayout() {
        clearRuntimeState()
        capVisibleGroups()
        reconcileOrphanedGroups()
    }

    /// Apply restore semantics to a decoded/saved workspace (`SPEC.md` §12.3).
    ///
    /// Nothing comes back zoomed, and up to `maxVisibleGroups` groups come back
    /// visible: groups that were hidden when the state was saved are re-attached
    /// by splitting the trailing leaf while there is room under the cap, and any
    /// beyond it stay on the hidden shelf (see `applyRestoreLayout`).
    /// `focusedGroup` is validated against the surviving groups and the canonical
    /// tree; if it no longer points at a *visible* group — including when the cap
    /// pushed it onto the shelf — it falls back to the canonical tree's first leaf.
    static func restoring(_ saved: Self) -> Self {
        var restored = saved
        restored.applyRestoreLayout()

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

/// The runtime specialization: pane elements are live surface views.
typealias WorkspaceState = WorkspaceStateOf<XGhostty.SurfaceView>

extension WorkspaceStateOf: Codable {
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
            ?? Self.currentVersion
        self.canonicalGroupTree = try c.decode(SplitTree<GroupRef>.self, forKey: .canonicalGroupTree)

        // Dictionaries with non-String/Int keys encode as JSON arrays by
        // default; we persist `groups` as a keyed object using uuid strings so
        // the JSON stays a readable object (see `encode(to:)`).
        let keyed = try c.decode([String: GroupStateOf<Pane>].self, forKey: .groups)
        self.groups = Dictionary(uniqueKeysWithValues: keyed.compactMap { key, value in
            UUID(uuidString: key).map { (GroupID(rawValue: $0), value) }
        })

        self.focusedGroup = try c.decodeIfPresent(GroupID.self, forKey: .focusedGroup)

        // Runtime-only state is always reset on decode (`SPEC.md` §12.2), and
        // groups that were hidden when this was encoded (so absent from the
        // persisted tree) are re-attached — up to the visible cap — so nothing
        // is orphaned. `hiddenGroupIDs` is re-derived here rather than decoded:
        // it stays runtime-only, it is just recomputed from the cap.
        self.applyRestoreLayout()
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
