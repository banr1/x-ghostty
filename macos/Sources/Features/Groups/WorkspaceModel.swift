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

    /// An empty workspace with no groups. Used as the controller's initial
    /// value before `init(wrapping:)` wraps the real pane tree.
    init() {
        state = WorkspaceState(canonicalGroupTree: .init(), groups: [:])
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
}
