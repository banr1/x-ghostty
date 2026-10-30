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

/// Tests for a project's terminal and the project list's terminal column
/// (must 128): the local default, persistence, an unregistered name resolving
/// to local while being kept, and the column's candidates, Delete, copy and
/// paste.
struct ProjectTerminalColumnTests {
    private static let terminals = ProjectTerminalRegistry(
        registrations: ["mini,mac-mini,colour33", "loop,mini-loopback,colour166"],
        hostname: "mac-mini")

    private static let today = ProjectDeadline(parsing: "2026-10-30")!

    private static func makeProject(
        name: String,
        terminalName: String? = nil,
        priority: ProjectPriority? = nil,
        at date: Date = Date(timeIntervalSince1970: 0)
    ) -> TestProjectState {
        TestProjectState(
            id: ProjectID(),
            name: name,
            paneTree: .init(view: TestPane()),
            priority: priority,
            terminalName: terminalName,
            createdAt: date)
    }

    private static func makeState(_ projects: [TestProjectState]) -> TestWorkspaceState {
        var state = TestWorkspaceState(
            projects: Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) }),
            projectOrder: projects.map(\.id),
            focusedProject: projects.first?.id)
        state.relayout()
        return state
    }

    private static func makeListModel(_ projects: [TestProjectState]) -> TestWorkspaceModel {
        let model = TestWorkspaceModel(makeState(projects))
        model.terminalRegistry = terminals
        model.beginProjectList()
        return model
    }

    private static func roundTrip(_ project: TestProjectState) throws -> TestProjectState {
        let data = try JSONEncoder().encode(project)
        return try JSONDecoder().decode(TestProjectState.self, from: data)
    }

    private static func row(of id: ProjectID, in state: TestWorkspaceState) throws -> ProjectListRow {
        try #require(state.projectListRows.first { $0.id == id })
    }

    // MARK: The project's terminal (must 128)

    @Test func aProjectRunsOnTheLocalTerminalByDefault() throws {
        let project = Self.makeProject(name: "alpha")
        #expect(project.terminalName == nil)

        let state = Self.makeState([project])
        let row = try Self.row(of: project.id, in: state)
        #expect(row.terminalName == nil)
        #expect(row.terminalDisplayName(in: Self.terminals) == "mini")
        #expect(Self.terminals.isLocal(Self.terminals.terminal(named: row.terminalName)))
    }

    @Test func theTerminalPersistsAndRestores() throws {
        let project = Self.makeProject(name: "alpha", terminalName: "loop")
        #expect(try Self.roundTrip(project).terminalName == "loop")

        // The local default writes no key at all and restores as local.
        let local = Self.makeProject(name: "beta")
        let json = try #require(String(data: try JSONEncoder().encode(local), encoding: .utf8))
        #expect(!json.contains("\"terminal\""))
        #expect(try Self.roundTrip(local).terminalName == nil)
    }

    @Test func aSaveWrittenBeforeTerminalsExistedRestoresAsLocal() throws {
        let project = Self.makeProject(name: "alpha", terminalName: "loop")
        var object = try #require(
            JSONSerialization.jsonObject(with: try JSONEncoder().encode(project)) as? [String: Any])
        #expect(object["terminal"] as? String == "loop")
        object.removeValue(forKey: "terminal")
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(try JSONDecoder().decode(TestProjectState.self, from: data).terminalName == nil)
    }

    @Test func anUnregisteredTerminalReadsAsLocalButIsKept() throws {
        let project = Self.makeProject(name: "alpha", terminalName: "gone")
        let state = Self.makeState([project])
        let row = try Self.row(of: project.id, in: state)

        // Resolved and shown as the local terminal...
        #expect(row.terminalDisplayName(in: Self.terminals) == "mini")
        #expect(Self.terminals.terminal(named: row.terminalName) == Self.terminals.local)
        // ...while the stored name survives a save, so re-registering the
        // terminal brings the project back to it.
        #expect(try Self.roundTrip(project).terminalName == "gone")
        let reregistered = ProjectTerminalRegistry(
            registrations: ["mini,mac-mini", "gone,gone-host,red"], hostname: "mac-mini")
        #expect(row.terminalDisplayName(in: reregistered) == "gone")
    }

    // MARK: The terminal column (must 128, C107)

    @Test func theTerminalColumnIsASelectionColumnAfterTheTitle() {
        let column = ProjectListColumn.terminal
        #expect(column.isSelectionColumn)
        #expect(!column.isTextColumn)
        #expect(column.enterAction == .enumerateCandidates)
        #expect(column.deleteAction == .clearValue)
        #expect(ProjectListColumn.defaultOrder == [
            .visibility, .title, .terminal, .priority, .deadline, .nextTrigger, .note,
        ])
        let row = ProjectListRow(
            id: ProjectID(), title: "alpha", ordinal: 1, isHidden: false,
            priority: nil, deadline: nil, nextTrigger: nil, note: "")
        #expect(row.editableText(for: .terminal) == nil)
        #expect(ProjectListCellEdit(row: row, column: .terminal) == nil)
    }

    @Test func theCandidatesAreTheRegisteredTerminalNamesOnly() throws {
        let project = Self.makeProject(name: "alpha")
        let row = try Self.row(of: project.id, in: Self.makeState([project]))
        let menu = try #require(ProjectListCandidateMenu.opened(
            on: row, column: .terminal, today: Self.today, terminals: Self.terminals))

        #expect(menu.items.map(\.displayText) == ["mini", "loop"])
        #expect(menu.items == Self.terminals.terminals.map { .terminal($0) })
    }

    @Test func theCandidatesOfAnUnregisteredMachineIncludeTheImplicitLocalTerminal() throws {
        let terminals = ProjectTerminalRegistry(
            registrations: ["loop,mini-loopback"], hostname: "banri-air.local")
        let project = Self.makeProject(name: "alpha")
        let row = try Self.row(of: project.id, in: Self.makeState([project]))
        let menu = try #require(ProjectListCandidateMenu.opened(
            on: row, column: .terminal, today: Self.today, terminals: terminals))
        #expect(menu.items.map(\.displayText) == ["loop", "banri-air"])
    }

    @Test func choosingACandidateStoresTheNameAndChoosingLocalStoresTheDefault() throws {
        let a = Self.makeProject(name: "alpha")
        let model = Self.makeListModel([a])
        let loop = try #require(Self.terminals.registeredTerminal(named: "loop"))

        #expect(model.commitProjectListCandidate(.terminal(loop), for: a.id))
        #expect(model.state.projects[a.id]?.terminalName == "loop")

        #expect(model.commitProjectListCandidate(.terminal(Self.terminals.local), for: a.id))
        #expect(model.state.projects[a.id]?.terminalName == nil)
    }

    @Test func theTerminalIsNotASortKey() throws {
        let a = Self.makeProject(name: "alpha", priority: .low)
        let b = Self.makeProject(name: "beta", priority: .high, at: Date(timeIntervalSince1970: 1))
        let model = Self.makeListModel([a, b])
        model.setProjectSortState(.priority)
        let order = model.state.projectOrder
        let loop = try #require(Self.terminals.registeredTerminal(named: "loop"))

        #expect(model.commitProjectListCandidate(.terminal(loop), for: a.id))
        #expect(model.state.projectOrder == order)
        #expect(model.deleteProjectListCellValue(.terminal, for: a.id))
        #expect(model.state.projectOrder == order)
    }

    @Test func deleteReturnsTheTerminalToLocal() {
        let a = Self.makeProject(name: "alpha", terminalName: "loop")
        var state = Self.makeState([a])
        let deleted = state.deleteListCellValue(.terminal, for: a.id)
        #expect(deleted)
        #expect(state.projects[a.id]?.terminalName == nil)
    }

    @Test func setProjectTerminalReportsOnlyARealChange() {
        let a = Self.makeProject(name: "alpha")
        var state = Self.makeState([a])
        let first = state.setProjectTerminal(a.id, to: "loop")
        let repeated = state.setProjectTerminal(a.id, to: "loop")
        let reset = state.setProjectTerminal(a.id, to: nil)
        let unknown = state.setProjectTerminal(ProjectID(), to: "loop")
        #expect(first)
        #expect(!repeated)
        #expect(reset)
        #expect(!unknown)
    }

    @Test func copyLiftsTheShownTerminalName() throws {
        let a = Self.makeProject(name: "alpha", terminalName: "loop")
        let b = Self.makeProject(name: "beta", at: Date(timeIntervalSince1970: 1))
        let state = Self.makeState([a, b])
        #expect(ProjectListClipboard.copyText(
            of: try Self.row(of: a.id, in: state), column: .terminal, terminals: Self.terminals)
            == "loop")
        #expect(ProjectListClipboard.copyText(
            of: try Self.row(of: b.id, in: state), column: .terminal, terminals: Self.terminals)
            == "mini")
    }

    @Test func pasteAcceptsOnlyARegisteredTerminalName() throws {
        let loop = try #require(Self.terminals.registeredTerminal(named: "loop"))
        #expect(ProjectListClipboard.pasteApplication(
            of: "loop", column: .terminal, terminals: Self.terminals) == .setTerminal(loop))
        #expect(ProjectListClipboard.pasteApplication(
            of: " loop\n", column: .terminal, terminals: Self.terminals) == .setTerminal(loop))
        #expect(ProjectListClipboard.pasteApplication(
            of: "mini", column: .terminal, terminals: Self.terminals)
            == .setTerminal(Self.terminals.local))
        for text in ["elsewhere", "Loop", "mac-mini", ""] {
            #expect(ProjectListClipboard.pasteApplication(
                of: text, column: .terminal, terminals: Self.terminals) == .ignore)
        }
    }

    @Test func storedNameIsNilForTheLocalTerminalOnly() throws {
        #expect(Self.terminals.storedName(for: Self.terminals.local) == nil)
        let loop = try #require(Self.terminals.registeredTerminal(named: "loop"))
        #expect(Self.terminals.storedName(for: loop) == "loop")
        #expect(Self.terminals.registeredTerminal(named: "gone") == nil)
    }
}
