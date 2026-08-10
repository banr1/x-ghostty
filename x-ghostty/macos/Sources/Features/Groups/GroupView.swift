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
    /// Open the note editor for that group (the header-band mouse affordance,
    /// `SPEC.md` §21.2). Model-only: routes to `beginNoteEditing`, which keeps
    /// the group focus unchanged.
    var openNote: (GroupID) -> Void
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

    /// Whether only the primary pane is rendered (SPEC §22.3): true in the
    /// overall (non-zoomed) view, false in the zoomed local view, which keeps
    /// the full pane layout.
    let primaryOnly: Bool

    /// The pane carrying the primary mark, or `nil` for no mark
    /// (SPEC §22.6): set only while this group is zoomed with multiple
    /// panes, so the overall view and single-pane groups never show it.
    let primaryMarkPane: SurfaceID?

    /// This group's pane-count badge, or `nil` for no badge (SPEC §22.7):
    /// set only in the overall view when the group holds non-primary panes,
    /// so the zoomed local view and single-pane groups never show it.
    let paneCountBadge: Int?

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
                onCancelRename: labelActions.cancelRename,
                onOpenNote: { labelActions.openNote(group.id) })

            TerminalSplitTreeView(
                tree: primaryOnly ? group.overallViewPaneTree : group.paneTree,
                markedPane: primaryMarkPane?.rawValue,
                action: paneAction)
                .overlay {
                    // Terminated-state cover (SPEC §23.3): the group's last
                    // pane's shell has exited; the pane area reads as
                    // "finished, resumable" until Enter starts a new shell.
                    if group.isTerminated {
                        GroupTerminatedPaneView()
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if let paneCountBadge {
                        GroupPaneCountBadge(count: paneCountBadge)
                    }
                }
        }
        .overlay {
            if showsNoteOverlay {
                GroupNoteOverviewOverlay(group: group)
            }
        }
    }
}

/// The subtle top-right badge shown on a group in the overall view when it
/// holds non-primary panes (SPEC §22.7): the group's total pane count on the
/// same thin-material chip styling as the primary mark (`PaneMarkBadge`), so
/// the two read as one family of terminal chrome. In the overall view only
/// the primary pane is rendered, so this is the cue that more panes exist
/// behind it.
private struct GroupPaneCountBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: 8, weight: .semibold))
            Text("\(count)")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(.secondary)
        .padding(4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
        .padding(6)
        .allowsHitTesting(false)
        .accessibilityLabel("\(count) panes")
    }
}
