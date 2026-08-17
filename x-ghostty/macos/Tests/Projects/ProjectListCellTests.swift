import Foundation
import Testing
@testable import XGhostty

/// A value-type pane element standing in for `XGhostty.SurfaceView`, which
/// cannot be constructed without a live XGhostty app. The generic model layer
/// runs the exact same code for both element types, so these tests exercise
/// the real list-cell judgment logic (SPEC §27.2) with real leaves in the trees.
private struct TestPane: Codable, Identifiable, Equatable {
    let id: UUID
    init(id: UUID = UUID()) { self.id = id }
}

private typealias TestProjectState = ProjectStateOf<TestPane>
private typealias TestWorkspaceState = WorkspaceStateOf<TestPane>
private typealias TestWorkspaceModel = WorkspaceModelOf<TestPane>

/// Tests for the project list's cell mechanics (SPEC §27.2): the cell cursor's
/// movement with its row-end wrap and last-row stop, text-cell edits (commit
/// applies, cancel reverts, the note cell rewrites only line 1, invalid
/// deadline input is unset), Space cycling on the selection columns, the
/// column moves with persistence, and the transient full-note toggle.
struct ProjectListCellTests {
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

    /// A model with the list session already up, as every cell operation
    /// requires.
    private static func makeListModel(_ projects: [TestProjectState]) -> TestWorkspaceModel {
        let model = TestWorkspaceModel(makeState(projects))
        model.beginProjectList()
        return model
    }

    // MARK: Cursor movement (SPEC §27.2)

    @Test func cursorRightWrapsAtRowEndAndStopsAtTheLastCell() {
        // Tab (and →) on a 2×3 grid.
        var cursor = ProjectListCellCursor(row: 0, column: 1)
        cursor = cursor.moved(.right, rowCount: 2, columnCount: 3)
        #expect(cursor == ProjectListCellCursor(row: 0, column: 2))

        // Row end: wrap to the next row's first cell.
        cursor = cursor.moved(.right, rowCount: 2, columnCount: 3)
        #expect(cursor == ProjectListCellCursor(row: 1, column: 0))

        // The very last cell absorbs — there is no next row to wrap into.
        let last = ProjectListCellCursor(row: 1, column: 2)
        #expect(last.moved(.right, rowCount: 2, columnCount: 3) == last)
    }

    @Test func cursorLeftWrapsBackAndStopsAtTheFirstCell() {
        // Shift+Tab (and ←) mirrors: a row's first cell wraps to the previous
        // row's last.
        let rowHead = ProjectListCellCursor(row: 1, column: 0)
        #expect(rowHead.moved(.left, rowCount: 2, columnCount: 3)
            == ProjectListCellCursor(row: 0, column: 2))

