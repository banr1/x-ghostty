import SwiftUI

/// The top of the group-layer view hierarchy (`SPEC.md` §6.2).
///
/// Renders the effective visible group tree and (from Phase 5) overlays the
/// hidden-group shelf.
///
/// Phase 1 note: `workspace` is passed by value rather than observed. The
/// controller's `@Published surfaceTree` remains the single source of truth and
/// the focused group's pane tree is mirrored from it synchronously, so every
/// render-relevant change already flows through a `surfaceTree` change that
/// re-renders this view. Promoting `WorkspaceModel` to an `ObservableObject`
/// is deferred to Phase 2, where changing `focusedGroup` must re-render the
/// group tree without a `surfaceTree` change.
struct TerminalWorkspaceView: View {
    let workspace: WorkspaceModel

    /// Pane-level operations, forwarded to each rendered group. In Phase 1 only
    /// the focused group exists, so this routes to the controller's
    /// `surfaceTree`-based handler.
    let paneAction: (TerminalSplitOperation) -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let tree = workspace.state.effectiveVisibleGroupTree {
                GroupSplitTreeView(
                    tree: tree,
                    groups: workspace.state.groups,
                    focusedGroup: workspace.state.focusedGroup,
                    paneAction: paneAction)
            }

            // The hidden-group shelf overlay is added in Phase 5. Until then
            // `hiddenGroupIDs` is always empty, so there is nothing to show.
        }
    }
}
