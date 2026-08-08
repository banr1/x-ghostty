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

/// Renders a single group: a name-header band stacked above its pane split tree
/// (`SPEC.md` §6.3).
///
/// The header is a `VStack` band (not an overlay), so it pushes the terminal
/// layout down by its own height (invariant §14.13). It is always shown (one
/// header per group, §7.1), emphasized when focused and dimmed otherwise.
/// Single-click focuses the group; double-click begins an inline rename
/// (`GroupLabel`).
struct GroupView: View {
    let group: GroupState
    let isFocused: Bool

    /// This group's 1-based display number, shown as a `"{ordinal}. "` prefix on
    /// the header. `nil` when the group has no number.
    let ordinal: Int?

    /// Whether this group's header is currently in inline-rename mode.
    let isRenaming: Bool

    /// Pane-level operations within this group's terminal split tree. Only the
    /// focused group's tree is mirrored to the controller's `surfaceTree`, so
    /// this routes there.
    let paneAction: (TerminalSplitOperation) -> Void

    /// Focus / rename callbacks for the header.
    let labelActions: GroupLabelActions

    /// Whether the note overview is laying this group's note over its content
    /// (`toggle_note_overview`). Every rendered group is visible, so the flag
    /// is workspace-wide.
    let showsNoteOverlay: Bool

    var body: some View {
        VStack(spacing: 0) {
            GroupLabel(
                name: group.name,
                ordinal: ordinal,
                isFocused: isFocused,
                isRenaming: isRenaming,
                onFocus: { labelActions.focus(group.id) },
                onBeginRename: { labelActions.beginRename(group.id) },
                onCommitRename: { labelActions.commitRename(group.id, $0) },
                onCancelRename: labelActions.cancelRename)

            TerminalSplitTreeView(
                tree: group.paneTree,
                action: paneAction)
        }
        .overlay {
            if showsNoteOverlay {
                GroupNoteOverviewOverlay(group: group)
            }
        }
    }
}
