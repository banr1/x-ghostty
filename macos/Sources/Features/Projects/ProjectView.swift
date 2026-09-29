import SwiftUI

/// The label interactions for a project, bundled so they thread cleanly through
/// the project-tree view hierarchy without a parameter explosion.
///
/// `focus` needs the controller (it swaps `surfaceTree`); the rename callbacks
/// are model-only. `TerminalWorkspaceView` builds this from a controller-
/// provided focus closure plus `WorkspaceModel`'s rename methods.
struct ProjectLabelActions {
    var focus: (ProjectID) -> Void
    var beginRename: (ProjectID) -> Void
    var commitRename: (ProjectID, String) -> Void
    var cancelRename: () -> Void
    /// Open the note editor for that project (the header-band mouse affordance,
    /// `SPEC.md` §21.2). Model-only: routes to `beginNoteEditing`, which keeps
    /// the project focus unchanged.
    var openNote: (ProjectID) -> Void
}

/// Renders a single project: a name-header band stacked above its pane split tree
/// (`SPEC.md` §6.3).
///
/// The header is a `VStack` band (not an overlay), so it pushes the terminal
/// layout down by its own height (invariant §14.13). It is always shown (one
/// header per project, §7.1), emphasized when focused and dimmed otherwise.
/// Single-click focuses the project; double-click begins an inline rename
/// (`ProjectLabel`).
struct ProjectView: View {
    let project: ProjectState
    let isFocused: Bool

    /// This project's 1-based display number, shown as a `"{ordinal}. "` prefix on
    /// the header. `nil` when the project has no number.
    let ordinal: Int?

    /// Whether this project's header is currently in inline-rename mode.
    let isRenaming: Bool

    /// Whether only the primary pane is rendered (SPEC §22.3): true in the
    /// overall (non-zoomed) view, false in the zoomed local view, which keeps
    /// the full pane layout.
    let primaryOnly: Bool

    /// The pane carrying the primary mark, or `nil` for no mark
    /// (SPEC §22.6): set only while this project is zoomed with multiple
    /// panes, so the overall view and single-pane projects never show it.
    let primaryMarkPane: SurfaceID?

    /// This project's pane-count badge, or `nil` for no badge (SPEC §22.7):
    /// set only in the overall view when the project holds non-primary panes,
    /// so the zoomed local view and single-pane projects never show it.
    let paneCountBadge: Int?

    /// Pane-level operations within this project's terminal split tree. Only the
    /// focused project's tree is mirrored to the controller's `surfaceTree`, so
    /// this routes there.
    let paneAction: (TerminalSplitOperation) -> Void

    /// Focus / rename callbacks for the header.
    let labelActions: ProjectLabelActions

    /// Whether the note overview is laying this project's note over its content
    /// (`toggle_note_overview`). Every rendered project is visible, so the flag
    /// is workspace-wide.
    let showsNoteOverlay: Bool

    var body: some View {
        VStack(spacing: 0) {
            ProjectLabel(
                name: project.name,
                ordinal: ordinal,
                isFocused: isFocused,
                isRenaming: isRenaming,
                priority: project.priority,
                deadline: project.deadline,
                isOverdue: isOverdue,
                onFocus: { labelActions.focus(project.id) },
                onBeginRename: { labelActions.beginRename(project.id) },
                onCommitRename: { labelActions.commitRename(project.id, $0) },
                onCancelRename: labelActions.cancelRename,
                onOpenNote: { labelActions.openNote(project.id) })

            TerminalSplitTreeView(
                tree: primaryOnly ? project.overallViewPaneTree : project.paneTree,
                markedPane: primaryMarkPane?.rawValue,
                action: paneAction)
                .overlay {
                    // Terminated-state cover (SPEC §23.3): the project's last
                    // pane's shell has exited; the pane area reads as
                    // "finished, resumable" until Enter starts a new shell.
                    if project.isTerminated {
                        ProjectTerminatedPaneView()
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if let paneCountBadge {
                        ProjectPaneCountBadge(count: paneCountBadge)
                    }
                }
        }
        .overlay {
            if showsNoteOverlay {
                ProjectNoteOverviewOverlay(project: project)
            }
        }
    }

    /// Whether this project's deadline is past today (SPEC §24.2). "Today" is
    /// derived at render time; the comparison rule itself lives on
    /// `ProjectDeadline`, so the view only asks the model's judgment.
    private var isOverdue: Bool {
        project.deadline?.isOverdue(today: ProjectDeadline(from: Date())) ?? false
    }
}

/// The subtle top-right badge shown on a project in the overall view when it
/// holds non-primary panes (SPEC §22.7): the project's total pane count on the
/// same thin-material chip styling as the primary mark (`PaneMarkBadge`), so
/// the two read as one family of terminal chrome. In the overall view only
/// the primary pane is rendered, so this is the cue that more panes exist
/// behind it.
private struct ProjectPaneCountBadge: View {
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
