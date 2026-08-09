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

    /// The last-focused terminal surface, used to hand keyboard focus back to
    /// the terminal when the note editor overlay closes.
    @Environment(\.ghosttyLastFocusedSurface) private var lastFocusedSurface

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

    /// Equalize the group layout (a group-divider double-click, `SPEC.md` §11.5).
    /// The pane-level equivalent routes through `XGhostty.App` because the pane
    /// tree's owner is the controller's `surfaceTree`; the group tree's owner is
    /// the controller too, so this is injected the same way as `onFocusGroup`.
    let onEqualizeGroups: () -> Void

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
                    // Numbers come from the canonical tree, so they stay stable
                    // under zoom and re-pack on hide / show / close / move.
                    ordinals: workspace.state.groupOrdinals,
                    renamingGroup: workspace.renamingGroup,
                    noteOverview: workspace.noteOverviewActive,
                    // The overall (non-zoomed) view draws only each group's
                    // primary pane; the zoomed local view keeps the full
                    // layout (SPEC §22.3).
                    primaryOnly: workspace.state.zoomedGroup == nil,
                    // The primary mark shows only while a multi-pane group
                    // is zoomed (SPEC §22.6).
                    primaryMarks: workspace.state.primaryMarkPaneIDs,
                    paneAction: paneAction,
                    labelActions: labelActions,
                    onEqualize: onEqualizeGroups)
            }

            // Hidden-group shelf overlay (`SPEC.md` §7.2). Only rendered when
            // groups are hidden; `HiddenGroupShelf` itself draws nothing for an
            // empty list, but skipping it entirely keeps the overlay absent.
            if !hiddenGroups.isEmpty {
                HiddenGroupShelf(groups: hiddenGroups, onShow: onShowGroup)
                    .padding(6)
            }

            // Note editor overlay: presented while a note is being edited,
            // absent otherwise so the terminal keeps the full area. The group
            // is resolved through live state, so the overlay vanishes if the
            // group disappears mid-edit.
            if let noteID = workspace.noteEditingGroup,
               let group = workspace.state.groups[noteID] {
                GroupNoteEditor(
                    groupName: group.name,
                    note: group.note,
                    onEnd: { workspace.endNoteEditing(saving: $0) },
                    onCancel: { workspace.cancelNoteEditing() })
            }

            // Note overview interaction layer: while the viewing-only mode is
            // up it blocks the mouse everywhere (the per-group note panels
            // render inside each `GroupView`) and owns the keyboard so Escape
            // and a re-pressed Cmd+Opt+N leave the mode.
            if workspace.noteOverviewActive {
                GroupNoteOverviewKeyCatcher(
                    onExit: { workspace.endNoteOverview() },
                    onToggle: { workspace.toggleNoteOverview() })
            }
        }
        .onChange(of: workspace.noteEditingGroup) { newValue in
            // When the note editor closes, hand keyboard focus back to the
            // terminal (same pattern as the command palette's dismissal).
            if newValue == nil {
                DispatchQueue.main.async {
                    if let surface = lastFocusedSurface?.value {
                        surface.window?.makeFirstResponder(surface)
                    }
                }
            }
        }
        .onChange(of: workspace.noteOverviewActive) { active in
            // Leaving the overview hands keyboard focus back to the terminal,
            // exactly like the note editor's dismissal above.
            if !active {
                DispatchQueue.main.async {
                    if let surface = lastFocusedSurface?.value {
                        surface.window?.makeFirstResponder(surface)
                    }
                }
            }
        }
    }
}
