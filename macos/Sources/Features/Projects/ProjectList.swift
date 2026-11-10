import Foundation

/// One row of the project list overlay (`SPEC.md` §27.1).
///
/// A pure value derived from the model: the view renders it and never recomputes
/// what a row should say. `ordinal` is `nil` for a project without a Cmd+1–9
/// number: a hidden one, or a visible one past the first nine in placement
/// order. `isHidden` is its own field because a missing number does not mean
/// hidden.
///
/// Unset fields are represented as they are in the model (`nil` terminal for
/// the local one, empty `note`); the view renders an empty note as a blank.
struct ProjectListRow: Equatable, Identifiable {
    let id: ProjectID
    let title: String
    let ordinal: Int?
    let isHidden: Bool

    /// The project's stored terminal name, `nil` for the local terminal
    /// (must 128). The cell shows the name it resolves to in the registry
    /// (`terminalDisplayName(in:)`), so an unregistered name reads as local.
    var terminalName: String? = nil

    /// The project's kind (must 140), shown by the kind column.
    var kind: ProjectKind = .core

    /// The full note text: the note column normally shows only the first
    /// line, but the whole-list full-note toggle (`SPEC.md` §27.2) renders
    /// every line, so the row carries them all.
    let note: String

    /// What the row's gutter shows: the ordinal, the hidden marker for a hidden
    /// row, and nothing for a visible row without a number.
    var ordinalGutterText: String {
        if let ordinal { return String(ordinal) }
        return isHidden ? "·" : ""
    }

    /// What the one-line note cell shows: the note's first line, empty for an
    /// empty note.
    var noteFirstLine: String {
        note.components(separatedBy: "\n").first ?? ""
    }

    /// What the terminal cell shows: the display name of the terminal the
    /// project runs on. Never blank — a project always has a terminal, the
    /// local one by default.
    func terminalDisplayName(in terminals: ProjectTerminalRegistry) -> String {
        terminals.terminal(named: terminalName).name
    }

    /// The text a cell edit of `column` starts from (`SPEC.md` §27.2): the
    /// column's current value in its editable spelling. The note edit covers
    /// the *whole* note — every line, not the displayed first line (§27.2:
    /// the cell shows line 1, the edit owns all of them). `nil` for the
    /// selection columns, which are not text-editable.
    func editableText(for column: ProjectListColumn) -> String? {
        switch column {
        case .title: return title
        case .note: return note
        case .visibility, .kind, .terminal: return nil
        }
    }
}

/// A column of the project list (`SPEC.md` §27.1). The raw value is the
/// persistence spelling of the column order.
enum ProjectListColumn: String, Codable, CaseIterable, Identifiable {
    case visibility, kind, title, terminal, note

    var id: String { rawValue }

    /// Whether typing starts a replace edit on this column in place
    /// (`SPEC.md` §27.2): the text columns are title and note.
    var isTextColumn: Bool {
        switch self {
        case .title, .note: return true
        case .visibility, .kind, .terminal: return false
        }
    }

    /// The selection columns — visibility (a two-value toggle), kind, and
    /// terminal — where typing never starts an edit.
    var isSelectionColumn: Bool { !isTextColumn }

    /// Whether this column's cell edit is multi-line (`SPEC.md` §27.2): only
    /// the note — its edit covers every line, Shift+Enter inserts a newline
    /// and the cell expands downward. Every other text edit is one line.
    var isMultilineEdit: Bool { self == .note }

    /// What Enter does on this column's cell (`SPEC.md` §27.2, Notion-style
    /// — Enter operates on the cell, it never moves the cursor): the text
    /// columns start a seeded edit with the caret in the existing text; the
    /// visibility column toggles hide/show immediately (under the
    /// at-least-one-visible protection); the value columns — kind and
    /// terminal — enumerate their candidates below the cell (§27.6).
    var enterAction: ProjectListEnterAction {
        switch self {
        case .title, .note: return .beginEdit
        case .visibility: return .toggleVisibility
        case .kind, .terminal: return .enumerateCandidates
        }
    }

    /// The default column order (`SPEC.md` §27.1): visibility, kind, title,
    /// terminal, note.
    static let defaultOrder: [ProjectListColumn] = [
        .visibility, .kind, .title, .terminal, .note,
    ]

