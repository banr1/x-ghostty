import Foundation

/// Drives the group layer for a single terminal window/tab.
///
/// `surfaceTree` on `BaseTerminalController` remains the source of truth for the
/// *focused* group's panes; this model mirrors it (via `replaceFocusedPaneTree`
/// from `surfaceTreeDidChange`) and owns the group structure around it. As of
/// Phase 2 it is an `ObservableObject` so the group-aware render path
/// (`TerminalWorkspaceView`) re-renders on group-structure changes that do not
/// flow through a `surfaceTree` change (e.g. switching the focused group, and —
/// later — rename). See `SPEC.md` §6.2.
final class WorkspaceModel: ObservableObject {
    /// The default group name used while the group layer is single-group. New
    /// groups created via `new_group_split` get random `adjective-noun` names
    /// from `GroupNameGenerator` (`SPEC.md` §8).
    static let defaultGroupName = "Group 1"

    enum WorkspaceError: Error {
        /// There is no focused group to anchor a new group split against.
        case noFocusedGroup
    }

    @Published private(set) var state: WorkspaceState

    /// The group currently in inline-rename mode, or `nil`. Transient UI state:
    /// it lives on the model (not in `WorkspaceState`) so it is never persisted.
    /// Both the double-click gesture and the `rename_group` action set this, so
    /// they share one editing path (`SPEC.md` §7.1).
    @Published var renamingGroup: GroupID?

    /// An empty workspace with no groups. Used as the controller's initial
    /// value before `init(wrapping:)` wraps the real pane tree.
    init() {
        state = WorkspaceState(canonicalGroupTree: .init(), groups: [:])
    }

    /// Construct a model around an existing `WorkspaceState`. Used to rehydrate a
    /// decoded state on restore (`SPEC.md` §12.3) and by tests that need to set
    /// up multi-group / zoomed / hidden states directly.
    init(_ state: WorkspaceState) {
        self.state = state
    }

    /// Wrap an existing single pane tree into one default group (Phase 0).
    init(wrapping paneTree: SplitTree<Ghostty.SurfaceView>, now: Date = Date()) {
        let groupID = GroupID()
        let focused = paneTree.firstLeaf.map { SurfaceID(rawValue: $0.id) }

        let group = GroupState(
            id: groupID,
            name: WorkspaceModel.defaultGroupName,
            paneTree: paneTree,
            focusedSurface: focused,
            createdAt: now,
            lastFocusedAt: focused == nil ? nil : now
        )

        state = WorkspaceState(
            canonicalGroupTree: .init(view: GroupRef(id: groupID)),
            groups: [groupID: group],
            focusedGroup: groupID
        )
    }

    // MARK: Focused group access

    var focusedGroupState: GroupState? {
        guard let id = state.focusedGroup else { return nil }
        return state.groups[id]
    }

    var focusedPaneTree: SplitTree<Ghostty.SurfaceView> {
        get { focusedGroupState?.paneTree ?? .init() }
        set { replaceFocusedPaneTree(newValue) }
    }

    /// Mirror a new pane tree into the focused group, keeping `focusedSurface`
    /// consistent: an explicit focus wins; otherwise a still-present stored
    /// focus is kept; otherwise it falls back to the first leaf.
    func replaceFocusedPaneTree(
        _ paneTree: SplitTree<Ghostty.SurfaceView>,
        focusedSurface: Ghostty.SurfaceView? = nil,
        now: Date = Date()
    ) {
        guard let id = state.focusedGroup, var group = state.groups[id] else { return }

        group.paneTree = paneTree

        if let focusedSurface, paneTree.find(id: focusedSurface.id) != nil {
            group.focusedSurface = SurfaceID(rawValue: focusedSurface.id)
            group.lastFocusedAt = now
        } else if let stored = group.focusedSurface,
                  paneTree.find(id: stored.rawValue) != nil {
            // Keep the existing stored focus; it is still present in the tree.
        } else {
            group.focusedSurface = paneTree.firstLeaf.map { SurfaceID(rawValue: $0.id) }
            if group.focusedSurface != nil { group.lastFocusedAt = now }
        }

        state.groups[id] = group
    }

