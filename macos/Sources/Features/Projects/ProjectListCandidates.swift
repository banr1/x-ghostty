import Foundation

// MARK: Value-candidate menus (SPEC §27.6)

/// One selectable value of a candidate menu (`SPEC.md` §27.6): the real
/// values a selection cell can take. "Unset" is deliberately absent from
/// every menu — clearing a value is Delete's job, not the menu's.
enum ProjectListCandidateValue: Equatable {
    case kind(ProjectKind)
    case terminal(ProjectTerminal)

    /// The text the menu row shows: the cell's own spelling of the value.
    var displayText: String {
        switch self {
        case .kind(let kind): return kind.displayText
        case .terminal(let terminal): return terminal.name
        }
    }
}

/// One open candidate-menu session (`SPEC.md` §27.6): the enumerated values
/// below a selection cell, with the keyboard selection. Up/Down move the
/// selection (clamped at the ends), Enter commits the selected value, Escape
/// discards the session — like a cell edit's cancel, no mutation ever
/// happened.
struct ProjectListCandidateMenu: Equatable {
    let rowID: ProjectID
    let column: ProjectListColumn
    let items: [ProjectListCandidateValue]
    var selection: Int

    /// The menu Enter opens on `column`'s cell, or `nil` for a column that
    /// does not enumerate candidates (`ProjectListColumn.enterAction`).
    ///
    /// The kind menu lists Core then Side (must 140). The terminal menu
    /// lists every registered terminal, the local one included, in
    /// registration order (must 128).
    static func opened(
        on row: ProjectListRow,
        column: ProjectListColumn,
        terminals: ProjectTerminalRegistry
    ) -> ProjectListCandidateMenu? {
        guard column.enterAction == .enumerateCandidates else { return nil }
        let items: [ProjectListCandidateValue]
        switch column {
        case .kind:
            items = ProjectKind.allCases.map { .kind($0) }
        case .terminal:
            items = terminals.terminals.map { .terminal($0) }
        case .visibility, .title, .note:
            return nil
        }
        guard !items.isEmpty else { return nil }
        return ProjectListCandidateMenu(
            rowID: row.id, column: column, items: items, selection: 0)
    }

    /// The menu after an Up/Down move of `delta`, clamped to the ends.
    func moved(by delta: Int) -> ProjectListCandidateMenu {
        var next = self
        next.selection = min(max(selection + delta, 0), items.count - 1)
        return next
    }

    /// The value Enter would commit right now.
    var selectedValue: ProjectListCandidateValue {
        items[min(max(selection, 0), items.count - 1)]
    }
}

// MARK: Candidate-menu key routing (SPEC §27.6)

/// A key press the list's keyDown monitor must route while a candidate menu
/// is up. Only the presses that mean something to the menu are named; every
/// other key is `.other` and is inert.
enum ProjectListCandidateKeyPress: Equatable {
    case up
    case down
    case enter
    case escape
    case tab
    case other
}

/// What the list does with a key press while a candidate menu is up
/// (`SPEC.md` §27.6): Up/Down move the selection, Enter commits it, Escape
/// closes changing nothing, and Tab / Shift+Tab close changing nothing and
/// move the cell cursor right/left (must 83) — the same wrap and edge stops
/// as any other cursor move.
enum ProjectListCandidateKeyRouting: Equatable {
    /// Move the keyboard selection by the delta (clamped at the ends).
    case moveSelection(Int)
    /// Commit the selected value and close.
    case commitSelection
    /// Close the menu; no value ever changed.
    case close
    /// Close the menu without committing and move the cell cursor — the
    /// Tab / Shift+Tab lateral move of must 83.
    case closeAndMoveCursor(ProjectListCellCursor.Move)
    /// The key means nothing to the menu.
    case ignore
}

extension ProjectListCandidateMenu {
    /// Where a key press goes while a candidate menu is up (`SPEC.md` §27.6).
    static func routing(
        for press: ProjectListCandidateKeyPress, shifted: Bool
    ) -> ProjectListCandidateKeyRouting {
        switch press {
        case .up: return .moveSelection(-1)
        case .down: return .moveSelection(1)
        case .enter: return .commitSelection
        case .escape: return .close
        case .tab: return .closeAndMoveCursor(shifted ? .left : .right)
        case .other: return .ignore
        }
    }
}
