import Foundation
import Testing
@testable import XGhostty

/// A value-type pane element standing in for `XGhostty.SurfaceView`, which
/// cannot be constructed without a live XGhostty app. The generic model layer
/// runs the exact same code for both element types, so these tests exercise
/// the real candidate-menu judgment logic (SPEC §27.6) with real leaves.
private struct TestPane: Codable, Identifiable, Equatable {
    let id: UUID
    init(id: UUID = UUID()) { self.id = id }
}

private typealias TestProjectState = ProjectStateOf<TestPane>
private typealias TestWorkspaceState = WorkspaceStateOf<TestPane>
private typealias TestWorkspaceModel = WorkspaceModelOf<TestPane>

/// Tests for the value-candidate menus (SPEC §27.6): only the kind and
/// terminal columns enumerate candidates, the menu's selection movement,
/// and a selection committing through the model.
struct ProjectListCandidateTests {
    private static func makeProject(name: String) -> TestProjectState {
        TestProjectState(
            id: ProjectID(),
            name: name,
            paneTree: .init(view: TestPane()),
            note: "",
            createdAt: Date(timeIntervalSince1970: 0))
    }

    private static func makeListModel(_ projects: [TestProjectState]) -> TestWorkspaceModel {
        var state = TestWorkspaceState(
            projects: Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) }),
            projectOrder: projects.map(\.id),
            focusedProject: projects.first?.id)
        state.relayout()
        let model = TestWorkspaceModel(state)
        model.beginProjectList()
        return model
    }

    private static func makeRow(_ project: TestProjectState) -> ProjectListRow {
        ProjectListRow(
            id: project.id,
            title: project.name,
            ordinal: 1,
            isHidden: false,
            note: project.note)
    }

    private static let terminals = ProjectTerminalRegistry(
        registrations: ["mini,mac-mini,colour33", "loop,mini-loopback,colour166"],
        hostname: "mac-mini")

    // MARK: Menu content (SPEC §27.6)

    @Test func menusOpenOnlyOnTheKindAndTerminalColumns() {
        let row = Self.makeRow(Self.makeProject(name: "alpha"))
        for column: ProjectListColumn in [.visibility, .title, .note] {
            #expect(ProjectListCandidateMenu.opened(
                on: row, column: column, terminals: Self.terminals) == nil)
        }
        for column: ProjectListColumn in [.kind, .terminal] {
            #expect(ProjectListCandidateMenu.opened(
                on: row, column: column, terminals: Self.terminals) != nil)
        }
        // Only those two columns enumerate candidates at all.
        #expect(ProjectListColumn.allCases.filter { $0.enterAction == .enumerateCandidates }
            == [.kind, .terminal])
    }

    // MARK: Selection movement (SPEC §27.6)

    @Test func selectionMovesWithUpDownAndClampsAtTheEnds() throws {
        let row = Self.makeRow(Self.makeProject(name: "alpha"))
        var menu = try #require(ProjectListCandidateMenu.opened(
            on: row, column: .terminal, terminals: Self.terminals))
        #expect(menu.selection == 0)

        // Up on the first entry is absorbed.
        #expect(menu.moved(by: -1).selection == 0)

        let loop = try #require(Self.terminals.registeredTerminal(named: "loop"))
        menu = menu.moved(by: 1)
        #expect(menu.selectedValue == .terminal(loop))

        // Down on the last entry is absorbed.
        #expect(menu.moved(by: 1).selection == menu.selection)
    }

    // MARK: Selection commits (SPEC §27.6)

    @Test func committingASelectionSetsTheValueThroughTheModel() throws {
        let project = Self.makeProject(name: "alpha")
        let model = Self.makeListModel([project])

        #expect(model.commitProjectListCandidate(.kind(.side), for: project.id))
        #expect(model.state.projects[project.id]?.kind == .side)

        let loop = try #require(Self.terminals.registeredTerminal(named: "loop"))
        #expect(model.commitProjectListCandidate(.terminal(loop), for: project.id))
        #expect(model.state.projects[project.id]?.terminalName == "loop")
    }

    @Test func commitRequiresTheListSession() {
        let project = Self.makeProject(name: "alpha")
        let model = Self.makeListModel([project])

        // Without the list session up, the commit is refused untouched.
        model.endProjectList()
        #expect(!model.commitProjectListCandidate(.kind(.side), for: project.id))
        #expect(model.state.projects[project.id]?.kind == .core)
    }
}