    /// Record the focused surface for the focused group. Ignored when the
    /// surface is not part of the focused group's pane tree.
    func setFocusedSurface(_ surfaceID: SurfaceID?, now: Date = Date()) {
        guard let groupID = state.focusedGroup, var group = state.groups[groupID] else { return }
        if let surfaceID, group.paneTree.find(id: surfaceID.rawValue) == nil { return }

        group.focusedSurface = surfaceID
        if surfaceID != nil { group.lastFocusedAt = now }
        state.groups[groupID] = group
    }

    // MARK: Group structure

    /// Open `newGroup` as a sibling of the currently focused group and switch
    /// focus to it (`SPEC.md` §11.1). This is the single place group switching
    /// happens, so ordering is handled here once:
    ///
    /// 1. Clear any zoom (`SPEC.md` §18.4: zoomed groups un-zoom first).
    /// 2. Persist the outgoing focused group's live pane tree, captured by the
    ///    caller from `surfaceTree` *before* the switch.
    /// 3. Register `newGroup` and insert its ref next to the focused group in
    ///    the canonical tree.
    /// 4. Switch `focusedGroup` to `newGroup`.
    ///
    /// The caller is then responsible for swapping `surfaceTree` to
    /// `newGroup.paneTree` and moving keyboard focus into its initial pane.
    ///
    /// - Throws: `WorkspaceError.noFocusedGroup` if nothing is focused, or a
    ///   `SplitTree.SplitError` if the canonical insert fails. The model is left
    ///   unchanged on throw.
    func openNewGroup(
        _ newGroup: GroupState,
        direction: SplitTree<GroupRef>.NewDirection,
        savingOutgoingPaneTree outgoing: SplitTree<Ghostty.SurfaceView>
    ) throws {
        guard let anchorID = state.focusedGroup else {
            throw WorkspaceError.noFocusedGroup
        }

        // Build the next state in a local copy so a failed insert leaves the
        // model untouched.
        var next = state

        // §18.4: a new group split un-zooms first.
        next.zoomedGroup = nil

        // Persist the outgoing focused group's panes before switching away.
        if var anchor = next.groups[anchorID] {
            anchor.paneTree = outgoing
            next.groups[anchorID] = anchor
        }

        // Insert the new group next to the focused one. Done before mutating
        // `groups`/`focusedGroup` for real so a throw here is a no-op.
        let newTree = try next.canonicalGroupTree.inserting(
            view: GroupRef(id: newGroup.id),
            at: GroupRef(id: anchorID),
            direction: direction)

        next.canonicalGroupTree = newTree
        next.groups[newGroup.id] = newGroup
        next.focusedGroup = newGroup.id

        state = next
    }

    /// Switch the focused group to `id`, persisting the outgoing focused group's
    /// live pane tree first (captured by the caller from `surfaceTree`). This is
    /// the click-to-focus counterpart of `openNewGroup` and the machinery
    /// `goto_group` (Phase 4) builds on.
    ///
    /// - Returns: the target group's stored last-focused surface so the caller
    ///   can move keyboard focus into it (`SPEC.md` §14.12), or `nil` when the
    ///   switch is a no-op (already focused, or `id` is not a known group).
    @discardableResult
    func switchFocusedGroup(
        to id: GroupID,
        savingOutgoingPaneTree outgoing: SplitTree<Ghostty.SurfaceView>
    ) -> SurfaceID? {
        guard id != state.focusedGroup else { return nil }
        guard state.groups[id] != nil else { return nil }

        var next = state

        // Persist the outgoing focused group's panes before switching away.
        if let outgoingID = next.focusedGroup, var outgoingGroup = next.groups[outgoingID] {
            outgoingGroup.paneTree = outgoing
            next.groups[outgoingID] = outgoingGroup
        }

        next.focusedGroup = id
        state = next

        return state.groups[id]?.focusedSurface
    }

    // MARK: Group navigation & layout (Phase 4)

