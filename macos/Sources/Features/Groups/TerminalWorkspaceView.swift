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

            // The hidden-group shelf overlay is added in Phase 5. Until then
            // `hiddenGroupIDs` is always empty, so there is nothing to show.
        }
    }
}
