import SwiftUI

/// A single project-level operation within the canonical project tree.
///
/// As with `TerminalSplitOperation`, the tree is immutable, so mutating
/// operations are surfaced to the embedder instead of bound directly. Only
/// resize is modelled today; it is wired up in Phase 4 (`resize_project`). Until
/// then the action is optional and dragging a project divider is a no-op.
enum ProjectSplitOperation {
    case resize(Resize)

    struct Resize {
        let node: SplitTree<ProjectRef>.Node
        let ratio: Double
    }
}

/// Renders the project layer: a `SplitTree<ProjectRef>` whose leaves are individual
/// projects (`SPEC.md` §6.1). Mirrors the structure of `TerminalSplitTreeView`
/// one level up.
struct ProjectSplitTreeView: View {
    let tree: SplitTree<ProjectRef>
    let projects: [ProjectID: ProjectState]
    let focusedProject: ProjectID?

    /// Every visible project's 1-based display number, keyed by id
    /// (`WorkspaceState.projectOrdinals`). Derived from the *canonical* tree, so a
    /// zoomed project keeps its number in the full layout instead of showing `1`.
    let ordinals: [ProjectID: Int]

    /// The project currently in inline-rename mode, if any (`WorkspaceModel`).
    let renamingProject: ProjectID?

    /// Whether the note overview is active (`toggle_note_overview`): each
    /// rendered project lays its note over its content.
    let noteOverview: Bool

    /// Whether each project renders only its primary pane (SPEC §22.3): true in
    /// the overall (non-zoomed) view, false while a project is zoomed — the
    /// local view keeps the full pane layout.
    let primaryOnly: Bool

    /// The pane carrying the primary mark, keyed by project
    /// (`WorkspaceState.primaryMarkPaneIDs`, SPEC §22.6): non-empty only
    /// while a multi-pane project is zoomed.
    let primaryMarks: [ProjectID: SurfaceID]

    /// Each project's pane-count badge, keyed by project
    /// (`WorkspaceState.overallViewPaneCountBadges`, SPEC §22.7): non-empty
    /// only in the overall view, for projects holding non-primary panes.
    let paneCountBadges: [ProjectID: Int]

    let paneAction: (TerminalSplitOperation) -> Void

    /// Label focus / rename callbacks.
    let labelActions: ProjectLabelActions

    /// Double-click on a project divider (`equalize_projects`, `SPEC.md` §11.5).
    let onEqualize: () -> Void

    /// Project-boundary resize. Wired up in Phase 4; `nil` until then.
    var projectAction: ((ProjectSplitOperation) -> Void)?

    var body: some View {
        if let node = tree.zoomed ?? tree.root {
            ProjectSplitSubtreeView(
                node: node,
                projects: projects,
                focusedProject: focusedProject,
                ordinals: ordinals,
                renamingProject: renamingProject,
                noteOverview: noteOverview,
                primaryOnly: primaryOnly,
                primaryMarks: primaryMarks,
                paneCountBadges: paneCountBadges,
                paneAction: paneAction,
                labelActions: labelActions,
                onEqualize: onEqualize,
                projectAction: projectAction)
            // Like `TerminalSplitTreeView`, we can't rely on SwiftUI's implicit
            // structural identity across the split tree. Keying on the project
            // tree's structural identity keeps each project's view (and the pane
            // tree nested within it) stable across unrelated mutations.
            // See: https://github.com/ghostty-org/ghostty/issues/7546
            .id(node.structuralIdentity)
        }
    }
}

private struct ProjectSplitSubtreeView: View {
    @EnvironmentObject var ghostty: XGhostty.App

    let node: SplitTree<ProjectRef>.Node
    let projects: [ProjectID: ProjectState]
    let focusedProject: ProjectID?
    let ordinals: [ProjectID: Int]
    let renamingProject: ProjectID?
    let noteOverview: Bool
    let primaryOnly: Bool
    let primaryMarks: [ProjectID: SurfaceID]
    let paneCountBadges: [ProjectID: Int]
    let paneAction: (TerminalSplitOperation) -> Void
    let labelActions: ProjectLabelActions
    let onEqualize: () -> Void
    let projectAction: ((ProjectSplitOperation) -> Void)?

    var body: some View {
        switch node {
        case .leaf(let ref):
            // A leaf whose project is missing from `projects` violates invariant
            // §14.1; render nothing rather than crash if that ever happens.
            if let project = projects[ref.id] {
                ProjectView(
                    project: project,
                    isFocused: ref.id == focusedProject,
                    ordinal: ordinals[ref.id],
                    isRenaming: ref.id == renamingProject,
                    primaryOnly: primaryOnly,
                    primaryMarkPane: primaryMarks[ref.id],
                    paneCountBadge: paneCountBadges[ref.id],
                    paneAction: paneAction,
                    labelActions: labelActions,
                    showsNoteOverlay: noteOverview)
            }

        case .split(let split):
            let splitViewDirection: SplitViewDirection = switch split.direction {
            case .horizontal: .horizontal
            case .vertical: .vertical
            }

            SplitView(
                splitViewDirection,
                .init(get: {
                    CGFloat(split.ratio)
                }, set: {
                    projectAction?(.resize(.init(node: node, ratio: $0)))
                }),
                dividerColor: ghostty.config.splitDividerColor,
                resizeIncrements: .init(width: 1, height: 1),
                left: {
                    ProjectSplitSubtreeView(
                        node: split.left,
                        projects: projects,
                        focusedProject: focusedProject,
                        ordinals: ordinals,
                        renamingProject: renamingProject,
                        noteOverview: noteOverview,
                        primaryOnly: primaryOnly,
                        primaryMarks: primaryMarks,
                        paneCountBadges: paneCountBadges,
                        paneAction: paneAction,
                        labelActions: labelActions,
                        onEqualize: onEqualize,
                        projectAction: projectAction)
                },
                right: {
                    ProjectSplitSubtreeView(
                        node: split.right,
                        projects: projects,
                        focusedProject: focusedProject,
                        ordinals: ordinals,
                        renamingProject: renamingProject,
                        noteOverview: noteOverview,
                        primaryOnly: primaryOnly,
                        primaryMarks: primaryMarks,
                        paneCountBadges: paneCountBadges,
                        paneAction: paneAction,
                        labelActions: labelActions,
                        onEqualize: onEqualize,
                        projectAction: projectAction)
                },
                // Double-clicking any project divider equalizes the whole project
                // layout, exactly like the `equalize_projects` keybind.
                onEqualize: onEqualize
            )
        }
    }
}
