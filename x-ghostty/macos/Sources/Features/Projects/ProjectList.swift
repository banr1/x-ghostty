import Foundation

/// One row of the project list overlay (`SPEC.md` §27.1).
///
/// A pure value derived from the model: the view renders it and never recomputes
/// what a row should say. `ordinal` is `nil` exactly for hidden projects — they
/// have no canonical leaf and therefore no Cmd+1–9 number — which is also what
/// `isHidden` reports, kept as its own field so the view does not have to infer
/// the meaning of a missing number.
///
/// Unset fields are represented as they are in the model (`nil` priority, `nil`
/// deadline / next trigger, empty `note`); the view renders those as blanks.
struct ProjectListRow: Equatable, Identifiable {
    let id: ProjectID
    let title: String
    let ordinal: Int?
    let isHidden: Bool
    let priority: ProjectPriority?
    let deadline: ProjectDeadline?
    let nextTrigger: ProjectNextTrigger?

    /// The full note text: the note column normally shows only the first
    /// line, but the whole-list full-note toggle (`SPEC.md` §27.2) renders
    /// every line, so the row carries them all.
    let note: String

    /// What the one-line note cell shows: the note's first line, empty for an
    /// empty note.
    var noteFirstLine: String {
        note.components(separatedBy: "\n").first ?? ""
    }

    /// The text a cell edit of `column` starts from (`SPEC.md` §27.2): the
    /// column's current value in its editable spelling. `nil` for the
    /// selection columns, which are not text-editable.
    func editableText(for column: ProjectListColumn) -> String? {
        switch column {
        case .title: return title
        case .deadline: return deadline?.displayText ?? ""
        case .note: return noteFirstLine
        case .visibility, .priority, .nextTrigger: return nil
        }
    }
}

/// A column of the project list (`SPEC.md` §27.1). The raw value is the
/// persistence spelling of the column order.
enum ProjectListColumn: String, Codable, CaseIterable, Identifiable {
    case visibility, title, priority, deadline, nextTrigger, note

    var id: String { rawValue }

    /// Whether typing edits this column in place (`SPEC.md` §27.2): the text
    /// columns are title, deadline, and note.
    var isTextColumn: Bool {
        switch self {
        case .title, .deadline, .note: return true
        case .visibility, .priority, .nextTrigger: return false
        }
    }

    /// Whether Space cycles this column's value (`SPEC.md` §27.2): the
    /// selection columns are visibility (a two-value toggle), priority, and
    /// next trigger.
    var isSelectionColumn: Bool { !isTextColumn }

    /// The default column order (`SPEC.md` §27.1): visibility, title,
    /// priority, deadline, next trigger, note.
    static let defaultOrder: [ProjectListColumn] = [
        .visibility, .title, .priority, .deadline, .nextTrigger, .note,
    ]

    /// Repair a decoded column order so it is always a permutation of all
    /// columns: duplicates collapse to their first occurrence and missing
    /// columns append in default order.
    static func normalizedOrder(_ columns: [ProjectListColumn]) -> [ProjectListColumn] {
        var seen = Set<ProjectListColumn>()
        var order: [ProjectListColumn] = []
        for column in columns where !seen.contains(column) {
            seen.insert(column)
            order.append(column)
        }
        order += defaultOrder.filter { !seen.contains($0) }
        return order
    }
}

// MARK: Row derivation (SPEC §27.1)

extension WorkspaceStateOf {
    /// Every project — hidden ones included — as list rows, in the ledger's
    /// single row order (`SPEC.md` §27.1): the rows are *not* partitioned by
    /// visibility, and a row's ordinal is its 1-based position among the
    /// visible rows counted from the top (`nil` for hidden rows, which the
    /// numbering skips).
    var projectListRows: [ProjectListRow] {
        var ordinal = 0
        return projectOrder.compactMap { id in
            guard let project = projects[id] else { return nil }
            let hidden = hiddenProjectIDs.contains(id)
            if !hidden { ordinal += 1 }
            return Self.listRow(id: id, project: project, ordinal: hidden ? nil : ordinal)
        }
    }

