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

    /// The result of closing the focused group (`SPEC.md` §11.9).
    enum CloseGroupOutcome: Equatable {
        /// Focus moved to `target` (its stored last-focused surface in `focus`).
        case switched(target: GroupID, focus: SurfaceID?)
        /// The focused group was the only group; the caller delegates to
        /// tab/window close (`SPEC.md` §18.5). The model is left unchanged so the
        /// close can be undone via the existing tab/window-close path.
        case closedLast
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

    // MARK: Zoom / hide / show (Phase 5)

    /// Whether `toggle_group_zoom` would change anything (`SPEC.md` §11.6).
    /// Zooming is meaningful only when more than one group is visible (so there
    /// is something to zoom into), or when a zoom is already active (so it can be
    /// cleared). A single visible group zooms to itself — a no-op — so the
    /// keybind should fall through rather than be consumed.
    var canToggleGroupZoom: Bool {
        guard state.focusedGroup != nil else { return false }
        if state.zoomedGroup != nil { return true }
        return state.effectiveVisibleGroupTree?.isSplit ?? false
    }

    /// Toggle group-level zoom for the focused group (`SPEC.md` §11.6). Zoom is
    /// a derived display state: it only flips `zoomedGroup`, and rendering reacts
    /// via `effectiveVisibleGroupTree`. Group zoom and inner split zoom compose
    /// (outer→inner, §14.15) because the inner pane tree keeps its own
    /// `zoomed` node. The focused group is always visible, so the §14.5 "zoom is
    /// visible-only" invariant holds.
    func toggleGroupZoom() {
        guard let focusedID = state.focusedGroup else { return }
        state.zoomedGroup = (state.zoomedGroup == focusedID) ? nil : focusedID
    }

    /// The group that would receive focus if `id` were hidden: the nearest
    /// canonical-tree leaf that stays visible once `id` joins the hidden set, or
    /// `nil` when `id` is the last visible group (`SPEC.md` §18.2). Computed on
    /// the canonical tree (ignoring zoom) because a hide un-zooms first (§18.3).
    private func neighborAfterHiding(_ id: GroupID) -> GroupRef? {
        var nextHidden = state.hiddenGroupIDs
        nextHidden.insert(id)
        return state.canonicalGroupTree.nearestLeaf(
            to: GroupRef(id: id),
            matching: { !nextHidden.contains($0.id) })
    }

    /// Whether `hide_group` would succeed for the focused group (`SPEC.md`
    /// §18.2): at least one other group must remain visible afterwards.
    var canHideFocusedGroup: Bool {
        guard let id = state.focusedGroup else { return false }
        return neighborAfterHiding(id) != nil
    }

    /// Hide the focused group (`SPEC.md` §11.7, §18.2–3). The group's processes
    /// stay alive (invariant §14.7): only `hiddenGroupIDs` changes, plus a focus
    /// move to a visible neighbor. `canonicalGroupTree` and `groups` are
    /// unchanged, so `show_group` restores it in place.
    ///
    /// The caller passes the outgoing focused group's live panes; they are
    /// persisted into `groups` (the hidden group keeps its layout) before focus
    /// moves away. A hidden group cannot stay zoomed, so any zoom is cleared
    /// (§18.3).
    ///
    /// - Returns: the neighbor group to focus next and its last-focused surface
    ///   so the caller can swap `surfaceTree` and move keyboard focus, or `nil`
    ///   when the hide is rejected (no focused group, or it is the last visible
    ///   group, §18.2).
    @discardableResult
    func hideFocusedGroup(
        savingOutgoingPaneTree outgoing: SplitTree<Ghostty.SurfaceView>
    ) -> (target: GroupID, focus: SurfaceID?)? {
        guard let hideID = state.focusedGroup else { return nil }
        guard let neighbor = neighborAfterHiding(hideID) else { return nil }

        var next = state

        // The hidden group keeps its current layout alive in `groups`.
        if var hidden = next.groups[hideID] {
            hidden.paneTree = outgoing
            next.groups[hideID] = hidden
        }

        next.hiddenGroupIDs.insert(hideID)
        // §18.3: a hidden group cannot remain zoomed.
        if next.zoomedGroup == hideID { next.zoomedGroup = nil }
        next.focusedGroup = neighbor.id
        state = next

        return (neighbor.id, state.groups[neighbor.id]?.focusedSurface)
    }

    /// The id of a hidden group named `name`, if any. Resolves the
    /// `show_group:<name>` action's argument to a concrete group; the shelf
    /// shows groups by id directly (`SPEC.md` §7.2, §11.8).
    func hiddenGroupID(named name: String) -> GroupID? {
        state.groups.first { id, group in
            state.hiddenGroupIDs.contains(id) && group.name == name
        }?.key
    }

    /// Show the hidden group `id` (`SPEC.md` §11.8): remove it from the hidden
    /// set, clear any zoom, and focus it. The canonical tree is unchanged, so it
    /// reappears in its original place.
    ///
    /// Like `switchFocusedGroup`, the caller passes the outgoing focused group's
    /// live panes so they are persisted before focus moves away.
    ///
    /// - Returns: the shown group's last-focused surface so the caller can move
    ///   keyboard focus into it, or `nil` when `id` is not currently hidden.
    @discardableResult
    func showGroup(
        _ id: GroupID,
        savingOutgoingPaneTree outgoing: SplitTree<Ghostty.SurfaceView>
    ) -> SurfaceID? {
        guard state.hiddenGroupIDs.contains(id) else { return nil }

        var next = state

        // Persist the outgoing focused group's panes before switching away.
        if let outgoingID = next.focusedGroup, var outgoingGroup = next.groups[outgoingID] {
            outgoingGroup.paneTree = outgoing
            next.groups[outgoingID] = outgoingGroup
        }

        next.hiddenGroupIDs.remove(id)
        next.zoomedGroup = nil
        next.focusedGroup = id
        state = next

        return state.groups[id]?.focusedSurface
    }

    // MARK: Close (SPEC §11.9)

    /// Close the focused group (`SPEC.md` §11.9, §18.1, §18.5). Removes it from
    /// the canonical tree, `groups`, and `hiddenGroupIDs`, clears any zoom on it,
    /// and moves focus to the nearest remaining group.
    ///
    /// Confirmation and terminating the group's surfaces are the caller's
    /// responsibility; this only mutates the group structure. The focus target
    /// is resolved on the pre-mutation canonical tree, preferring a visible
    /// neighbor and falling back to any remaining group — which is then revealed
    /// (un-hidden) so the focused group stays visible (invariant §14.6). This
    /// fallback only matters in the unusual case where the focused group is the
    /// last *visible* one but hidden groups remain.
    ///
    /// - Returns: `.switched` after a successful close, `.closedLast` when the
    ///   focused group was the only group (the model is left unchanged so the
    ///   caller can delegate to tab/window close, §18.5), or `nil` if there is no
    ///   focused group.
    @discardableResult
    func closeFocusedGroup() -> CloseGroupOutcome? {
        guard let closeID = state.focusedGroup else { return nil }
        let closeRef = GroupRef(id: closeID)

        // Resolve the next focus target before mutating. `nearestLeaf` already
        // excludes `closeRef` itself; prefer a still-visible group, otherwise
        // take any remaining group.
        let target = state.canonicalGroupTree.nearestLeaf(
            to: closeRef,
            matching: { !state.hiddenGroupIDs.contains($0.id) })
            ?? state.canonicalGroupTree.nearestLeaf(to: closeRef, matching: { _ in true })

        // §18.5: the only group's close is delegated to tab/window close.
        guard let target else { return .closedLast }

        var next = state
        next.canonicalGroupTree = state.canonicalGroupTree.pruningLeaves { $0.id == closeID }
        next.groups.removeValue(forKey: closeID)
        next.hiddenGroupIDs.remove(closeID)
        if next.zoomedGroup == closeID { next.zoomedGroup = nil }
        // Reveal the target if it was hidden (no visible group remained).
        next.hiddenGroupIDs.remove(target.id)
        next.focusedGroup = target.id
        state = next

        return .switched(target: target.id, focus: state.groups[target.id]?.focusedSurface)
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