        let first = ProjectListCellCursor(row: 0, column: 0)
        #expect(first.moved(.left, rowCount: 2, columnCount: 3) == first)
    }

    @Test func cursorDownStopsAtTheLastRowAndUpAtTheFirst() {
        // Enter / Shift+Enter (and ↓/↑) keep the column and stop at the edge
        // rows.
        let middle = ProjectListCellCursor(row: 1, column: 2)
        #expect(middle.moved(.down, rowCount: 3, columnCount: 4)
            == ProjectListCellCursor(row: 2, column: 2))
        #expect(middle.moved(.up, rowCount: 3, columnCount: 4)
            == ProjectListCellCursor(row: 0, column: 2))

        let lastRow = ProjectListCellCursor(row: 2, column: 1)
        #expect(lastRow.moved(.down, rowCount: 3, columnCount: 4) == lastRow)
        let firstRow = ProjectListCellCursor(row: 0, column: 1)
        #expect(firstRow.moved(.up, rowCount: 3, columnCount: 4) == firstRow)
    }

    @Test func cursorClampsWhenTheGridShrinksUnderIt() {
        let stale = ProjectListCellCursor(row: 5, column: 9)
        #expect(stale.clamped(rowCount: 3, columnCount: 6)
            == ProjectListCellCursor(row: 2, column: 5))
        // Movement on the shrunken grid starts from the clamped position.
        #expect(stale.moved(.down, rowCount: 3, columnCount: 6)
            == ProjectListCellCursor(row: 2, column: 5))
    }

    // MARK: Row content for the cells (SPEC §27.1–27.2)

    @Test func rowsCarryTheNextTriggerAndTheFullNote() throws {
        let deadline = try #require(ProjectDeadline(year: 2026, month: 9, day: 1))
        let a = Self.makeProject(
            name: "alpha",
            note: "first\nsecond\nthird",
            priority: .high,
            deadline: deadline,
            nextTrigger: .teamMember)
        let state = Self.makeState([a])

        let row = try #require(state.projectListRows.first)
        #expect(row.nextTrigger == .teamMember)
        #expect(row.note == "first\nsecond\nthird")
        #expect(row.noteFirstLine == "first")
    }

    @Test func editableTextIsTheTextColumnsCurrentValueOnly() throws {
        let deadline = try #require(ProjectDeadline(year: 2026, month: 9, day: 1))
        let a = Self.makeProject(name: "alpha", note: "memo\nrest", deadline: deadline)
        let row = try #require(Self.makeState([a]).projectListRows.first)

        #expect(row.editableText(for: .title) == "alpha")
        #expect(row.editableText(for: .deadline) == "2026-09-01")
        #expect(row.editableText(for: .note) == "memo")
        // Selection columns are not text-editable: no edit session exists.
        #expect(row.editableText(for: .visibility) == nil)
        #expect(row.editableText(for: .priority) == nil)
        #expect(row.editableText(for: .nextTrigger) == nil)
        #expect(ProjectListCellEdit(row: row, column: .priority) == nil)
    }

    // MARK: Text-cell commit and cancel (SPEC §27.2)

    @Test func commitAppliesTheDraftAndCancelLeavesTheOriginal() throws {
        let a = Self.makeProject(name: "alpha")
        var state = Self.makeState([a])
        let row = try #require(state.projectListRows.first)

        // Cancel: the session is discarded without any mutation, so the cell
        // still shows what the edit started from.
        var abandoned = try #require(ProjectListCellEdit(row: row, column: .title))
        abandoned.draft = "typed then escaped"
        #expect(abandoned.original == "alpha")
        #expect(state.projectListRows.first?.title == "alpha")

        // Commit: the draft is applied through the model.
        var edit = try #require(ProjectListCellEdit(row: row, column: .title))
        edit.draft = "renamed"
        let committedRename = state.commitListCellEdit(edit.draft, column: edit.column, for: edit.rowID)
        #expect(committedRename)
        #expect(state.projectListRows.first?.title == "renamed")
    }

    @Test func titleCommitTrimsAndRejectsEmpty() {
        let a = Self.makeProject(name: "alpha")
        var state = Self.makeState([a])

        let committedTrimmedTitle = state.commitListCellEdit("  beta  ", column: .title, for: a.id)
        #expect(committedTrimmedTitle)
        #expect(state.projects[a.id]?.name == "beta")

        // The shared rename rule: an all-whitespace title keeps the old name.
        let committedEmptyTitle = state.commitListCellEdit("   ", column: .title, for: a.id)
        #expect(committedEmptyTitle == false)
        #expect(state.projects[a.id]?.name == "beta")
    }

    @Test func deadlineCommitParsesAndInvalidInputBecomesUnset() throws {
        let a = Self.makeProject(name: "alpha")
        var state = Self.makeState([a])

        let committedValidDeadline = state.commitListCellEdit("2026-09-01", column: .deadline, for: a.id)
        #expect(committedValidDeadline)
        #expect(state.projects[a.id]?.deadline
            == ProjectDeadline(year: 2026, month: 9, day: 1))

        // Invalid input is treated as unset (SPEC §24.1) — not kept, not
        // rejected into the previous value.
        let committedImpossibleDate = state.commitListCellEdit("2026-13-40", column: .deadline, for: a.id)
        #expect(committedImpossibleDate)
        #expect(state.projects[a.id]?.deadline == nil)

        let committedDeadlineAgain = state.commitListCellEdit("2026-09-01", column: .deadline, for: a.id)
        #expect(committedDeadlineAgain)
        let committedGarbageDate = state.commitListCellEdit("not a date", column: .deadline, for: a.id)
        #expect(committedGarbageDate)
        #expect(state.projects[a.id]?.deadline == nil)

        // Clearing the cell unsets too.
        let committedDeadlineOnceMore = state.commitListCellEdit("2026-09-01", column: .deadline, for: a.id)
        #expect(committedDeadlineOnceMore)
        let committedClearedCell = state.commitListCellEdit("", column: .deadline, for: a.id)
        #expect(committedClearedCell)
        #expect(state.projects[a.id]?.deadline == nil)
    }

    @Test func noteCommitRewritesOnlyTheFirstLine() {
        let a = Self.makeProject(name: "alpha", note: "old first\nsecond\nthird")
        var state = Self.makeState([a])

        let committedNoteFirstLine = state.commitListCellEdit("new first", column: .note, for: a.id)
        #expect(committedNoteFirstLine)
        #expect(state.projects[a.id]?.note == "new first\nsecond\nthird")

        // An empty note gains its first line.
        let b = Self.makeProject(name: "beta")
        var fresh = Self.makeState([b])
        let committedOntoEmptyNote = fresh.commitListCellEdit("only line", column: .note, for: b.id)
        #expect(committedOntoEmptyNote)
        #expect(fresh.projects[b.id]?.note == "only line")
    }

    // MARK: Selection-column cycling (SPEC §27.2)

    @Test func priorityCyclesThroughDefinitionOrderAndBackToUnset() {
        let a = Self.makeProject(name: "alpha")
        var state = Self.makeState([a])

        var seen: [ProjectPriority?] = []
        for _ in 0..<4 {
            let cycledPriority = state.cycleListCellValue(.priority, for: a.id)
            #expect(cycledPriority)
            seen.append(state.projects[a.id]?.priority)
        }
        #expect(seen == [.high, .medium, .low, nil])
    }

    @Test func nextTriggerCyclesThroughDefinitionOrderAndBackToUnset() {
        let a = Self.makeProject(name: "alpha")
        var state = Self.makeState([a])

        var seen: [ProjectNextTrigger?] = []
        for _ in 0..<5 {
            let cycledNextTrigger = state.cycleListCellValue(.nextTrigger, for: a.id)
            #expect(cycledNextTrigger)
            seen.append(state.projects[a.id]?.nextTrigger)
        }
        #expect(seen == [.myself, .teamMember, .externalPerson, .event, nil])
    }

    @Test func cyclingIsDefinedOnlyForPriorityAndNextTrigger() {
        // Visibility toggles through the session hide/show path (with the
        // at-least-one-visible rule and relayout), never through the cycle.
        let a = Self.makeProject(name: "alpha")
        var state = Self.makeState([a])

        let cycledVisibility = state.cycleListCellValue(.visibility, for: a.id)
        #expect(cycledVisibility == false)
        let cycledTitle = state.cycleListCellValue(.title, for: a.id)
        #expect(cycledTitle == false)
        let cycledUnknownProject = state.cycleListCellValue(.priority, for: ProjectID())
        #expect(cycledUnknownProject == false)
    }

    // MARK: Column moves persist (SPEC §27.1)

    @Test func columnMovesClampAtTheEndsAndRoundTrip() throws {
        let a = Self.makeProject(name: "alpha")
        var state = Self.makeState([a])

        // title left: swaps with visibility.
        let movedTitleLeft = state.moveListColumn(.title, by: -1)
        #expect(movedTitleLeft)
        #expect(state.listColumnOrder == [
            .title, .visibility, .priority, .deadline, .nextTrigger, .note,
        ])

        // The ends absorb.
        let movedTitlePastTheEnd = state.moveListColumn(.title, by: -1)
        #expect(movedTitlePastTheEnd == false)
        let movedNotePastTheEnd = state.moveListColumn(.note, by: 1)
        #expect(movedNotePastTheEnd == false)

        // A multi-place move clamps to the end instead of overshooting.
        let movedPriorityFarRight = state.moveListColumn(.priority, by: 99)
        #expect(movedPriorityFarRight)
        #expect(state.listColumnOrder.last == .priority)

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(TestWorkspaceState.self, from: data)
        #expect(decoded.listColumnOrder == state.listColumnOrder)
    }

    // MARK: Session gating and the transient full-note toggle (SPEC §27.2)

    @Test func cellOperationsRequireTheListSession() {
        let a = Self.makeProject(name: "alpha")
        let b = Self.makeProject(name: "beta", at: Date(timeIntervalSince1970: 1))
        let model = TestWorkspaceModel(Self.makeState([a, b]))

        // Closed list: everything is inert.
        #expect(model.commitProjectListCellEdit("x", column: .title, for: a.id) == false)
        #expect(model.cycleProjectListCell(.priority, for: a.id) == false)
        #expect(model.moveProjectListRow(b.id, by: -1) == false)
        #expect(model.moveProjectListColumn(.note, by: -1) == false)
        #expect(model.state.projects[a.id]?.name == "alpha")
        #expect(model.state.projectOrder == [a.id, b.id])

        model.beginProjectList()

        #expect(model.commitProjectListCellEdit("gamma", column: .title, for: a.id))
        #expect(model.state.projects[a.id]?.name == "gamma")
        #expect(model.cycleProjectListCell(.priority, for: a.id))
        #expect(model.state.projects[a.id]?.priority == .high)
        #expect(model.moveProjectListRow(b.id, by: -1))
        #expect(model.state.projectOrder == [b.id, a.id])
        // Clamped at the top now.
        #expect(model.moveProjectListRow(b.id, by: -1) == false)
        #expect(model.moveProjectListColumn(.note, by: -1))
        #expect(model.state.listColumnOrder == [
            .visibility, .title, .priority, .deadline, .note, .nextTrigger,
        ])
    }

    @Test func rowMovesFromTheListRelayoutTheArrangement() {
        let a = Self.makeProject(name: "alpha")
        let b = Self.makeProject(name: "beta", at: Date(timeIntervalSince1970: 1))
        let model = Self.makeListModel([a, b])

        #expect(model.moveProjectListRow(b.id, by: -1))
        // The arrangement is a projection of the ledger: the visible order
        // follows the row move immediately (SPEC §26.3).
        #expect(model.state.canonicalProjectTree.map(\.id) == [b.id, a.id])
        #expect(model.state.ordinal(of: b.id) == 1)
        #expect(model.state.ordinal(of: a.id) == 2)
    }

    // MARK: Creation through the list (SPEC §27.4)

    @Test func insertFromListLandsBelowTheAnchorAndMarksThePendingTitleEdit() {
        let a = Self.makeProject(name: "alpha")
        let b = Self.makeProject(name: "beta", at: Date(timeIntervalSince1970: 1))
        let model = TestWorkspaceModel(Self.makeState([a, b]))
        let created = Self.makeProject(name: "new", at: Date(timeIntervalSince1970: 2))

        // Inert while no session is up: creation is a list-only path.
        #expect(model.insertProjectFromList(created, after: a.id) == false)
        #expect(model.state.projects[created.id] == nil)
        #expect(model.projectListPendingTitleEdit == nil)

        model.beginProjectList()

        #expect(model.insertProjectFromList(created, after: a.id))
        // The row lands right below the anchor, visible under the cap, and
        // focus stays where it was — the list session remains open.
        #expect(model.state.projectOrder == [a.id, created.id, b.id])
        #expect(model.state.isProjectHidden(created.id) == false)
        #expect(model.state.focusedProject == a.id)
        #expect(model.projectListActive == true)
        // The overlay is told to open the new row's title cell, then clears
        // the handoff once seated.
        #expect(model.projectListPendingTitleEdit == created.id)
        model.clearProjectListPendingTitleEdit()
        #expect(model.projectListPendingTitleEdit == nil)

        // A duplicate id is refused.
        #expect(model.insertProjectFromList(created, after: b.id) == false)
    }

    @Test func pendingTitleEditDoesNotSurviveAcrossListSessions() {
        let a = Self.makeProject(name: "alpha")
        let model = TestWorkspaceModel(Self.makeState([a]))
        model.beginProjectList()
        let created = Self.makeProject(name: "new", at: Date(timeIntervalSince1970: 1))
        #expect(model.insertProjectFromList(created, after: a.id))
        #expect(model.projectListPendingTitleEdit == created.id)

        // An unconsumed handoff dies with the session: reopening must not
        // re-open a title edit for a row created last time.
        model.endProjectList()
        #expect(model.projectListPendingTitleEdit == nil)
        model.beginProjectList()
        #expect(model.projectListPendingTitleEdit == nil)
    }

    @Test func fullNoteToggleIsViewingOnlyAndResetsEachSession() {
        let a = Self.makeProject(name: "alpha", note: "1\n2\n3")
        let model = TestWorkspaceModel(Self.makeState([a]))

        // Inert while no session is up.
        #expect(model.toggleProjectListFullNotes() == false)
        #expect(model.projectListFullNotes == false)

        model.beginProjectList()
        #expect(model.projectListFullNotes == false)
        #expect(model.toggleProjectListFullNotes() == true)
        #expect(model.projectListFullNotes == true)
        #expect(model.toggleProjectListFullNotes() == false)
        #expect(model.toggleProjectListFullNotes() == true)

        // Transient: the next session starts back at first-lines-only, and
        // nothing about the toggle touches the persisted state.
        model.endProjectList()
        #expect(model.projectListFullNotes == false)
        model.beginProjectList()
        #expect(model.projectListFullNotes == false)
        #expect(model.state.projects[a.id]?.note == "1\n2\n3")
    }
}
