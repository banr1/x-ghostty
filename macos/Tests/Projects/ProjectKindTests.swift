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

/// Tests for a project's kind and the project list's kind column (must 140):
/// the Core default, persistence, the candidates in Core → Side order, Delete,
/// copy and paste, and that the kind is not a sort key.
struct ProjectKindTests {
    private static let terminals = ProjectTerminalRegistry(
        registrations: ["mini,mac-mini,colour33"], hostname: "mac-mini")

    private static func makeProject(
        name: String,
        kind: ProjectKind = .core,
        at date: Date = Date(timeIntervalSince1970: 0)
    ) -> TestProjectState {
        TestProjectState(
            id: ProjectID(),
            name: name,
            paneTree: .init(view: TestPane()),
            kind: kind,
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

    // MARK: The project's kind

    @Test func aProjectIsCoreByDefault() throws {
        let project = TestProjectState(
            id: ProjectID(),
            name: "alpha",
            paneTree: .init(view: TestPane()),
            createdAt: Date(timeIntervalSince1970: 0))
        #expect(project.kind == .core)
        #expect(try Self.row(of: project.id, in: Self.makeState([project])).kind == .core)
    }

    @Test func theKindPersistsAndRestores() throws {
        #expect(try Self.roundTrip(Self.makeProject(name: "alpha", kind: .side)).kind == .side)

        // The Core default writes no key at all and restores as Core.
        let core = Self.makeProject(name: "beta")
        let json = try #require(String(data: try JSONEncoder().encode(core), encoding: .utf8))
        #expect(!json.contains("\"kind\""))
        #expect(try Self.roundTrip(core).kind == .core)
    }

    @Test func aSaveWithoutAKnownKindRestoresAsCore() throws {
        let project = Self.makeProject(name: "alpha", kind: .side)
        var object = try #require(
            JSONSerialization.jsonObject(with: try JSONEncoder().encode(project)) as? [String: Any])
        #expect(object["kind"] as? String == "side")

        object.removeValue(forKey: "kind")
        let missing = try JSONSerialization.data(withJSONObject: object)
        #expect(try JSONDecoder().decode(TestProjectState.self, from: missing).kind == .core)

        object["kind"] = "huge"
        let unknown = try JSONSerialization.data(withJSONObject: object)
        #expect(try JSONDecoder().decode(TestProjectState.self, from: unknown).kind == .core)
    }

    // MARK: The kind column (C107)

    @Test func theKindColumnIsASelectionColumnRightAfterTheVisibility() {
        let column = ProjectListColumn.kind
        #expect(column.isSelectionColumn)
        #expect(!column.isTextColumn)
        #expect(!column.isMultilineEdit)
        #expect(column.enterAction == .enumerateCandidates)
        #expect(column.deleteAction == .clearValue)
        #expect(ProjectListColumn.defaultOrder == [
            .visibility, .kind, .title, .terminal, .note,
        ])
        let row = ProjectListRow(
            id: ProjectID(), title: "alpha", ordinal: 1, isHidden: false, note: "")
        #expect(row.editableText(for: .kind) == nil)
        #expect(ProjectListCellEdit(row: row, column: .kind) == nil)
    }

    @Test func theCandidatesAreCoreThenSide() throws {
        let project = Self.makeProject(name: "alpha", kind: .side)
        let row = try Self.row(of: project.id, in: Self.makeState([project]))
        let menu = try #require(ProjectListCandidateMenu.opened(
            on: row, column: .kind, terminals: Self.terminals))

        #expect(menu.items == [.kind(.core), .kind(.side)])
        #expect(menu.items.map(\.displayText) == ["Core", "Side"])
    }

    @Test func choosingACandidateSetsTheKind() {
        let a = Self.makeProject(name: "alpha")
        let model = Self.makeListModel([a])

        #expect(model.commitProjectListCandidate(.kind(.side), for: a.id))
        #expect(model.state.projects[a.id]?.kind == .side)
        #expect(model.commitProjectListCandidate(.kind(.core), for: a.id))
        #expect(model.state.projects[a.id]?.kind == .core)
    }

    @Test func deleteReturnsTheKindToCore() {
        let a = Self.makeProject(name: "alpha", kind: .side)
        var state = Self.makeState([a])
        let deleted = state.deleteListCellValue(.kind, for: a.id)
        #expect(deleted)
        #expect(state.projects[a.id]?.kind == .core)
    }

    @Test func setProjectKindReportsOnlyARealChange() {
        let a = Self.makeProject(name: "alpha")
        var state = Self.makeState([a])
        let first = state.setProjectKind(a.id, to: .side)
        let repeated = state.setProjectKind(a.id, to: .side)
        let reset = state.setProjectKind(a.id, to: .core)
        let unknown = state.setProjectKind(ProjectID(), to: .side)
        #expect(first)
        #expect(!repeated)
        #expect(reset)
        #expect(!unknown)
    }

    @Test func aKindChangeLeavesTheRowOrderAlone() {
        // The rows are always in the manual order: a kind change re-derives
        // the arrangement but never moves a row.
        let a = Self.makeProject(name: "alpha")
        let b = Self.makeProject(name: "beta", at: Date(timeIntervalSince1970: 1))
        let model = Self.makeListModel([a, b])
        let order = model.state.projectOrder

        #expect(model.commitProjectListCandidate(.kind(.side), for: b.id))
        #expect(model.state.projectOrder == order)
        #expect(model.deleteProjectListCellValue(.kind, for: b.id))
        #expect(model.state.projectOrder == order)
    }

    @Test func copyLiftsTheShownKind() throws {
        let a = Self.makeProject(name: "alpha", kind: .side)
        let b = Self.makeProject(name: "beta", at: Date(timeIntervalSince1970: 1))
        let state = Self.makeState([a, b])
        #expect(ProjectListClipboard.copyText(
            of: try Self.row(of: a.id, in: state), column: .kind, terminals: Self.terminals)
            == "Side")
        #expect(ProjectListClipboard.copyText(
            of: try Self.row(of: b.id, in: state), column: .kind, terminals: Self.terminals)
            == "Core")
    }

    @Test func pasteAcceptsOnlyCoreAndSide() {
        #expect(ProjectListClipboard.pasteApplication(
            of: "Core", column: .kind, terminals: Self.terminals) == .setKind(.core))
        #expect(ProjectListClipboard.pasteApplication(
            of: " Side\n", column: .kind, terminals: Self.terminals) == .setKind(.side))
        for text in ["core", "side", "SIDE", "main", "high", ""] {
            #expect(ProjectListClipboard.pasteApplication(
                of: text, column: .kind, terminals: Self.terminals) == .ignore)
        }
    }
}
