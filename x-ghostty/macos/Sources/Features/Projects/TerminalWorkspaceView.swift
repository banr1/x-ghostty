import SwiftUI

/// The top of the project-layer view hierarchy (`SPEC.md` §6.2).
///
/// Renders the effective visible project tree and (from Phase 5) overlays the
/// hidden-project shelf.
///
/// `workspace` is observed (Phase 2): a `surfaceTree` change still re-renders
/// this view via the focused project's mirrored pane tree, but switching the
/// focused project (and, later, renaming) mutates `WorkspaceModel.state` without
/// a `surfaceTree` change, so direct observation is required for those.
struct TerminalWorkspaceView: View {
    @ObservedObject var workspace: WorkspaceModel

    /// The last-focused terminal surface, used to hand keyboard focus back to
    /// the terminal when the note editor overlay closes.
    @Environment(\.ghosttyLastFocusedSurface) private var lastFocusedSurface

    /// Pane-level operations, forwarded to each rendered project. In Phase 1 only
    /// the focused project exists, so this routes to the controller's
    /// `surfaceTree`-based handler.
    let paneAction: (TerminalSplitOperation) -> Void

    /// Switch the focused project (a label single-click). This needs the
    /// controller to swap `surfaceTree`, so it is injected rather than handled
    /// in the model. Rename callbacks are model-only and built below.
    let onFocusProject: (ProjectID) -> Void

    /// Toggle a project-list row between hidden and visible (Enter on the
    /// visibility column, `SPEC.md` §27.2). Hiding the focused project moves
    /// focus, which swaps `surfaceTree`, so the controller handles it.
    let onToggleProjectListVisibility: (ProjectID) -> Void

    /// Focus a project-list row and close the list (Enter, `SPEC.md` §27.3).
    /// Swaps `surfaceTree` like `onFocusProject`, so the controller handles it.
    let onFocusProjectListRow: (ProjectID) -> Void

    /// Close the project list (backdrop click, `SPEC.md` §27.3). The
    /// controller handles it so keyboard focus returns to whichever project is
    /// focused *after* the session's toggles, not to the surface that was
    /// focused when the list opened.
    let onCloseProjectList: () -> Void

    /// Close a project-list row's project (row-selection Delete, `SPEC.md`
    /// §27.2). The controller owns the close-equivalent confirmation dialog,
    /// the surface teardown, and the undo.
    let onCloseProjectListRow: (ProjectID) -> Void

    /// Create a new project below the list's cursor row (`Cmd+N` inside the
    /// list, `SPEC.md` §27.4). Needs a fresh `SurfaceView`, so the controller
    /// handles it; the new row comes back through the model's pending title
    /// edit.
    let onCreateProjectListRow: (ProjectID?) -> Void

    /// Choose a layout type in the open selector (Enter, `SPEC.md` §26.2).
    /// The controller registers the project-aware undo; cancel is model-only
    /// and wired below.
    let onChooseLayoutType: (ProjectLayoutType) -> Void

