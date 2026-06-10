import SwiftUI

/// The label interactions for a group, bundled so they thread cleanly through
/// the group-tree view hierarchy without a parameter explosion.
///
/// `focus` needs the controller (it swaps `surfaceTree`); the rename callbacks
/// are model-only. `TerminalWorkspaceView` builds this from a controller-
/// provided focus closure plus `WorkspaceModel`'s rename methods.
struct GroupLabelActions {
    var focus: (GroupID) -> Void
    var beginRename: (GroupID) -> Void
    var commitRename: (GroupID, String) -> Void
    var cancelRename: () -> Void
}

/// Renders a single group: its pane split tree with a name-label overlay
/// (`SPEC.md` §6.3).
///
/// The label is an overlay (`ZStack`) so it never pushes the terminal layout
/// down (invariant §14.13). It is always shown (one label per group, §7.1),
/// emphasized when focused and dimmed otherwise. Single-click focuses the
/// group; double-click begins an inline rename (`GroupLabel`).
struct GroupView: View {
    let group: GroupState
    let isFocused: Bool

    /// Whether this group's label is currently in inline-rename mode.
    let isRenaming: Bool

    /// Pane-level operations within this group's terminal split tree. Only the
    /// focused group's tree is mirrored to the controller's `surfaceTree`, so
    /// this routes there.
    let paneAction: (TerminalSplitOperation) -> Void

    /// Focus / rename callbacks for the label.
    let labelActions: GroupLabelActions

    var body: some View {
        ZStack(alignment: .topLeading) {
            TerminalSplitTreeView(
                tree: group.paneTree,
                action: paneAction)

            GroupLabel(
                title: group.name,
                isFocused: isFocused,
                isRenaming: isRenaming,
                onFocus: { labelActions.focus(group.id) },
                onBeginRename: { labelActions.beginRename(group.id) },
                onCommitRename: { labelActions.commitRename(group.id, $0) },
                onCancelRename: labelActions.cancelRename)
                .padding(6)
        }
    }
}