    /// Repair a decoded column order so it is always a permutation of all
    /// columns: duplicates collapse to their first occurrence, and each
    /// missing column is inserted right after the column that precedes it in
    /// the default order (at the front when it has none). A save written
    /// before a column existed therefore gains it where the default puts it —
    /// the kind column after the visibility, the terminal column after the
    /// title — while the saved order of
    /// the other columns is kept.
    static func normalizedOrder(_ columns: [ProjectListColumn]) -> [ProjectListColumn] {
        var seen = Set<ProjectListColumn>()
        var order: [ProjectListColumn] = []
        for column in columns where !seen.contains(column) {
            seen.insert(column)
            order.append(column)
        }
        for (index, column) in defaultOrder.enumerated() where !seen.contains(column) {
            let predecessor = index > 0 ? defaultOrder[index - 1] : nil
            let position = predecessor
                .flatMap { order.firstIndex(of: $0) }
                .map { $0 + 1 } ?? 0
            order.insert(column, at: position)
            seen.insert(column)
        }
        return order
    }
}

/// The per-column judgment of what Enter does on a cell (`SPEC.md` §27.2).
enum ProjectListEnterAction: Equatable {
    /// Start an in-place edit seeded with the cell's current text, caret in
    /// the existing content (unlike a typed edit, which replaces).
    case beginEdit
    /// Toggle the row between hidden and visible immediately.
    case toggleVisibility
    /// Enumerate the cell's value candidates below it (§27.6).
    case enumerateCandidates
}

/// The per-column judgment of what Delete does on a cell (`SPEC.md` §27.2):
/// the title empties and the value columns reset immediately; the note —
/// the one cell whose loss is many lines of handwriting — asks for
/// confirmation first; the visibility column has no value to delete.
enum ProjectListDeleteAction: Equatable {
    /// Clear the cell's value immediately (`deleteListCellValue`).
    case clearValue
    /// Ask for confirmation; OK deletes every note line, Cancel does nothing.
    case confirmClearNote
    /// Delete does nothing on this column.
    case none
}

extension ProjectListColumn {
    /// What Delete does on this column's cell (`SPEC.md` §27.2).
    var deleteAction: ProjectListDeleteAction {
        switch self {
        case .title, .kind, .terminal: return .clearValue
        case .note: return .confirmClearNote
        case .visibility: return .none
        }
    }
}

// MARK: Row selection (SPEC §27.2)

/// The list's keyboard interaction mode (`SPEC.md` §27.2): the cell cursor,
/// or the whole-row selection Escape enters from it. In row selection the
/// up/down moves carry the selected row (the cursor's row), Enter returns to
/// the cell cursor on that row, Escape releases likewise, and Delete closes
/// the row's project through the same confirmation as `close_project` —
/// hidden rows included.
enum ProjectListKeyboardMode: Equatable {
    case cellCursor
    case rowSelection

    /// Escape's transition (`SPEC.md` §27.2): the cell cursor enters row
    /// selection; row selection releases back to the cell cursor. The list
    /// itself never closes on Escape — Cmd+L is the toggle.
    var escaped: ProjectListKeyboardMode {
        switch self {
        case .cellCursor: return .rowSelection
        case .rowSelection: return .cellCursor
        }
    }

    /// Enter's transition: row selection returns to the cell cursor on the
    /// selected row. In cell-cursor mode Enter is not a mode change — it
    /// operates on the cell (`ProjectListColumn.enterAction`).
    var entered: ProjectListKeyboardMode {
        .cellCursor
    }
}

// MARK: Row derivation (SPEC §27.1)

extension WorkspaceStateOf {
    /// Every project — hidden ones included — as list rows, in the ledger's
    /// single row order (`SPEC.md` §27.1): the rows are *not* partitioned by
    /// visibility, and a row's ordinal is the project's own display number
    /// (`projectOrdinals`, the placement order — `nil` for hidden rows, which
    /// the numbering skips, and for visible rows past the first nine).
    var projectListRows: [ProjectListRow] {
        let ordinals = projectOrdinals
        return projectOrder.compactMap { id in
            guard let project = projects[id] else { return nil }
            return Self.listRow(
                id: id,
                project: project,
                ordinal: ordinals[id],
                isHidden: hiddenProjectIDs.contains(id))
        }
    }

