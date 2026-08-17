import Foundation
import Testing
@testable import XGhostty

/// A value-type pane element standing in for `XGhostty.SurfaceView`, which
/// cannot be constructed without a live XGhostty app. The generic model layer
/// runs the exact same code for both element types, so these tests exercise
/// the real layout-type selection logic (SPEC §26.2) with real leaves.
private struct TestPane: Codable, Identifiable, Equatable {
    let id: UUID
    init(id: UUID = UUID()) { self.id = id }
}

private typealias TestProjectState = ProjectStateOf<TestPane>
private typealias TestWorkspaceState = WorkspaceStateOf<TestPane>
private typealias TestWorkspaceModel = WorkspaceModelOf<TestPane>

/// Tests for the layout-type selection session (SPEC §26.2, success
/// condition 16's model half): the selector lists only the current visible
/// count's collapsed choices, Enter remembers the type and re-derives the
/// arrangement without ever changing the project count, Escape changes
/// nothing, and a single choice means there is nothing to choose.
struct ProjectLayoutSelectionTests {
    private static func makeModel(_ count: Int) -> (model: TestWorkspaceModel, ids: [ProjectID]) {
        let base = Date(timeIntervalSince1970: 0)
        let projects = (0..<count).map { i in
            TestProjectState(
                id: ProjectID(), name: "p\(i)",
                paneTree: .init(view: TestPane()),
                createdAt: base.addingTimeInterval(Double(i)))
        }
        let ids = projects.map(\.id)
        let state = TestWorkspaceState(
            projects: Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) }),
            projectOrder: ids,
            focusedProject: ids.first)
        return (TestWorkspaceModel(state), ids)
    }

    // MARK: The choice list (SPEC §26.2)

    @Test func choicesListOnlyTheCurrentVisibleCountsCollapsedSet() {
        let (model, ids) = Self.makeModel(4)
        // Closed: no session, no list.
        #expect(model.layoutTypeChoices.isEmpty)

        model.beginLayoutSelection()
        #expect(model.layoutTypeChoices == ProjectLayoutType.choices(forVisibleCount: 4))

        // Hiding a project mid-session re-judges against the new count (3).
        model.cancelLayoutSelection()
        var state = model.state
        state.setProjectHidden(ids[3], true)
        let three = TestWorkspaceModel(state)
        three.beginLayoutSelection()
        #expect(three.layoutTypeChoices == ProjectLayoutType.choices(forVisibleCount: 3))
    }

    @Test func singleChoiceMeansNothingToChoose() {
        // One visible project: the selector still opens (the human sees the
        // nothing-to-choose message) but the collapsed set holds one entry.
        let (model, _) = Self.makeModel(1)
        #expect(model.canBeginLayoutSelection)
        model.beginLayoutSelection()
        #expect(model.layoutSelectionActive)
        #expect(model.layoutTypeChoices.count == 1)
    }

    @Test func currentChoiceIsTheRememberedTypesRepresentative() {
        let (model, _) = Self.makeModel(3)
        // The default type stands for itself…
        #expect(model.currentLayoutTypeChoice == .default)

        // …and a saved spelling that collapses at this count highlights its
        // kept representative (pedestal/row-major == wide/row-major at n=3).
        var state = model.state
        state.layoutType = ProjectLayoutType(shape: .pedestal, orientation: .rowMajor)
        state.relayout()
        let collapsed = TestWorkspaceModel(state)
        #expect(collapsed.currentLayoutTypeChoice == .default)
    }

    // MARK: Choosing (SPEC §26.2–26.4)

    @Test func enterRemembersTheTypeAndRederivesWithoutChangingProjects() {
        let (model, ids) = Self.makeModel(4)
        let type = ProjectLayoutType(shape: .tall, orientation: .columnMajor)
        model.beginLayoutSelection()

        #expect(model.chooseLayoutType(type))

        // The selector closed, the type is remembered, the arrangement is its
        // projection over the SAME visible rows — the project count and the
        // ledger never change.
        #expect(!model.layoutSelectionActive)
        #expect(model.state.layoutType == type)
        #expect(model.state.projectOrder == ids)
        #expect(model.state.projects.count == 4)
        #expect(model.state.hiddenProjectIDs.isEmpty)
        #expect(model.state.canonicalProjectTree.root == type.tree(over: ids).root)
        // Ordinals still follow the list order.
        #expect(ids.map { model.ordinal(of: $0) } == [1, 2, 3, 4])
    }

    @Test func chooseIsRejectedWhileTheSelectorIsClosed() {
        let (model, _) = Self.makeModel(3)
        let before = model.state

        #expect(!model.chooseLayoutType(ProjectLayoutType(shape: .tall, orientation: .rowMajor)))

        #expect(model.state.layoutType == before.layoutType)
        #expect(model.state.canonicalProjectTree.root == before.canonicalProjectTree.root)
    }

    @Test func escCancelsChangingNothing() {
        let (model, _) = Self.makeModel(4)
        let before = model.state
        model.beginLayoutSelection()

        model.cancelLayoutSelection()

        #expect(!model.layoutSelectionActive)
        #expect(model.state.layoutType == before.layoutType)
        #expect(model.state.projectOrder == before.projectOrder)
        #expect(model.state.canonicalProjectTree.root == before.canonicalProjectTree.root)
    }

    @Test func chosenTypeSurvivesACodableRoundTrip() throws {
        let (model, ids) = Self.makeModel(3)
        let type = ProjectLayoutType(shape: .pedestal, orientation: .columnMajor)
        model.beginLayoutSelection()
        #expect(model.chooseLayoutType(type))

        let data = try JSONEncoder().encode(model.state)
        let decoded = try JSONDecoder().decode(TestWorkspaceState.self, from: data)

        #expect(decoded.layoutType == type)
        #expect(decoded.canonicalProjectTree.root == type.tree(over: ids).root)
    }

    // MARK: Session mechanics

    @Test func beginReleasesZoomAndDeclinesWhileOtherOverlaysUp() {
        let (model, ids) = Self.makeModel(2)
        var state = model.state
        state.zoomedProject = ids[1]
        let zoomed = TestWorkspaceModel(state)
        zoomed.beginLayoutSelection()
        #expect(zoomed.layoutSelectionActive)
        #expect(zoomed.state.zoomedProject == nil)

        // Each overlay owns the keyboard alone: no layout selector while the
        // note editor or the note overview is up.
        let (editing, _) = Self.makeModel(2)
        editing.beginNoteEditingFocusedProject()
        #expect(!editing.canBeginLayoutSelection)
        editing.beginLayoutSelection()
        #expect(!editing.layoutSelectionActive)

        let (overview, _) = Self.makeModel(2)
        overview.toggleNoteOverview()
        #expect(!overview.canBeginLayoutSelection)
    }

    @Test func selectorOwnsTheInteractionWhileUp() {
        let (model, ids) = Self.makeModel(4)
        model.beginLayoutSelection()

        // No focus moves, no note editing, no sorting, no hide, no other
        // overlay while the selector is up.
        #expect(model.switchFocusedProject(to: ids[1], savingOutgoingPaneTree: .init()) == nil)
        #expect(model.gotoProjectIndexTarget(2) == nil)
        model.beginNoteEditing(ids[0])
        #expect(model.noteEditingProject == nil)
        #expect(!model.canSortVisibleProjects)
        #expect(!model.canHideFocusedProject)
        model.toggleNoteOverview()
        #expect(!model.noteOverviewActive)

        // Everything works again once the selector closes.
        model.cancelLayoutSelection()
        #expect(model.gotoProjectIndexTarget(2) == ids[1])
        #expect(model.canSortVisibleProjects)
    }

    @Test func restoreStateAndTeardownEndTheSession() {
        let (model, _) = Self.makeModel(3)
        let snapshot = model.state
        model.beginLayoutSelection()
        model.restoreState(snapshot)
        #expect(!model.layoutSelectionActive)

        let (torndown, _) = Self.makeModel(3)
        torndown.beginLayoutSelection()
        torndown.removeAllProjects()
        #expect(!torndown.layoutSelectionActive)
    }
}