    private var labelActions: ProjectLabelActions {
        ProjectLabelActions(
            focus: onFocusProject,
            beginRename: { workspace.beginRenaming($0) },
            commitRename: { workspace.renameProject($0, to: $1) },
            cancelRename: { workspace.cancelRenaming() },
            // The header-band mouse affordance (SPEC §21.2): opens that
            // project's note editor directly, leaving the project focus unchanged.
            // `beginNoteEditing` already guards the unknown-project and
            // overview-active cases.
            openNote: { workspace.beginNoteEditing($0) })
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let tree = workspace.state.effectiveVisibleProjectTree {
                ProjectSplitTreeView(
                    tree: tree,
                    projects: workspace.state.projects,
                    focusedProject: workspace.state.focusedProject,
                    // Numbers come from the canonical tree, so they stay stable
                    // under zoom and re-pack on hide / show / close / move.
                    ordinals: workspace.state.projectOrdinals,
                    renamingProject: workspace.renamingProject,
                    noteOverview: workspace.noteOverviewActive,
                    // The overall (non-zoomed) view draws only each project's
                    // primary pane; the zoomed local view keeps the full
                    // layout (SPEC §22.3).
                    primaryOnly: workspace.state.zoomedProject == nil,
                    // The primary mark shows only while a multi-pane project
                    // is zoomed (SPEC §22.6).
                    primaryMarks: workspace.state.primaryMarkPaneIDs,
                    // The pane-count badge shows only in the overall view,
                    // on projects holding non-primary panes (SPEC §22.7).
                    paneCountBadges: workspace.state.overallViewPaneCountBadges,
                    paneAction: paneAction,
                    labelActions: labelActions)
            }

            // Note editor overlay: presented while a note is being edited,
            // absent otherwise so the terminal keeps the full area. The project
            // is resolved through live state, so the overlay vanishes if the
            // project disappears mid-edit.
            if let noteID = workspace.noteEditingProject,
               let project = workspace.state.projects[noteID] {
                ProjectNoteEditor(
                    projectName: project.name,
                    note: project.note,
                    onEnd: { workspace.endNoteEditing(saving: $0) },
                    onCancel: { workspace.cancelNoteEditing() },
                    shortcutListActive: workspace.shortcutListActive,
                    onToggleShortcutList: { workspace.toggleShortcutList() })
            }

            // Note overview interaction layer: while the viewing-only mode is
            // up it blocks the mouse everywhere (the per-project note panels
            // render inside each `ProjectView`) and owns the keyboard so Escape
            // and a re-pressed Cmd+Opt+E leave the mode.
            if workspace.noteOverviewActive {
                ProjectNoteOverviewKeyCatcher(
                    onExit: { workspace.endNoteOverview() },
                    onToggle: { workspace.toggleNoteOverview() },
                    onShortcutList: { workspace.toggleShortcutList() })
            }

            // Layout-type selector (`SPEC.md` §26.2): presented while the
            // selector session is up, listing only the current visible
            // count's collapsed choices.
            if workspace.layoutSelectionActive {
                ProjectLayoutSelector(
                    choices: workspace.layoutTypeChoices,
                    current: workspace.currentLayoutTypeChoice,
                    onChoose: onChooseLayoutType,
                    onCancel: { workspace.cancelLayoutSelection() })
            }

            // Project list (`SPEC.md` §27): every project including hidden
            // ones, and the only way back from hidden now that the shelf is
            // gone. Rows resolve through live state, so a toggle re-renders
            // the list in place.
            if workspace.projectListActive {
                ProjectListOverlay(
                    rows: workspace.projectListRows,
                    columns: workspace.state.listColumnOrder,
                    fullNotes: workspace.projectListFullNotes,
                    pendingTitleEdit: workspace.projectListPendingTitleEdit,
                    sortState: workspace.projectSortState,
                    canToggle: { workspace.canToggleProjectListVisibility($0) },
                    canFocus: { workspace.canFocusProjectListRow($0) },
                    isOverdue: {
                        workspace.isProjectOverdue($0, today: ProjectDeadline(from: Date()))
                    },
                    onToggle: onToggleProjectListVisibility,
                    onFocus: onFocusProjectListRow,
                    onClose: onCloseProjectList,
                    onCloseRow: onCloseProjectListRow,
                    // Cell mutations are model-only: no `surfaceTree` swap is
                    // involved, so no controller round-trip is needed.
                    onCommitEdit: { workspace.commitProjectListCellEdit($0, column: $1, for: $2) },
                    // Candidate-menu commits land through the same setters
                    // as every other entry point (SPEC §27.6); model-only.
                    onCommitCandidate: { workspace.commitProjectListCandidate($0, for: $1) },
                    // Cell-value deletion is model-only; the note's
                    // confirmation happens in the overlay before this fires.
                    onDeleteCellValue: { workspace.deleteProjectListCellValue($0, for: $1) },
                    onMoveRow: { workspace.moveProjectListRow($0, by: $1) },
                    // The sorted-move approval is model-only: inherit the
                    // display order as manual, then move (SPEC §24.5).
                    onApproveSortedMove: { workspace.approveSortedRowMove($0, by: $1) },
                    onMoveColumn: { workspace.moveProjectListColumn($0, by: $1) },
                    onToggleFullNotes: { workspace.toggleProjectListFullNotes() },
                    // Applying a sort state is model-only: the ledger
                    // reorders and the arrangement re-forms behind the list
                    // (SPEC §24.5); no `surfaceTree` swap is involved.
                    onSetSortState: { workspace.setProjectSortState($0) },
                    onCreate: onCreateProjectListRow,
                    onConsumePendingTitleEdit: { workspace.clearProjectListPendingTitleEdit() },
                    shortcutListActive: workspace.shortcutListActive,
                    onToggleShortcutList: { workspace.toggleShortcutList() })
            }

            // Shortcut list (`SPEC.md` §30): read-only, stacked above every
            // other layer — it opens over the terminal, a zoom, the list,
            // the note editor, or the overview, and closing it restores
            // that scene untouched. Rendered last so it is topmost.
            if workspace.shortcutListActive {
                ShortcutListOverlay(
                    onClose: { workspace.endShortcutList() })
            }

        }
        .onChange(of: workspace.noteEditingProject) { newValue in
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
        .onChange(of: workspace.layoutSelectionActive) { active in
            // Closing the layout selector hands keyboard focus back to the
            // terminal, exactly like the overlays above.
            if !active {
                DispatchQueue.main.async {
                    if let surface = lastFocusedSurface?.value {
                        surface.window?.makeFirstResponder(surface)
                    }
                }
            }
        }
        .onChange(of: workspace.shortcutListActive) { active in
            // Closing the shortcut list hands keyboard focus back to the
            // terminal ONLY when no other overlay is underneath: closed over
            // the list / note editor / overview, the scene beneath kept its
            // own focus (sink field or text view) the whole time and must
            // get its keyboard back untouched (SPEC §30).
            if !active,
               workspace.noteEditingProject == nil,
               !workspace.noteOverviewActive,
               !workspace.layoutSelectionActive,
               !workspace.projectListActive {
                DispatchQueue.main.async {
                    if let surface = lastFocusedSurface?.value {
                        surface.window?.makeFirstResponder(surface)
                    }
                }
            }
        }
    }
}