    private static func listRow(
        id: ProjectID,
        project: ProjectStateOf<Pane>,
        ordinal: Int?
    ) -> ProjectListRow {
        ProjectListRow(
            id: id,
            title: project.name,
            ordinal: ordinal,
            isHidden: ordinal == nil,
            priority: project.priority,
            deadline: project.deadline,
            nextTrigger: project.nextTrigger,
            note: project.note)
    }
}

// MARK: Cell cursor (SPEC §27.2)

/// The project list's cell cursor: a (row, column) position over the rows in
/// ledger order and the columns in the persisted column order.
///
/// Movement is the model judgment of `SPEC.md` §27.2: Tab moves right and
/// wraps from a row's last cell to the next row's first, Shift+Tab mirrors it
/// leftwards, Enter moves down and stops at the last row, Shift+Enter moves
/// up and stops at the first — the arrow keys are the same four moves. The
/// grid's corners are absorbing: there is nowhere to wrap past the last (or
/// before the first) cell.
struct ProjectListCellCursor: Equatable {
    var row: Int
    var column: Int

    /// One cursor move: right/left are Tab/Shift+Tab (and →/←), down/up are
    /// Enter/Shift+Enter (and ↓/↑).
    enum Move {
        case right, left, down, up
    }

    /// The cursor after `move` on a `rowCount` × `columnCount` grid. An empty
    /// grid or a non-positive dimension leaves the cursor unchanged.
    func moved(_ move: Move, rowCount: Int, columnCount: Int) -> ProjectListCellCursor {
        guard rowCount > 0, columnCount > 0 else { return self }
        var next = clamped(rowCount: rowCount, columnCount: columnCount)
        switch move {
        case .right:
            if next.column + 1 < columnCount {
                next.column += 1
            } else if next.row + 1 < rowCount {
                // Row-end wrap: the next row's first cell (SPEC §27.2).
                next.row += 1
                next.column = 0
            }
        case .left:
            if next.column > 0 {
                next.column -= 1
            } else if next.row > 0 {
                next.row -= 1
                next.column = columnCount - 1
            }
        case .down:
            if next.row + 1 < rowCount { next.row += 1 }
        case .up:
            if next.row > 0 { next.row -= 1 }
        }
        return next
    }

    /// The cursor forced back onto a `rowCount` × `columnCount` grid — the
    /// repair for a row set or column order that shrank under the cursor.
    func clamped(rowCount: Int, columnCount: Int) -> ProjectListCellCursor {
        ProjectListCellCursor(
            row: min(max(row, 0), max(rowCount - 1, 0)),
            column: min(max(column, 0), max(columnCount - 1, 0)))
    }
}

// MARK: Cell edit session (SPEC §27.2)

/// One in-place text edit of a list cell: the pristine `original` the edit
/// started from and the `draft` the typist is building.
///
/// The commit/cancel judgment lives in the shape itself: committing applies
/// `draft` through `WorkspaceStateOf.commitListCellEdit`, cancelling simply
/// discards the session — no mutation ever happened, so the cell still shows
/// `original` (`SPEC.md` §27.2). Only text columns are editable; asking for a
/// selection column yields no session.
struct ProjectListCellEdit: Equatable {
    let rowID: ProjectID
    let column: ProjectListColumn
    let original: String
    var draft: String

    init?(row: ProjectListRow, column: ProjectListColumn) {
        guard let text = row.editableText(for: column) else { return nil }
        self.rowID = row.id
        self.column = column
        self.original = text
        self.draft = text
    }

    /// The session a keystroke on a text cell starts (`SPEC.md` §27.2, §27.5).
    ///
    /// The draft starts *empty* — typing replaces the cell's value, as it
    /// always has — and, unlike a seeded draft, it does not carry the
    /// keystroke that started the edit. That keystroke is replayed into the
    /// cell editor's input context instead, so a Japanese IME composition can
    /// begin on the very first stroke rather than having its raw character
    /// committed straight into the draft (must 78).
    static func started(
        on row: ProjectListRow, column: ProjectListColumn
    ) -> ProjectListCellEdit? {
        guard var session = ProjectListCellEdit(row: row, column: column) else {
            return nil
        }
        session.draft = ""
        return session
    }
}

// MARK: Edit-session key routing (SPEC §27.5)

