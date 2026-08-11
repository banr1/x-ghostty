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

    /// Show a hidden project (a shelf pill click, `SPEC.md` §11.8). Like
    /// `onFocusProject` this swaps `surfaceTree`, so the controller handles it.
    let onShowProject: (ProjectID) -> Void

    /// Equalize the project layout (a project-divider double-click, `SPEC.md` §11.5).
    /// The pane-level equivalent routes through `XGhostty.App` because the pane
    /// tree's owner is the controller's `surfaceTree`; the project tree's owner is
    /// the controller too, so this is injected the same way as `onFocusProject`.
    let onEqualizeProjects: () -> Void

    /// Confirm the hide-selection screen (Enter, `SPEC.md` §25). Batch-hiding
    /// can move focus to another project, which swaps `surfaceTree`, so the
    /// controller handles it like `onShowProject`; toggle and cancel are
    /// model-only and wired below.
    let onConfirmHideSelection: () -> Void

    /// Hidden projects in a stable display order for the shelf. Sorted by creation
    /// time (then id) so the pill order does not jump as visibility changes.
    private var hiddenProjects: [ProjectState] {
        workspace.state.hiddenProjectIDs
            .compactMap { workspace.state.projects[$0] }
            .sorted { ($0.createdAt, $0.id.rawValue.uuidString) < ($1.createdAt, $1.id.rawValue.uuidString) }
    }

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
                    labelActions: labelActions,
                    onEqualize: onEqualizeProjects)
            }

            // Hidden-project shelf overlay (`SPEC.md` §7.2). Only rendered when
            // projects are hidden; `HiddenProjectShelf` itself draws nothing for an
            // empty list, but skipping it entirely keeps the overlay absent.
            if !hiddenProjects.isEmpty {
                HiddenProjectShelf(projects: hiddenProjects, onShow: onShowProject)
                    .padding(6)
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
                    priority: project.priority,
                    deadline: project.deadline,
                    onEnd: { workspace.endNoteEditing(saving: $0, priority: $1, deadlineInput: $2) },
                    onCancel: { workspace.cancelNoteEditing() })
            }

            // Note overview interaction layer: while the viewing-only mode is
            // up it blocks the mouse everywhere (the per-project note panels
            // render inside each `ProjectView`) and owns the keyboard so Escape
            // and a re-pressed Cmd+Opt+N leave the mode.
            if workspace.noteOverviewActive {
                ProjectNoteOverviewKeyCatcher(
                    onExit: { workspace.endNoteOverview() },
                    onToggle: { workspace.toggleNoteOverview() })
            }

            // Hide-selection overlay (`SPEC.md` §25): presented while the
            // selection session is up, absent otherwise so the terminal keeps
            // the full area. The listed projects resolve through live state,
            // in ordinal order.
            if let selection = workspace.hideSelection {
                ProjectHideSelector(
                    projects: workspace.hideSelectionProjectIDs.compactMap {
                        workspace.state.projects[$0]
                    },
                    ordinals: workspace.state.projectOrdinals,
                    selection: selection,
                    canConfirm: workspace.canConfirmHideSelection,
                    onToggle: { workspace.toggleHideSelection($0) },
                    onConfirm: onConfirmHideSelection,
                    onCancel: { workspace.cancelHideSelection() })
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
        .onChange(of: workspace.hideSelectionActive) { active in
            // Closing the hide-selection screen hands keyboard focus back to
            // the terminal, exactly like the overlays above.
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
