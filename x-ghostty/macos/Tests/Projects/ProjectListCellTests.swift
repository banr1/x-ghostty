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

/// Tests for the project list's cell mechanics (SPEC §27.2, Notion-style):
/// the cell cursor's movement with its row-end wrap, edge stops, and
/// Cmd+arrow edge jumps, the per-column Enter judgment (edit / toggle /
/// candidates), text-cell edits (commit applies, cancel reverts, the note
/// cell rewrites only line 1, invalid deadline input is unset), the column
/// moves with persistence, and the transient full-note toggle.
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
        // ↓/↑ keep the column and stop at the edge rows.
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

    @Test func cmdArrowEdgeJumpsReachTheEdgesKeepingTheOtherCoordinate() {
        // Cmd+arrows jump straight to the first/last row or the
        // leftmost/rightmost column (SPEC §27.2).
        let middle = ProjectListCellCursor(row: 3, column: 2)
        #expect(middle.movedToEdge(.up, rowCount: 6, columnCount: 6)
            == ProjectListCellCursor(row: 0, column: 2))
        #expect(middle.movedToEdge(.down, rowCount: 6, columnCount: 6)
            == ProjectListCellCursor(row: 5, column: 2))
        #expect(middle.movedToEdge(.left, rowCount: 6, columnCount: 6)
            == ProjectListCellCursor(row: 3, column: 0))
        #expect(middle.movedToEdge(.right, rowCount: 6, columnCount: 6)
            == ProjectListCellCursor(row: 3, column: 5))

        // Already at an edge: the jump is absorbed, nothing wraps.
        let corner = ProjectListCellCursor(row: 0, column: 0)
        #expect(corner.movedToEdge(.up, rowCount: 6, columnCount: 6) == corner)
        #expect(corner.movedToEdge(.left, rowCount: 6, columnCount: 6) == corner)

        // A stale cursor clamps onto the grid before jumping.
        let stale = ProjectListCellCursor(row: 9, column: 9)
        #expect(stale.movedToEdge(.up, rowCount: 3, columnCount: 4)
            == ProjectListCellCursor(row: 0, column: 3))
    }

    // MARK: Per-column Enter judgment (SPEC §27.2)

    @Test func enterEditsTextColumnsTogglesVisibilityAndListsCandidates() {
        // Enter operates on the cell, per column (Notion-style): the text
        // columns start a seeded edit, the visibility column toggles
        // hide/show immediately, and the value columns enumerate their
        // candidates.
        #expect(ProjectListColumn.title.enterAction == .beginEdit)
        #expect(ProjectListColumn.note.enterAction == .beginEdit)
        #expect(ProjectListColumn.visibility.enterAction == .toggleVisibility)
        #expect(ProjectListColumn.deadline.enterAction == .enumerateCandidates)
        #expect(ProjectListColumn.priority.enterAction == .enumerateCandidates)
        #expect(ProjectListColumn.nextTrigger.enterAction == .enumerateCandidates)
    }

    @Test func anEnterOpenedEditIsSeededWithTheExistingText() throws {
        // Enter starts the edit with the caret in the existing content: the
        // session's draft begins as the cell's current text (a typed edit
        // starts empty instead — the replace judgment, covered below).
        let a = Self.makeProject(name: "alpha", note: "first\nsecond")
        let row = try #require(Self.makeState([a]).projectListRows.first)

        let title = try #require(ProjectListCellEdit(row: row, column: .title))
        #expect(title.draft == "alpha" && title.original == "alpha")
        let note = try #require(ProjectListCellEdit(row: row, column: .note))
        #expect(note.draft == "first" && note.original == "first")
    }

    // MARK: Row content for the cells (SPEC §27.1–27.2)

    @Test func rowsCarryTheNextTriggerAndTheFullNote() throws {
        let deadline = try #require(ProjectDeadline(year: 2026, month: 9, day: 1))
        let a = Self.makeProject(
            name: "alpha",
            note: "first\nsecond\nthird",
            priority: .high,
            deadline: deadline,
            nextTrigger: .externalPerson)
        let state = Self.makeState([a])

        let row = try #require(state.projectListRows.first)
        #expect(row.nextTrigger == .externalPerson)
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
        #expect(model.moveProjectListRow(b.id, by: -1) == nil)
        #expect(model.moveProjectListColumn(.note, by: -1) == nil)
        #expect(model.state.projects[a.id]?.name == "alpha")
        #expect(model.state.projectOrder == [a.id, b.id])

        model.beginProjectList()

        #expect(model.commitProjectListCellEdit("gamma", column: .title, for: a.id))
        #expect(model.state.projects[a.id]?.name == "gamma")
        #expect(model.moveProjectListRow(b.id, by: -1) == 0)
        #expect(model.state.projectOrder == [b.id, a.id])
        // Clamped at the top now.
        #expect(model.moveProjectListRow(b.id, by: -1) == nil)
        #expect(model.moveProjectListColumn(.note, by: -1) == 4)
        #expect(model.state.listColumnOrder == [
            .visibility, .title, .priority, .deadline, .note, .nextTrigger,
        ])
    }

    // MARK: Deadline day arithmetic (feeds the date candidates, §27.6)

    @Test func deadlineAdvanceRollsOverMonthAndYearBoundaries() {
        #expect(ProjectDeadline(parsing: "2026-08-31")?.advanced(by: 1)
            == ProjectDeadline(parsing: "2026-09-01"))
        #expect(ProjectDeadline(parsing: "2026-12-31")?.advanced(by: 1)
            == ProjectDeadline(parsing: "2027-01-01"))
        #expect(ProjectDeadline(parsing: "2028-02-29")?.advanced(by: -1)
            == ProjectDeadline(parsing: "2028-02-28"))
    }

    // MARK: Consecutive reorders follow the moved row/column (SPEC §27.1)

    @Test func consecutiveRowMovesKeepActingOnTheSameRow() {
        let a = Self.makeProject(name: "alpha")
        let b = Self.makeProject(name: "beta", at: Date(timeIntervalSince1970: 1))
        let c = Self.makeProject(name: "gamma", at: Date(timeIntervalSince1970: 2))
        let model = Self.makeListModel([a, b, c])

        // The reported index is where the moved row now sits — the cursor
        // follows it, so pressing Cmd+↓ again moves the same row again.
        var cursor = 0
        for (expectedIndex, expectedOrder) in [
            (1, [b.id, a.id, c.id]),
            (2, [b.id, c.id, a.id]),
        ] {
            let moved = model.moveProjectListRow(
                model.state.projectOrder[cursor], by: 1)
            #expect(moved == expectedIndex)
            #expect(model.state.projectOrder == expectedOrder)
            #expect(model.state.projectOrder.firstIndex(of: a.id) == moved)
            cursor = moved ?? cursor
        }

        // The bottom end clamps: nothing moves, nothing is reported, the
        // cursor stays on the same row.
        #expect(model.moveProjectListRow(model.state.projectOrder[cursor], by: 1) == nil)
        #expect(model.state.projectOrder == [b.id, c.id, a.id])

        // And two consecutive moves back up return it to the top.
        cursor = model.moveProjectListRow(model.state.projectOrder[cursor], by: -1) ?? cursor
        #expect(cursor == 1)
        cursor = model.moveProjectListRow(model.state.projectOrder[cursor], by: -1) ?? cursor
        #expect(cursor == 0)
        #expect(model.state.projectOrder == [a.id, b.id, c.id])
    }

    @Test func consecutiveColumnMovesKeepActingOnTheSameColumn() {
        let a = Self.makeProject(name: "alpha")
        let model = Self.makeListModel([a])

        // Priority right twice: each report is the moved column's new index.
        var cursor = model.state.listColumnOrder.firstIndex(of: .priority)!
        for expectedOrder: [ProjectListColumn] in [
            [.visibility, .title, .deadline, .priority, .nextTrigger, .note],
            [.visibility, .title, .deadline, .nextTrigger, .priority, .note],
        ] {
            let moved = model.moveProjectListColumn(
                model.state.listColumnOrder[cursor], by: 1)
            #expect(moved == model.state.listColumnOrder.firstIndex(of: .priority))
            #expect(model.state.listColumnOrder == expectedOrder)
            cursor = moved ?? cursor
        }

        // One more lands on the end; the end then clamps and reports nothing.
        cursor = model.moveProjectListColumn(
            model.state.listColumnOrder[cursor], by: 1) ?? cursor
        #expect(cursor == 5)
        #expect(model.state.listColumnOrder.last == .priority)
        #expect(model.moveProjectListColumn(
            model.state.listColumnOrder[cursor], by: 1) == nil)
    }

    @Test func rowMovesFromTheListRelayoutTheArrangement() {
        let a = Self.makeProject(name: "alpha")
        let b = Self.makeProject(name: "beta", at: Date(timeIntervalSince1970: 1))
        let model = Self.makeListModel([a, b])

        #expect(model.moveProjectListRow(b.id, by: -1) == 0)
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

    // MARK: IME-capable cell editing (SPEC §27.5, must 78)

    @Test func aTypedEditStartsEmptySoTheFirstKeystrokeCanComposeThroughTheIME() {
        let a = Self.makeProject(name: "alpha", note: "first\nsecond")
        let rows = Self.makeState([a]).projectListRows
        let row = rows[0]

        // A session opened by typing carries no keystroke of its own: the
        // stroke goes to the editor's input context, not into the draft, so
        // an IME composition can begin with it instead of its raw character
        // landing in the cell.
        for column in [ProjectListColumn.title, .deadline, .note] {
            let started = ProjectListCellEdit.started(on: row, column: column)
            #expect(started?.draft == "")
        }

        // Typing still replaces rather than appends: the original is kept for
        // the cancel path only.
        #expect(ProjectListCellEdit.started(on: row, column: .title)?.original == "alpha")
        #expect(ProjectListCellEdit.started(on: row, column: .note)?.original == "first")

        // The selection columns are still not text-editable.
        for column in [ProjectListColumn.visibility, .priority, .nextTrigger] {
            #expect(ProjectListCellEdit.started(on: row, column: column) == nil)
        }
    }

    @Test func aMarkedStringKeepsEveryKeyOnTheImeInsteadOfTheSession() {
        // While the IME holds an uncommitted string, Enter commits the
        // conversion, Escape cancels it and Space converts — none of them may
        // read as the session's commit / cancel / move.
        for press in [
            ProjectListEditKeyPress.escape, .enter, .tab, .other,
        ] {
            for shifted in [false, true] {
                #expect(
                    ProjectListCellEdit.routing(
                        for: press, shifted: shifted, composing: true) == .editor)
            }
        }
    }

    @Test func withNothingMarkedTheSessionTerminatorsReadAsBefore() {
        func routing(
            _ press: ProjectListEditKeyPress, shifted: Bool = false
        ) -> ProjectListEditKeyRouting {
            ProjectListCellEdit.routing(for: press, shifted: shifted, composing: false)
        }

        #expect(routing(.escape) == .cancel)
        #expect(routing(.escape, shifted: true) == .cancel)
        // Enter commits and moves down whether shifted or not: Shift+Enter's
        // up move is abolished with the Notion-style keys (SPEC §27.2).
        #expect(routing(.enter) == .commit(.down))
        #expect(routing(.enter, shifted: true) == .commit(.down))
        #expect(routing(.tab) == .commit(.right))
        #expect(routing(.tab, shifted: true) == .commit(.left))

        // Everything else — the typing itself, the standard edit chords — is
        // the field editor's, exactly as it is mid composition.
        #expect(routing(.other) == .editor)
        #expect(routing(.other, shifted: true) == .editor)
    }
}
