import Foundation
import Testing
@testable import XGhostty

/// Tests for the hide-selection model layer (`SPEC.md` §25): the selection
/// session over visible projects behind Cmd+Opt+H — multi-toggle, batch hide
/// on confirm, cancel hiding nothing, and the select-all rejection that keeps
/// at least one project visible. Pane trees stay empty because constructing
/// `XGhostty.SurfaceView` leaves requires a live XGhostty app; the selection
/// judgment is independent of pane contents.
struct ProjectHideSelectionTests {
    /// Builds a project with an empty pane tree (see the type doc comment).
    private static func makeEmptyProject(name: String) -> ProjectState {
        ProjectState(id: ProjectID(), name: name, paneTree: .init(), createdAt: Date())
    }

    /// A model with `count` visible projects in canonical order a, b, c, …
    /// (each `openNewProject` splits right of the focused project, so the
    /// traversal order matches creation order). Focus ends on the last one.
    private static func makeModel(visible count: Int) throws -> (model: WorkspaceModel, ids: [ProjectID]) {
        let model = WorkspaceModel(wrapping: .init(), name: "a")
        var ids = [try #require(model.state.focusedProject)]
        for name in ["b", "c", "d", "e"].prefix(count - 1) {
            let project = makeEmptyProject(name: name)
            try model.openNewProject(project, direction: .right, savingOutgoingPaneTree: .init())
            ids.append(project.id)
        }
        return (model, ids)
    }

    // MARK: Opening the session

    @Test func beginHideSelectionListsVisibleProjectsInOrdinalOrder() throws {
        let (model, ids) = try Self.makeModel(visible: 3)
        #expect(model.hideSelectionActive == false)
        #expect(model.hideSelectionProjectIDs.isEmpty)

        model.beginHideSelection()

        #expect(model.hideSelectionActive == true)
        #expect(model.hideSelection == [])
        #expect(model.hideSelectionProjectIDs == ids)
        #expect(model.hideSelectionProjectIDs == model.state.visibleProjectIDs)
    }

    @Test func beginHideSelectionReleasesZoom() throws {
        let (model, ids) = try Self.makeModel(visible: 2)
        var state = model.state
        state.zoomedProject = ids[1]
        let zoomed = WorkspaceModel(state)

        zoomed.beginHideSelection()

        #expect(zoomed.hideSelectionActive == true)
        #expect(zoomed.state.zoomedProject == nil)
    }

    @Test func beginHideSelectionDeclinesForSingleVisibleProject() {
        // With one visible project nothing could ever be hidden (at least one
        // must stay visible), so the screen does not open at all.
        let model = WorkspaceModel(wrapping: .init())
        #expect(model.canBeginHideSelection == false)

        model.beginHideSelection()
        #expect(model.hideSelectionActive == false)
    }

    @Test func beginHideSelectionDeclinesWhileAnotherOverlayIsUp() throws {
        // The note editor owns the keyboard alone.
        let (editing, _) = try Self.makeModel(visible: 2)
        editing.beginNoteEditingFocusedProject()
        #expect(editing.canBeginHideSelection == false)
        editing.beginHideSelection()
        #expect(editing.hideSelectionActive == false)

        // So does the read-only note overview.
        let (overview, _) = try Self.makeModel(visible: 2)
        overview.toggleNoteOverview()
        #expect(overview.canBeginHideSelection == false)
        overview.beginHideSelection()
        #expect(overview.hideSelectionActive == false)
    }

    // MARK: Toggling

    @Test func toggleHideSelectionTogglesMultipleProjects() throws {
        let (model, ids) = try Self.makeModel(visible: 3)
        model.beginHideSelection()

        model.toggleHideSelection(ids[0])
        model.toggleHideSelection(ids[1])
        #expect(model.hideSelection == [ids[0], ids[1]])

        // A second toggle removes the project from the selection again.
        model.toggleHideSelection(ids[0])
        #expect(model.hideSelection == [ids[1]])
    }

    @Test func toggleHideSelectionRejectsHiddenAndUnknownProjects() throws {
        let (model, ids) = try Self.makeModel(visible: 3)
        // Hide one project the pre-existing way so it is on the shelf.
        model.switchFocusedProject(to: ids[0], savingOutgoingPaneTree: .init())
        try #require(model.hideFocusedProject(savingOutgoingPaneTree: .init()))
        #expect(model.state.hiddenProjectIDs == [ids[0]])

        model.beginHideSelection()
        model.toggleHideSelection(ids[0])
        model.toggleHideSelection(ProjectID())
        #expect(model.hideSelection == [])

        // Toggling before the screen opens does nothing either.
        let (inactive, inactiveIDs) = try Self.makeModel(visible: 2)
        inactive.toggleHideSelection(inactiveIDs[0])
        #expect(inactive.hideSelection == nil)
    }

    // MARK: Confirm (S-069: batch hide)

    @Test func confirmHidesSelectedProjectsInOneBatch() throws {
        let (model, ids) = try Self.makeModel(visible: 3)
        #expect(model.state.focusedProject == ids[2])
        model.beginHideSelection()
        model.toggleHideSelection(ids[0])
        model.toggleHideSelection(ids[1])

        let result = try #require(model.confirmHideSelection(savingOutgoingPaneTree: .init()))

        // Both selected projects are hidden in one commit; the focused
        // project was not selected, so focus stays put.
        #expect(model.state.hiddenProjectIDs == [ids[0], ids[1]])
        #expect(model.state.canonicalProjectTree.map(\.id) == [ids[2]])
        #expect(result.target == ids[2])
        #expect(model.state.focusedProject == ids[2])
        // §14.7: the hidden projects stay alive in `projects` behind the
        // shelf entries.
        #expect(model.state.projects.count == 3)
        // The session is closed.
        #expect(model.hideSelectionActive == false)
        #expect(model.hideSelectionProjectIDs.isEmpty)
    }

    @Test func confirmMovesFocusToNearestSurvivorWhenFocusedProjectIsHidden() throws {
        let (model, ids) = try Self.makeModel(visible: 3)
        #expect(model.state.focusedProject == ids[2])
        model.beginHideSelection()
        model.toggleHideSelection(ids[1])
        model.toggleHideSelection(ids[2])

        let result = try #require(model.confirmHideSelection(savingOutgoingPaneTree: .init()))

        #expect(model.state.hiddenProjectIDs == [ids[1], ids[2]])
        #expect(result.target == ids[0])
        #expect(model.state.focusedProject == ids[0])
        #expect(model.state.canonicalProjectTree.map(\.id) == [ids[0]])
    }

    @Test func confirmWithEmptySelectionClosesHidingNothing() throws {
        let (model, ids) = try Self.makeModel(visible: 2)
        model.beginHideSelection()
        #expect(model.canConfirmHideSelection == true)

        let result = model.confirmHideSelection(savingOutgoingPaneTree: .init())

        #expect(result == nil)
        #expect(model.hideSelectionActive == false)
        #expect(model.state.hiddenProjectIDs.isEmpty)
        #expect(model.state.visibleProjectIDs == ids)
    }

    // MARK: Cancel (S-069: hides nothing)

    @Test func cancelHideSelectionHidesNothing() throws {
        let (model, ids) = try Self.makeModel(visible: 3)
        let before = model.state
        model.beginHideSelection()
        model.toggleHideSelection(ids[0])
        model.toggleHideSelection(ids[1])

        model.cancelHideSelection()

        // The session is gone and no project was hidden — the workspace is
        // exactly what it was before the screen opened.
        #expect(model.hideSelectionActive == false)
        #expect(model.state.hiddenProjectIDs.isEmpty)
        #expect(model.state.visibleProjectIDs == before.visibleProjectIDs)
        #expect(model.state.focusedProject == before.focusedProject)
        #expect(model.state.projects.count == before.projects.count)
    }

    // MARK: Select-all rejection (S-069: at least one stays visible)

    @Test func selectAllCannotConfirmAndAtLeastOneProjectStaysVisible() throws {
        let (model, ids) = try Self.makeModel(visible: 3)
        model.beginHideSelection()
        for id in ids { model.toggleHideSelection(id) }
        #expect(model.hideSelection == Set(ids))
        #expect(model.canConfirmHideSelection == false)

        // The rejected confirm hides nothing and keeps the screen up.
        let rejected = model.confirmHideSelection(savingOutgoingPaneTree: .init())
        #expect(rejected == nil)
        #expect(model.hideSelectionActive == true)
        #expect(model.state.hiddenProjectIDs.isEmpty)

        // Deselecting one project makes the selection confirmable, and the
        // deselected project is the one that stays visible.
        model.toggleHideSelection(ids[1])
        #expect(model.canConfirmHideSelection == true)
        let result = try #require(model.confirmHideSelection(savingOutgoingPaneTree: .init()))
        #expect(model.state.hiddenProjectIDs == [ids[0], ids[2]])
        #expect(model.state.visibleProjectIDs == [ids[1]])
        #expect(result.target == ids[1])
    }

    // MARK: The screen owns the interaction while up

    @Test func focusMovesEditingAndSortsAreNoOpsWhileSelectionIsUp() throws {
        let (model, ids) = try Self.makeModel(visible: 3)
        model.beginHideSelection()

        // No focus moves (the same guards as the viewing-only note overview).
        #expect(model.switchFocusedProject(to: ids[0], savingOutgoingPaneTree: .init()) == nil)
        #expect(model.state.focusedProject == ids[2])
        #expect(model.gotoProjectTarget(.spatial(.left)) == nil)
        #expect(model.gotoProjectIndexTarget(1) == nil)

        // No note editing, no note overview, no sorting.
        model.beginNoteEditing(ids[0])
        #expect(model.noteEditingProject == nil)
        model.toggleNoteOverview()
        #expect(model.noteOverviewActive == false)
        #expect(model.canSortVisibleProjects == false)

        // Everything works again once the screen closes.
        model.cancelHideSelection()
        #expect(model.gotoProjectIndexTarget(1) == ids[0])
        #expect(model.canSortVisibleProjects == true)
    }

    @Test func restoreStateAndTeardownEndTheSession() throws {
        let (model, _) = try Self.makeModel(visible: 2)
        let snapshot = model.state
        model.beginHideSelection()
        model.restoreState(snapshot)
        #expect(model.hideSelectionActive == false)

        let (torndown, _) = try Self.makeModel(visible: 2)
        torndown.beginHideSelection()
        torndown.removeAllProjects()
        #expect(torndown.hideSelectionActive == false)
    }

    // MARK: Return path unchanged (S-057)

    @Test func batchHiddenProjectsReturnThroughTheShelfUnchanged() throws {
        let (model, ids) = try Self.makeModel(visible: 3)
        model.beginHideSelection()
        model.toggleHideSelection(ids[0])
        model.toggleHideSelection(ids[1])
        try #require(model.confirmHideSelection(savingOutgoingPaneTree: .init()))

        // The batch-hidden projects are ordinary hidden projects: the
        // existing `show_project` path reveals them exactly as before — back
        // at their own ledger rows (SPEC §27.1).
        #expect(model.canShowProject(ids[0]) == true)
        model.showProject(ids[0], savingOutgoingPaneTree: .init())
        #expect(model.state.hiddenProjectIDs == [ids[1]])
        #expect(model.state.visibleProjectIDs == [ids[0], ids[2]])
        #expect(model.state.focusedProject == ids[0])
    }
}
