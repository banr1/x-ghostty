import SwiftUI

/// The top of the group-layer view hierarchy (`SPEC.md` §6.2).
///
/// Renders the effective visible group tree and (from Phase 5) overlays the
/// hidden-group shelf.
///
/// `workspace` is observed (Phase 2): a `surfaceTree` change still re-renders
/// this view via the focused group's mirrored pane tree, but switching the
/// focused group (and, later, renaming) mutates `WorkspaceModel.state` without
/// a `surfaceTree` change, so direct observation is required for those.
struct TerminalWorkspaceView: View {
    @ObservedObject var workspace: WorkspaceModel

    /// Pane-level operations, forwarded to each rendered group. In Phase 1 only
    /// the focused group exists, so this routes to the controller's
    /// `surfaceTree`-based handler.
    let paneAction: (TerminalSplitOperation) -> Void

    /// Switch the focused group (a label single-click). This needs the
    /// controller to swap `surfaceTree`, so it is injected rather than handled
    /// in the model. Rename callbacks are model-only and built below.
    let onFocusGroup: (GroupID) -> Void

    /// Show a hidden group (a shelf pill click, `SPEC.md` §11.8). Like
    /// `onFocusGroup` this swaps `surfaceTree`, so the controller handles it.
    let onShowGroup: (GroupID) -> Void

    /// Hidden groups in a stable display order for the shelf. Sorted by creation
    /// time (then id) so the pill order does not jump as visibility changes.
    private var hiddenGroups: [GroupState] {
        workspace.state.hiddenGroupIDs
            .compactMap { workspace.state.groups[$0] }
            .sorted { ($0.createdAt, $0.id.rawValue.uuidString) < ($1.createdAt, $1.id.rawValue.uuidString) }
    }

    private var labelActions: GroupLabelActions {
        GroupLabelActions(
            focus: onFocusGroup,
            beginRename: { workspace.beginRenaming($0) },
            commitRename: { workspace.renameGroup($0, to: $1) },
            cancelRename: { workspace.cancelRenaming() })
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let tree = workspace.state.effectiveVisibleGroupTree {
                GroupSplitTreeView(
                    tree: tree,
                    groups: workspace.state.groups,
                    focusedGroup: workspace.state.focusedGroup,
                    renamingGroup: workspace.renamingGroup,
                    paneAction: paneAction,
                    labelActions: labelActions)
            }

            // Hidden-group shelf overlay (`SPEC.md` §7.2). Only rendered when
            // groups are hidden; `HiddenGroupShelf` itself draws nothing for an
            // empty list, but skipping it entirely keeps the overlay absent.
            if !hiddenGroups.isEmpty {
                HiddenGroupShelf(groups: hiddenGroups, onShow: onShowGroup)
                    .padding(6)
            }
        }
    }
}
