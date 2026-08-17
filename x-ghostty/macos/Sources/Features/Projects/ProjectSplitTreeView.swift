import SwiftUI

/// Renders the project layer: a `SplitTree<ProjectRef>` whose leaves are individual
/// projects (`SPEC.md` §6.1). Mirrors the structure of `TerminalSplitTreeView`
/// one level up — except that project boundaries are **not interactive**
/// (`SPEC.md` §26.3): the arrangement is a projection of the ledger and the
/// remembered layout type, so there is no divider drag and no double-click
/// equalize here. Pane dividers inside a zoomed project keep their existing
/// interactions (they live in `TerminalSplitTreeView`).
struct ProjectSplitTreeView: View {
    let tree: SplitTree<ProjectRef>
    let projects: [ProjectID: ProjectState]
    let focusedProject: ProjectID?

    /// Every visible project's 1-based display number, keyed by id
    /// (`WorkspaceState.projectOrdinals`). Derived from the ledger, so a
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
                labelActions: labelActions)
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
            FixedSplitView(
                direction: split.direction,
                ratio: CGFloat(split.ratio),
                dividerColor: ghostty.config.splitDividerColor,
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
                        labelActions: labelActions)
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
                        labelActions: labelActions)
                })
        }
    }
}

/// A non-interactive split at a fixed ratio: no drag handle, no double-click.
/// The divider is a hairline in the same color as the pane dividers so the
/// two layers read as one visual family.
private struct FixedSplitView<L: View, R: View>: View {
    let direction: SplitTree<ProjectRef>.Direction
    let ratio: CGFloat
    let dividerColor: Color
    @ViewBuilder let left: () -> L
    @ViewBuilder let right: () -> R

    var body: some View {
        GeometryReader { geo in
            switch direction {
            case .horizontal:
                HStack(spacing: 0) {
                    left().frame(width: max(0, geo.size.width * ratio))
                    Rectangle().fill(dividerColor).frame(width: 1)
                    right().frame(maxWidth: .infinity)
                }
            case .vertical:
                VStack(spacing: 0) {
                    left().frame(height: max(0, geo.size.height * ratio))
                    Rectangle().fill(dividerColor).frame(height: 1)
                    right().frame(maxHeight: .infinity)
                }
            }
        }
    }
}