    /// Where a list focus request on row `id` actually lands (`SPEC.md`
    /// §27.3): a visible row focuses itself; a hidden row — which has no
    /// place on screen — resolves to the *nearest visible* row by ledger
    /// distance, the one above preferred on ties. `nil` for an unknown row
    /// (a no-visible-rows ledger cannot resolve either, but the
    /// at-least-one-visible invariant keeps that unreachable in practice).
    func resolvedListFocusTarget(for id: ProjectID) -> ProjectID? {
        guard projects[id] != nil else { return nil }
        guard hiddenProjectIDs.contains(id) else { return id }
        guard let index = projectOrder.firstIndex(of: id) else { return nil }
        for distance in 1..<max(projectOrder.count, 2) {
            for candidate in [index - distance, index + distance]
            where projectOrder.indices.contains(candidate) {
                let neighbor = projectOrder[candidate]
                if !hiddenProjectIDs.contains(neighbor) { return neighbor }
            }
        }
        return nil
    }

    private static func listRow(
        id: ProjectID,
        project: ProjectStateOf<Pane>,
        ordinal: Int?,
        isHidden: Bool
    ) -> ProjectListRow {
        ProjectListRow(
            id: id,
            title: project.name,
            ordinal: ordinal,
            isHidden: isHidden,
            terminalName: project.terminalName,
            kind: project.kind,
            note: project.note)
    }
}

// MARK: Cell cursor (SPEC §27.2)

/// The project list's cell cursor: a (row, column) position over the rows in
/// ledger order and the columns in the persisted column order.
///
/// Movement is the model judgment of `SPEC.md` §27.2 (Notion-style): the
/// arrow keys move in all four directions, Tab moves right and wraps from a
/// row's last cell to the next row's first, Shift+Tab mirrors it leftwards,
/// and up/down stop at the edge rows. Enter never moves the cursor — it
/// operates on the cell (`ProjectListColumn.enterAction`); the down/up moves
/// remain what an edit commit walks. Cmd+arrows jump to the edges
/// (`movedToEdge`). The grid's corners are absorbing: there is nowhere to
/// wrap past the last (or before the first) cell.
///
/// `ProjectListTitleSeat` below resolves where a new row's title edit lands.
struct ProjectListCellCursor: Equatable {
    var row: Int
    var column: Int

    /// One cursor move: right/left are Tab/Shift+Tab (and →/←), down/up are
    /// ↓/↑ (and where a committed edit walks).
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