    /// Resolve the group that `goto_group` in `direction` should focus, using the
    /// visible group tree (`SPEC.md` §11.3). Hidden groups are excluded because
    /// the tree is already pruned to visible leaves.
    ///
    /// - Returns: the target group, or `nil` when the move is a no-op: a group is
    ///   zoomed (§11.3 says no-op while zoomed), there is no focused group, there
    ///   is no neighbor in that direction, or the resolved target is the focused
    ///   group itself (e.g. `next`/`previous` wrapping with a single group).
    func gotoGroupTarget(_ direction: SplitTree<GroupRef>.FocusDirection) -> GroupID? {
        guard state.zoomedGroup == nil else { return nil }
        guard let focusedID = state.focusedGroup else { return nil }
        guard let visibleTree = state.effectiveVisibleGroupTree,
              let node = visibleTree.find(id: focusedID) else { return nil }

        guard let target = visibleTree.focusTarget(for: direction, from: node),
              target.id != focusedID else { return nil }
        return target.id
    }

    /// Resize the canonical split between the focused group and its visible
    /// neighbor in `direction` by `ratioDelta` (`SPEC.md` §11.4).
    ///
    /// The neighbor is found in the *visible* tree (what the user sees), but the
    /// ratio change is applied to the *canonical* tree's lowest common split, so
    /// it stays correct even with hidden groups present. Pixel→ratio conversion
    /// is the caller's responsibility (`SplitTree.adjustRatio`).
    ///
    /// No-op when zoomed, when there is no focused group, when there is no
    /// neighbor that way, or when the lowest common split's orientation does not
    /// match the resize direction.
    func resizeFocusedGroup(
        _ direction: SplitTree<GroupRef>.Spatial.Direction,
        ratioDelta: Double
    ) {
        guard state.zoomedGroup == nil else { return }
        guard let focusedID = state.focusedGroup else { return }
        guard let visibleTree = state.effectiveVisibleGroupTree else { return }

        let focusedRef = GroupRef(id: focusedID)
        guard let neighbor = visibleTree.spatialNeighbor(
            from: focusedRef,
            direction: direction) else { return }

        guard let splitPath = state.canonicalGroupTree.lowestCommonSplitPath(
            between: focusedRef,
            and: neighbor,
            matchingResizeDirection: direction) else { return }

        state.canonicalGroupTree = state.canonicalGroupTree.adjustRatio(
            at: splitPath,
            direction: direction,
            amount: ratioDelta)
    }

    /// Equalize the visible group layout (`SPEC.md` §11.5).
    ///
    /// MVP scope: only runs when no groups are hidden, in which case the visible
    /// tree is the canonical tree and equalizing the whole canonical tree is
    /// exactly right. With hidden groups present this would also rebalance their
    /// (invisible) splits, so it declines and logs instead. The recommended
    /// per-visible-split approach arrives with Phase 5, when hidden groups become
    /// reachable (`SPEC.md` §11.5).
    ///
    /// - Returns: `true` if the layout was equalized, `false` if it declined.
    @discardableResult
    func equalizeGroups() -> Bool {
        guard state.hiddenGroupIDs.isEmpty else {
            Ghostty.logger.warning("equalize_groups skipped: hidden groups present (Phase 5)")
            return false
        }

        state.canonicalGroupTree = state.canonicalGroupTree.equalized()
        return true
    }

    // MARK: Rename (Phase 3)

    /// Enter inline-rename mode for `id`. No-op if the group is unknown.
    func beginRenaming(_ id: GroupID) {
        guard state.groups[id] != nil else { return }
        renamingGroup = id
    }

    /// Enter inline-rename mode for the focused group (`rename_group`, §7.1).
    func beginRenamingFocusedGroup() {
        guard let id = state.focusedGroup else { return }
        beginRenaming(id)
    }

    /// Leave inline-rename mode without changing any name.
    func cancelRenaming() {
        renamingGroup = nil
    }

    /// Rename `id` to `newName` and leave rename mode. Whitespace is trimmed and
    /// an empty result is rejected (the existing name is kept). Shared by the
    /// inline editor's commit and the `set_group_title` action (`SPEC.md` §9.1).
    func renameGroup(_ id: GroupID, to newName: String) {
        defer { if renamingGroup == id { renamingGroup = nil } }

        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var group = state.groups[id], group.name != trimmed else { return }

        group.name = trimmed
        state.groups[id] = group
    }
}
