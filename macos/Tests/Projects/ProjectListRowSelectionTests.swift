import Foundation
import Testing
@testable import XGhostty

/// A value-type pane element standing in for `XGhostty.SurfaceView`, which
/// cannot be constructed without a live XGhostty app. The generic model layer
/// runs the exact same code for both element types, so these tests exercise
/// the real Delete and row-selection judgment logic (SPEC §27.2).
private struct TestPane: Codable, Identifiable, Equatable {
    let id: UUID
    init(id: UUID = UUID()) { self.id = id }
}

private typealias TestProjectState = ProjectStateOf<TestPane>
private typealias TestWorkspaceState = WorkspaceStateOf<TestPane>
private typealias TestWorkspaceModel = WorkspaceModelOf<TestPane>

/// Tests for the list's Delete and row selection (SPEC §27.2): the
/// per-column Delete judgment (title empties, the value columns unset, the
/// note asks first, visibility does nothing), the keyboard-mode transitions
/// (Escape into row selection, Enter back, Escape release), and the
/// row-selection Delete being a close-equivalent deletion that reaches
/// hidden rows too.
struct ProjectListRowSelectionTests {
    private static func makeProject(
        name: String,
        note: String = "",
        priority: ProjectPriority? = nil,
        deadline: ProjectDeadline? = nil,
        nextTrigger: ProjectNextTrigger? = nil,
        at date: Date = Date(timeIntervalSince1970: 0)
    ) -> TestProjectState {
        TestProjectState(
            id: ProjectID(),
            name: name,
            paneTree: .init(view: TestPane()),
            note: note,
            priority: priority,
            deadline: deadline,
            nextTrigger: nextTrigger,
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

    private static func makeListModel(_ state: TestWorkspaceState) -> TestWorkspaceModel {
        let model = TestWorkspaceModel(state)
        model.beginProjectList()
        return model
    }

    // MARK: Per-column Delete judgment (SPEC §27.2)

    @Test func deleteActionIsTheColumnsJudgment() {
        // Title and the value columns clear immediately; the note — many
        // lines of handwriting — asks first; visibility has no value.
        #expect(ProjectListColumn.title.deleteAction == .clearValue)
        #expect(ProjectListColumn.priority.deleteAction == .clearValue)
        #expect(ProjectListColumn.deadline.deleteAction == .clearValue)
        #expect(ProjectListColumn.nextTrigger.deleteAction == .clearValue)
        #expect(ProjectListColumn.note.deleteAction == .confirmClearNote)
        #expect(ProjectListColumn.visibility.deleteAction == .none)
    }

    @Test func deleteClearsEachColumnsValuePerDefinition() {
        let project = Self.makeProject(
            name: "alpha",
            note: "line 1\nline 2\nline 3",
            priority: .high,
            deadline: ProjectDeadline(parsing: "2026-08-19"),
            nextTrigger: .event)
        let other = Self.makeProject(name: "beta", at: Date(timeIntervalSince1970: 1))
        let model = Self.makeListModel(Self.makeState([project, other]))

        // Title empties — deliberately past the rename rule's empty-reject.
        #expect(model.deleteProjectListCellValue(.title, for: project.id))
        #expect(model.state.projects[project.id]?.name == "")

        // The value columns unset.
        #expect(model.deleteProjectListCellValue(.priority, for: project.id))
        #expect(model.projectPriority(of: project.id) == nil)
        #expect(model.deleteProjectListCellValue(.deadline, for: project.id))
        #expect(model.projectDeadline(of: project.id) == nil)
        #expect(model.deleteProjectListCellValue(.nextTrigger, for: project.id))
        #expect(model.projectNextTrigger(of: project.id) == nil)

        // An approved note deletion loses every line.
        #expect(model.deleteProjectListCellValue(.note, for: project.id))
        #expect(model.state.projects[project.id]?.note == "")

        // The visibility column is untouched — Delete refuses, the row
        // stays visible.
        #expect(!model.deleteProjectListCellValue(.visibility, for: project.id))
        #expect(!model.state.isProjectHidden(project.id))
    }

    @Test func deletingASortKeyValueResortsWhileASortIsActive() {
        let high = Self.makeProject(name: "high", priority: .high)
        let medium = Self.makeProject(
            name: "medium", priority: .medium, at: Date(timeIntervalSince1970: 1))
        let model = Self.makeListModel(Self.makeState([high, medium]))
        model.setProjectSortState(.priority)
        #expect(model.state.projectOrder == [high.id, medium.id])

        // Deleting the top row's priority makes it unset, which sorts last
        // (SPEC §24.3) — the change re-sorts immediately (§24.4).
        #expect(model.deleteProjectListCellValue(.priority, for: high.id))
        #expect(model.state.projectOrder == [medium.id, high.id])
    }

    @Test func deleteRequiresTheListSession() {
        let project = Self.makeProject(name: "alpha", priority: .high)
        let model = TestWorkspaceModel(Self.makeState([project]))

        #expect(!model.deleteProjectListCellValue(.priority, for: project.id))
        #expect(model.projectPriority(of: project.id) == .high)
    }

    // MARK: Row-selection transitions (SPEC §27.2)

    @Test func escapeEntersRowSelectionAndReleasesBackAndEnterReturns() {
        // Esc from the cell cursor enters row selection; Esc releases it;
        // Enter returns to the cells likewise.
        #expect(ProjectListKeyboardMode.cellCursor.escaped == .rowSelection)
        #expect(ProjectListKeyboardMode.rowSelection.escaped == .cellCursor)
        #expect(ProjectListKeyboardMode.rowSelection.entered == .cellCursor)
    }

    // MARK: Row-selection Delete is a close-equivalent deletion (SPEC §27.2)

    @Test func closingAnUnfocusedRowRemovesItKeepingFocus() {
        let a = Self.makeProject(name: "alpha")
        let b = Self.makeProject(name: "beta", note: "kept", at: Date(timeIntervalSince1970: 1))
        let model = Self.makeListModel(Self.makeState([a, b]))

        // The unfocused row leaves the ledger with all its information;
        // focus stays on the focused project.
        #expect(model.closeProject(b.id)
            == .switched(target: a.id, focus: model.state.projects[a.id]?.focusedSurface))
        #expect(model.state.projects[b.id] == nil)
        #expect(model.state.projectOrder == [a.id])
        #expect(model.state.focusedProject == a.id)
    }

    @Test func closingAHiddenRowWorksToo() {
        let a = Self.makeProject(name: "alpha")
        let b = Self.makeProject(name: "beta", at: Date(timeIntervalSince1970: 1))
        let c = Self.makeProject(name: "gamma", at: Date(timeIntervalSince1970: 2))
        var state = Self.makeState([a, b, c])
        state.setProjectHidden(c.id, true)
        let model = Self.makeListModel(state)

        #expect(model.closeProject(c.id)
            == .switched(target: a.id, focus: model.state.projects[a.id]?.focusedSurface))
        #expect(model.state.projects[c.id] == nil)
        #expect(!model.state.hiddenProjectIDs.contains(c.id))
        #expect(model.state.projectOrder == [a.id, b.id])
    }

    @Test func closingTheFocusedRowDelegatesToTheFocusedClose() {
        let a = Self.makeProject(name: "alpha")
        let b = Self.makeProject(name: "beta", at: Date(timeIntervalSince1970: 1))
        let model = Self.makeListModel(Self.makeState([a, b]))

        // Same outcome as close_project on the focused project: focus
        // switches to the nearest remaining row.
        #expect(model.closeProject(a.id)
            == .switched(target: b.id, focus: model.state.projects[b.id]?.focusedSurface))
        #expect(model.state.projects[a.id] == nil)
        #expect(model.state.focusedProject == b.id)
    }

    @Test func closingTheLastRowDelegatesToTheWindowClose() {
        let only = Self.makeProject(name: "only")
        let model = Self.makeListModel(Self.makeState([only]))

        // §18.5: the model is left unchanged; the caller closes the window.
        #expect(model.closeProject(only.id) == .closedLast)
        #expect(model.state.projects[only.id] != nil)

        // An unknown row is a no-op.
        #expect(model.closeProject(ProjectID()) == nil)
    }
}
