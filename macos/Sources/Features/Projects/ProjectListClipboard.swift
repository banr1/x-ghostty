import Foundation

// MARK: Cell-cursor clipboard (SPEC §27.7, must 83)

/// The model judgment behind Cmd+C / Cmd+V on the cell *cursor* (not an
/// edit session): what a cell's value copies as, and what — if anything — a
/// pasted string sets the cell to. Single cell only; rows and multi-cell
/// ranges are deliberately out of scope.
///
/// The paste side is parse-or-ignore: a string the column does not accept is
/// ignored — no mutation, because clearing a value is Delete's job (§27.2),
/// not the clipboard's. The visibility column takes no part in either direction.
enum ProjectListClipboard {
    /// The text Cmd+C lifts from `column`'s cell (`SPEC.md` §27.7): each
    /// value in its editable/display spelling — the same text a paste of it
    /// would parse back — and the note as every line. `nil` for the visibility column, where
    /// Cmd+C does nothing at all (the pasteboard keeps its old contents).
    static func copyText(
        of row: ProjectListRow,
        column: ProjectListColumn,
        terminals: ProjectTerminalRegistry
    ) -> String? {
        switch column {
        case .visibility: return nil
        case .title: return row.title
        case .kind: return row.kind.displayText
        case .terminal: return row.terminalDisplayName(in: terminals)
        case .note: return row.note
        }
    }

    /// What a paste of `text` sets `column`'s cell to (`SPEC.md` §27.7), or
    /// `.ignore` for a string the column does not accept. The title takes any
    /// text the shared rename rule would (non-blank after trimming); the
    /// kind takes only Core or Side (must 140); the terminal takes only a
    /// registered display name (must 128); the note takes every line of
    /// any non-blank text (the save-time line cap still applies on commit,
    /// §21.1); the visibility column never changes by paste.
    static func pasteApplication(
        of text: String,
        column: ProjectListColumn,
        terminals: ProjectTerminalRegistry
    ) -> ProjectListPasteApplication {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch column {
        case .visibility:
            return .ignore
        case .title:
            return trimmed.isEmpty ? .ignore : .setTitle(trimmed)
        case .kind:
            guard let kind = ProjectKind.allCases.first(where: { $0.displayText == trimmed })
            else {
                return .ignore
            }
            return .setKind(kind)
        case .terminal:
            guard let terminal = terminals.registeredTerminal(named: trimmed) else {
                return .ignore
            }
            return .setTerminal(terminal)
        case .note:
            return trimmed.isEmpty ? .ignore : .setNote(text)
        }
    }
}

/// The typed outcome of a cell-cursor paste (`ProjectListClipboard`): the
/// value the accepted string sets, or `.ignore` — no mutation at all.
enum ProjectListPasteApplication: Equatable {
    case setTitle(String)
    case setKind(ProjectKind)
    case setTerminal(ProjectTerminal)
    case setNote(String)
    case ignore
}
