import Foundation
import Testing
@testable import XGhostty

/// A value-type pane element standing in for `XGhostty.SurfaceView`, which
/// cannot be constructed without a live XGhostty app. The generic model layer
/// runs the exact same code for both element types.
private struct TestPane: Codable, Identifiable, Equatable {
    let id: UUID
    init(id: UUID = UUID()) { self.id = id }
}

private typealias TestProjectState = ProjectStateOf<TestPane>
private typealias TestWorkspaceState = WorkspaceStateOf<TestPane>
private typealias TestWorkspaceModel = WorkspaceModelOf<TestPane>

/// Tests for the visible cap and the ordinals past it (must 141 and 68): at most
/// 24 projects are visible whatever their kind, the list's visibility toggle is
/// rejected at the cap, a new row comes in hidden there, and only the first nine
/// projects in placement order have a number.
struct ProjectVisibleCapTests {
    private static func makeProject(
        name: String,
        kind: ProjectKind = .core
    ) -> TestProjectState {
        TestProjectState(
            id: ProjectID(),
            name: name,
            paneTree: .init(view: TestPane()),
            kind: kind,
            createdAt: Date(timeIntervalSince1970: 0))
    }

    private static func makeProjects(
        _ count: Int,
        kind: (Int) -> ProjectKind = { _ in .core }
    ) -> [TestProjectState] {
        (0..<count).map { makeProject(name: "p\($0)", kind: kind($0)) }
    }

    private static func makeState(
        _ projects: [TestProjectState],
        hidden: Set<ProjectID> = []
    ) -> TestWorkspaceState {
        var state = TestWorkspaceState(
            projects: Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) }),
            projectOrder: projects.map(\.id),
            hiddenProjectIDs: hidden,
            focusedProject: projects.first?.id)
        state.relayout()
        return state
    }

    private static func makeListModel(
        _ projects: [TestProjectState],
        hidden: Set<ProjectID> = []
    ) -> TestWorkspaceModel {
        let model = TestWorkspaceModel(makeState(projects, hidden: hidden))
        model.beginProjectList()
        return model
    }

    @Test func theVisibleCapIsTwentyFour() {
        #expect(TestWorkspaceState.maxVisibleProjects == 24)
    }

    @Test func aSideCountsAsOneTowardTheCap() {
        let projects = Self.makeProjects(25) { _ in .side }
        let state = Self.makeState(projects)

        #expect(state.visibleProjectCount == 24)
        #expect(state.isProjectHidden(projects[24].id))
    }

    // MARK: The list's visibility toggle

    @Test func theToggleShowsAHiddenRowBelowTheCap() {
        let projects = Self.makeProjects(24)
        let model = Self.makeListModel(projects, hidden: [projects[23].id])

        #expect(model.canToggleProjectListVisibility(projects[23].id))
        model.toggleProjectListVisibility(projects[23].id, savingOutgoingPaneTree: .init())
        #expect(model.state.isProjectHidden(projects[23].id) == false)
        #expect(model.state.visibleProjectCount == 24)
    }

    @Test func theToggleIsRejectedWithTwentyFourVisible() {
        let projects = Self.makeProjects(25)
        let model = Self.makeListModel(projects, hidden: [projects[24].id])
        #expect(model.state.visibleProjectCount == 24)
        let tree = model.state.canonicalProjectTree.map(\.id)

        #expect(model.canToggleProjectListVisibility(projects[24].id) == false)
        model.toggleProjectListVisibility(projects[24].id, savingOutgoingPaneTree: .init())

        #expect(model.state.hiddenProjectIDs == [projects[24].id])
        #expect(model.state.canonicalProjectTree.map(\.id) == tree)

        // Hiding stays possible at the cap: the rejection is only for showing.
        #expect(model.canToggleProjectListVisibility(projects[0].id))
    }

    // MARK: New rows

    @Test func aNewRowIsVisibleCoreWhileBelowTheCap() {
        let projects = Self.makeProjects(23)
        let model = Self.makeListModel(projects)
        let new = Self.makeProject(name: "new")

        #expect(model.insertProjectFromList(new, after: projects.last?.id))

        #expect(model.state.isProjectHidden(new.id) == false)
        #expect(model.state.visibleProjectCount == 24)
        #expect(model.state.projects[new.id]?.kind == .core)
    }

    @Test func aNewRowIsHiddenCoreAtTheCap() {
        let projects = Self.makeProjects(24)
        let model = Self.makeListModel(projects)
        let tree = model.state.canonicalProjectTree.map(\.id)
        let new = Self.makeProject(name: "new")

        #expect(model.insertProjectFromList(new, after: projects.last?.id))

        #expect(model.state.isProjectHidden(new.id))
        #expect(model.state.visibleProjectCount == 24)
        #expect(model.state.projects[new.id]?.kind == .core)
        #expect(model.state.canonicalProjectTree.map(\.id) == tree)
    }

    // MARK: Ordinals

    @Test func everyVisibleProjectInPlacementOrderHasANumber() {
        // Every other row is a Side, so the placement order differs from the
        // row order: the numbers follow the placement, through the 24th.
        let projects = Self.makeProjects(24) { $0.isMultiple(of: 2) ? .side : .core }
        let state = Self.makeState(projects)
        let placement = state.visibleProjectIDs
        #expect(placement.count == 24)
        #expect(placement.prefix(12).allSatisfy { state.projects[$0]?.kind == .core })

        #expect(placement.map { state.ordinal(of: $0) } == (1...24).map(Optional.some))
        #expect((1...24).map { state.visibleProjectID(ordinal: $0) } == placement.map(Optional.some))
        #expect(state.visibleProjectID(ordinal: 25) == nil)
        #expect(state.visibleProjectID(ordinal: 0) == nil)
        #expect(state.projectOrdinals == Dictionary(
            uniqueKeysWithValues: placement.enumerated().map { ($0.element, $0.offset + 1) }))
    }

    @Test func aHiddenRowFreesItsNumberForTheNextProject() {
        let projects = Self.makeProjects(12)
        let state = Self.makeState(projects, hidden: [projects[0].id])

        #expect(state.ordinal(of: projects[0].id) == nil)
        #expect(state.ordinal(of: projects[1].id) == 1)
        #expect(state.ordinal(of: projects[9].id) == 9)
        #expect(state.ordinal(of: projects[10].id) == 10)
        #expect(state.ordinal(of: projects[11].id) == 11)
        #expect(state.projectOrdinals.count == 11)
    }

    @Test func onlyAHiddenRowGoesWithoutANumber() {
        let projects = Self.makeProjects(12)
        let state = Self.makeState(projects, hidden: [projects[10].id])

        let rows = state.projectListRows
        #expect(rows[8].ordinal == 9)
        #expect(rows[8].isHidden == false)
        #expect(rows[8].ordinalGutterText == "9")

        // Past the ninth the visible rows keep counting.
        #expect(rows[9].ordinal == 10)
        #expect(rows[9].isHidden == false)
        #expect(rows[9].ordinalGutterText == "10")

        #expect(rows[10].ordinal == nil)
        #expect(rows[10].isHidden == true)
        #expect(rows[10].ordinalGutterText == "·")

        #expect(rows[11].ordinal == 11)
        #expect(rows[11].ordinalGutterText == "11")
    }

    @Test func theListFocusReachesPastTheNinth() {
        let projects = Self.makeProjects(12)
        let model = TestWorkspaceModel(Self.makeState(projects))

        // A row past the ninth is visible, so a list focus lands on it.
        #expect(model.state.resolvedListFocusTarget(for: projects[11].id) == projects[11].id)
    }
}