    /// The cursor after a Cmd+arrow edge jump (`SPEC.md` §27.2): straight to
    /// the first/last row (up/down) or the leftmost/rightmost column
    /// (left/right), keeping the other coordinate. An empty grid leaves the
    /// cursor unchanged.
    func movedToEdge(_ move: Move, rowCount: Int, columnCount: Int) -> ProjectListCellCursor {
        guard rowCount > 0, columnCount > 0 else { return self }
        var next = clamped(rowCount: rowCount, columnCount: columnCount)
        switch move {
        case .up: next.row = 0
        case .down: next.row = rowCount - 1
        case .left: next.column = 0
        case .right: next.column = columnCount - 1
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
    /// Insert a newline into the draft (Shift+Enter on a multi-line edit,
    /// `SPEC.md` §27.2) — the cell expands downward with it.
    case insertNewline
}

extension ProjectListCellEdit {
    /// Where a key press goes while this edit is up (`SPEC.md` §27.5).
    ///
    /// The whole judgment is `composing`: while the IME holds a marked
    /// (uncommitted) string, *every* key belongs to the editor, because Space
    /// converts, Enter commits the conversion, and Escape cancels it — none of
    /// them may reach the session's own Enter-commits / Escape-cancels /
    /// Tab-moves meaning (must 78). Once nothing is marked, the session's
    /// terminators read per §27.2: Enter commits and moves down, Tab commits
    /// and moves right (Shift+Tab left), Escape cancels this edit alone.
    /// On a multi-line edit (the note cell) Shift+Enter is a newline
    /// insertion instead of a commit; on a one-line edit the shift changes
    /// nothing (Shift+Enter's up move is abolished with the Notion-style
    /// keys).
    static func routing(
        for press: ProjectListEditKeyPress, shifted: Bool, composing: Bool,
        multiline: Bool = false
    ) -> ProjectListEditKeyRouting {
        guard !composing else { return .editor }
        switch press {
        case .escape: return .cancel
        case .enter: return multiline && shifted ? .insertNewline : .commit(.down)
        case .tab: return .commit(shifted ? .left : .right)
        case .other: return .editor
        }
    }
}

// MARK: Editing shortcuts during a cell edit (SPEC §27.5, must 83)

/// The six standard editing shortcuts a cell edit routes to its own editor
/// (must 83): while an edit is up they act on the cell's text — never on the
/// terminal behind, which the keyDown monitor guarantees by consuming the
/// chord after performing it. Undo history is the field editor's own, scoped
/// to the editing session like the note editor's.
enum ProjectListEditorShortcut: CaseIterable, Equatable {
    case selectAll, copy, cut, paste, undo, redo

    /// The editor shortcut a Cmd-chord means, or `nil` for a chord that is
    /// not one of the six (which keeps its existing meaning). `character` is
    /// the modifier-stripped key character; `shifted` distinguishes redo
    /// (Cmd+Shift+Z) from undo (Cmd+Z).
    static func shortcut(
        forCommandCharacter character: String, shifted: Bool
    ) -> ProjectListEditorShortcut? {
        switch (character.lowercased(), shifted) {
        case ("a", false): return .selectAll
        case ("c", false): return .copy
        case ("x", false): return .cut
        case ("v", false): return .paste
        case ("z", false): return .undo
        case ("z", true): return .redo
        default: return nil
        }
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
    /// the shared rename rule, and the note by replacing
    /// the whole note — the edit covers every line, and `setNote` applies
    /// the line cap (the over-limit confirmation happens before the commit
    /// reaches here, §21.1).
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
        case .note:
            project.setNote(text)
            projects[id] = project
            return true
        case .visibility, .kind, .terminal:
            return false
        }
    }

    /// Set project `id`'s kind (must 140). The row order never changes; a
    /// visible project's arrangement re-derives
    /// with it (`SPEC.md` §26.3).
    ///
    /// - Returns: whether the kind changed.
    @discardableResult
    mutating func setProjectKind(_ id: ProjectID, to kind: ProjectKind) -> Bool {
        guard var project = projects[id], project.kind != kind else { return false }
        project.kind = kind
        projects[id] = project
        if !hiddenProjectIDs.contains(id) { relayout() }
        return true
    }

    /// Set project `id`'s terminal to the stored name `name` (`nil` = the
    /// local terminal, must 128). The row order never changes. Panes already open keep running where they are;
    /// the change applies to panes started afterwards.
    ///
    /// - Returns: whether the stored name changed.
    @discardableResult
    mutating func setProjectTerminal(_ id: ProjectID, to name: String?) -> Bool {
        guard var project = projects[id], project.terminalName != name else { return false }
        project.terminalName = name
        projects[id] = project
        return true
    }

    /// Apply a Delete on `column`'s cell (`SPEC.md` §27.2): the title
    /// empties — deliberately bypassing the rename rule's empty-reject,
    /// which protects against *accidental* emptiness, not this explicit
    /// deletion — the kind returns to Core, the terminal returns to the local
    /// one, and the note loses every line. The note's confirmation is the
    /// caller's (`ProjectListColumn.deleteAction`); this is the mutation
    /// an approved deletion applies. The visibility column has no value
    /// to delete.
    ///
    /// - Returns: whether anything was deleted (an unknown project or the
    ///   visibility column leaves the state untouched).
    @discardableResult
    mutating func deleteListCellValue(
        _ column: ProjectListColumn, for id: ProjectID
    ) -> Bool {
        guard var project = projects[id] else { return false }
        switch column {
        case .title:
            project.name = ""
            projects[id] = project
            return true
        case .kind:
            setProjectKind(id, to: .core)
            return true
        case .terminal:
            project.terminalName = nil
            projects[id] = project
            return true
        case .note:
            project.setNote("")
            projects[id] = project
            return true
        case .visibility:
            return false
        }
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

/// Where the title edit of a newly created row lands (`Cmd+N`, `SPEC.md`
/// §27.4): the new row's title cell, in the rows and columns as they stand
/// now. `nil` while nothing is pending, or until the pending row has appeared
/// in `rows`.
///
/// The overlay observes this value rather than the pending id alone: a SwiftUI
/// `onChange` closure may run with the view values of the previous body, so the
/// row and its position must arrive inside the observed value.
struct ProjectListTitleSeat: Equatable {
    let row: ProjectListRow
    let cursor: ProjectListCellCursor

    static func resolve(
        pending: ProjectID?, rows: [ProjectListRow], columns: [ProjectListColumn]
    ) -> ProjectListTitleSeat? {
        guard let pending,
              let rowIndex = rows.firstIndex(where: { $0.id == pending }),
              let columnIndex = columns.firstIndex(of: .title)
        else { return nil }
        return ProjectListTitleSeat(
            row: rows[rowIndex],
            cursor: ProjectListCellCursor(row: rowIndex, column: columnIndex))
    }
}