/// A key press the list's keyDown monitor must route while a cell edit is up.
/// Only the presses that mean something to the *session* are named; every
/// other key is `.other` and belongs to the editor.
enum ProjectListEditKeyPress: Equatable {
    case escape
    case enter
    case tab
    case other
}

/// What the list does with a key press while a cell edit is up
/// (`SPEC.md` §27.5).
enum ProjectListEditKeyRouting: Equatable {
    /// Commit the draft and move the cursor.
    case commit(ProjectListCellCursor.Move)
    /// Discard the draft, leaving the cell's original value.
    case cancel
    /// Hand the press to the cell editor — which is also the IME's input
    /// path, so this is what "the IME keeps the key" looks like.
    case editor
}

extension ProjectListCellEdit {
    /// Where a key press goes while this edit is up (`SPEC.md` §27.5).
    ///
    /// The whole judgment is `composing`: while the IME holds a marked
    /// (uncommitted) string, *every* key belongs to the editor, because Space
    /// converts, Enter commits the conversion, and Escape cancels it — none of
    /// them may reach the session's own Enter-commits / Escape-cancels /
    /// Tab-moves meaning (must 78). Once nothing is marked, the session's
    /// terminators read exactly as they did before: Enter commits and moves
    /// down (Shift+Enter up), Tab commits and moves right (Shift+Tab left),
    /// Escape cancels this edit alone (§27.2).
    static func routing(
        for press: ProjectListEditKeyPress, shifted: Bool, composing: Bool
    ) -> ProjectListEditKeyRouting {
        guard !composing else { return .editor }
        switch press {
        case .escape: return .cancel
        case .enter: return .commit(shifted ? .up : .down)
        case .tab: return .commit(shifted ? .left : .right)
        case .other: return .editor
        }
    }
}

// MARK: Selection-column cycling (SPEC §27.2)

/// The next value of a Space-cycled selection cell: unset → the cases in
/// definition order → unset again.
private func cycledSelectionValue<Value: CaseIterable & Equatable>(
    after current: Value?
) -> Value? {
    let cases = Array(Value.allCases)
    guard let current, let index = cases.firstIndex(of: current) else {
        return cases.first
    }
    let next = cases.index(after: index)
    return next < cases.endIndex ? cases[next] : nil
}

extension ProjectPriority {
    /// Space in the priority cell (`SPEC.md` §27.2): unset → high → medium →
    /// low → unset.
    static func cycled(after current: ProjectPriority?) -> ProjectPriority? {
        cycledSelectionValue(after: current)
    }
}

extension ProjectNextTrigger {
    /// Space in the next-trigger cell (`SPEC.md` §27.2): unset → myself →
    /// external person → event → unset.
    static func cycled(after current: ProjectNextTrigger?) -> ProjectNextTrigger? {
        cycledSelectionValue(after: current)
    }
}

// MARK: Cell mutations (SPEC §27.2)

