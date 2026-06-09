import Foundation

/// A thin value-type wrapper over `WorkspaceState` that mirrors the focused
/// group's pane tree for `BaseTerminalController`.
///
/// Phase 0 only: `BaseTerminalController.surfaceTree` remains the source of
/// truth for the focused group's panes, and this model is kept in sync from
/// `surfaceTreeDidChange` and `focusedSurface.didSet`. Later phases will
/// promote this to an `ObservableObject` once the group layer drives rendering
/// directly (see `SPEC.md` §6.2).
struct WorkspaceModel {
    /// The default group name used while the group layer is single-group.
    /// Random `adjective-noun` generation arrives in Phase 2 (`SPEC.md` §8).
    static let defaultGroupName = "Group 1"

    private(set) var state: WorkspaceState

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
    mutating func replaceFocusedPaneTree(
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
    mutating func setFocusedSurface(_ surfaceID: SurfaceID?, now: Date = Date()) {
        guard let groupID = state.focusedGroup, var group = state.groups[groupID] else { return }
        if let surfaceID, group.paneTree.find(id: surfaceID.rawValue) == nil { return }

        group.focusedSurface = surfaceID
        if surfaceID != nil { group.lastFocusedAt = now }
        state.groups[groupID] = group
    }
}