extension WorkspaceStateOf {
    /// Rename project `id` to `newName`: whitespace is trimmed and an empty
    /// result is rejected, keeping the existing name — the one title rule,
    /// shared by the inline rename, the `set_project_title` action, and the
    /// list's title cell (`SPEC.md` §9.1, §27.2).
    ///
    /// - Returns: whether the name changed.
    @discardableResult
    mutating func renameProject(_ id: ProjectID, to newName: String) -> Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var project = projects[id],
              project.name != trimmed else { return false }
        project.name = trimmed
        projects[id] = project
        return true
    }

    /// Apply a committed text-cell edit (`SPEC.md` §27.2): the title through
    /// the shared rename rule, the deadline through the parse-or-unset rule
    /// (invalid input is treated as unset, §24.1), and the note by rewriting
    /// only its first line — every later line is preserved.
    ///
    /// - Returns: whether the commit was accepted (an unknown project, a
    ///   selection column, or a rejected title leaves the state untouched).
    @discardableResult
    mutating func commitListCellEdit(
        _ text: String, column: ProjectListColumn, for id: ProjectID
    ) -> Bool {
        guard var project = projects[id] else { return false }
        switch column {
        case .title:
            return renameProject(id, to: text)
        case .deadline:
            project.deadline = ProjectDeadline(parsing: text)
            projects[id] = project
            return true
        case .note:
            var lines = project.note.components(separatedBy: "\n")
            if lines.isEmpty {
                lines = [text]
            } else {
                lines[0] = text
            }
            project.setNote(lines.joined(separator: "\n"))
            projects[id] = project
            return true
        case .visibility, .priority, .nextTrigger:
            return false
        }
    }

    /// Space on a cycling selection cell (`SPEC.md` §27.2): priority and next
    /// trigger step to their next value. The visibility column is *not*
    /// handled here — its toggle is the session-level hide/show with the
    /// at-least-one-visible and cap rules and the relayout.
    ///
    /// - Returns: whether a value cycled.
    @discardableResult
    mutating func cycleListCellValue(_ column: ProjectListColumn, for id: ProjectID) -> Bool {
        guard var project = projects[id] else { return false }
        switch column {
        case .priority:
            project.priority = ProjectPriority.cycled(after: project.priority)
        case .nextTrigger:
            project.nextTrigger = ProjectNextTrigger.cycled(after: project.nextTrigger)
        case .visibility, .title, .deadline, .note:
            return false
        }
        projects[id] = project
        return true
    }

    /// One Space (`forward`) or Shift+Space press on `id`'s deadline cell
    /// (`SPEC.md` §27.2): applies `ProjectDeadline.stepped` to the stored
    /// value immediately. The press belongs to no edit session — the value
    /// is committed the moment it is applied, so there is nothing an Esc
    /// could revert.
    ///
    /// - Returns: whether the press changed the deadline (an unset cell
    ///   stepped back is the no-op).
    @discardableResult
    mutating func stepListDeadline(
        for id: ProjectID, forward: Bool, today: ProjectDeadline
    ) -> Bool {
        guard var project = projects[id] else { return false }
        let step = ProjectDeadline.stepped(
            project.deadline, forward: forward, today: today)
        guard step.changed else { return false }
        project.deadline = step.value
        projects[id] = project
        return true
    }

    /// Move `column` by `delta` places in the persisted column order
    /// (`SPEC.md` §27.1), clamped to the ends.
    ///
    /// - Returns: whether the order changed.
    @discardableResult
    mutating func moveListColumn(_ column: ProjectListColumn, by delta: Int) -> Bool {
        guard let from = listColumnOrder.firstIndex(of: column) else { return false }
        let target = min(max(from + delta, 0), listColumnOrder.count - 1)
        guard target != from else { return false }
        listColumnOrder.remove(at: from)
        listColumnOrder.insert(column, at: target)
        return true
    }
}

// MARK: Daily priority reset (SPEC §28.2)

extension WorkspaceStateOf {
    /// Whether the priority reset is due at `now`: the workday `now` belongs to
    /// differs from the one the reset last ran for (`SPEC.md` §28.2). A state
    /// that never reset (no stored workday — a fresh workspace, or a save
    /// written before the reset existed) is always due, which is the rule read
    /// literally and is harmless: the reset only clears priorities, which is
    /// exactly what the next boundary would do.
    func needsPriorityReset(at now: Date, calendar: Calendar = .current) -> Bool {
        lastPriorityResetWorkday != Workday(containing: now, calendar: calendar)
    }

    /// Run the daily priority reset if it is due (`SPEC.md` §28.2): every
    /// project — hidden ones included — loses its priority, and the current
    /// workday is stamped so the reset cannot run twice within it.
    ///
    /// Deliberately narrow: deadlines and notes are untouched, and nothing here
    /// writes `canonicalProjectTree`, so the reset can never reorder projects
    /// (§28.3 — reordering stays exclusive to the explicit sort actions).
    ///
    /// - Returns: whether the reset actually ran.
    @discardableResult
    mutating func resetPrioritiesIfNeeded(at now: Date, calendar: Calendar = .current) -> Bool {
        let today = Workday(containing: now, calendar: calendar)
        guard lastPriorityResetWorkday != today else { return false }

        lastPriorityResetWorkday = today
        for id in projects.keys where projects[id]?.priority != nil {
            projects[id]?.priority = nil
        }
        return true
    }
}
