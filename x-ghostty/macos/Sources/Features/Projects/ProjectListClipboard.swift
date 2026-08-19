import Foundation

// MARK: Cell-cursor clipboard (SPEC §27.7, must 83)

/// The model judgment behind Cmd+C / Cmd+V on the cell *cursor* (not an
/// edit session): what a cell's value copies as, and what — if anything — a
/// pasted string sets the cell to. Single cell only; rows and multi-cell
/// ranges are deliberately out of scope.
///
/// The paste side is parse-or-ignore: a string the column does not accept is
/// ignored — no mutation, like invalid deadline input (§24.1) but without
/// the unset fallback, because clearing a value is Delete's job (§27.2), not
/// the clipboard's. The visibility column takes no part in either direction.
enum ProjectListClipboard {
    /// The text Cmd+C lifts from `column`'s cell (`SPEC.md` §27.7): each
    /// value in its editable/display spelling — the same text a paste of it
    /// would parse back — and the note as every line. An unset value copies
    /// as the blank the cell shows. `nil` for the visibility column, where
    /// Cmd+C does nothing at all (the pasteboard keeps its old contents).
    static func copyText(of row: ProjectListRow, column: ProjectListColumn) -> String? {
        switch column {
        case .visibility: return nil
        case .title: return row.title
        case .priority: return row.priority?.displayText ?? ""
        case .deadline: return row.deadline?.displayText ?? ""
        case .nextTrigger: return row.nextTrigger?.displayText ?? ""
        case .note: return row.note
        }
    }

    /// What a paste of `text` sets `column`'s cell to (`SPEC.md` §27.7), or
    /// `.ignore` for a string the column does not accept. The title takes any
    /// text the shared rename rule would (non-blank after trimming); the
    /// value columns parse their own spellings; the note takes every line of
    /// any non-blank text (the save-time line cap still applies on commit,
    /// §21.1); the visibility column never changes by paste.
    static func pasteApplication(
        of text: String, column: ProjectListColumn
    ) -> ProjectListPasteApplication {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch column {
        case .visibility:
            return .ignore
        case .title:
            return trimmed.isEmpty ? .ignore : .setTitle(trimmed)
        case .priority:
            guard let priority = ProjectPriority.parsed(from: trimmed) else {
                return .ignore
            }
            return .setPriority(priority)
        case .deadline:
            guard let deadline = ProjectDeadline(parsing: trimmed) else {
                return .ignore
            }
            return .setDeadline(deadline)
        case .nextTrigger:
            guard let trigger = ProjectNextTrigger.parsed(from: trimmed) else {
                return .ignore
            }
            return .setNextTrigger(trigger)
        case .note:
            return trimmed.isEmpty ? .ignore : .setNote(text)
        }
    }
}

/// The typed outcome of a cell-cursor paste (`ProjectListClipboard`): the
/// value the accepted string sets, or `.ignore` — no mutation at all.
enum ProjectListPasteApplication: Equatable {
    case setTitle(String)
    case setPriority(ProjectPriority)
    case setDeadline(ProjectDeadline)
    case setNextTrigger(ProjectNextTrigger)
    case setNote(String)
    case ignore
}

extension ProjectPriority {
    /// Parse a pasted priority spelling (`SPEC.md` §27.7): the cell's own
    /// compact display spelling ("med"), the full word ("medium"), or the
    /// persistence raw value — case-insensitively. Anything else is `nil`.
    static func parsed(from text: String) -> ProjectPriority? {
        let lowered = text.lowercased()
        return allCases.first {
            lowered == $0.displayText.lowercased() || lowered == $0.rawValue.lowercased()
        }
    }
}

extension ProjectNextTrigger {
    /// Parse a pasted next-trigger spelling (`SPEC.md` §27.7): the cell's
    /// display spelling ("me" / "external" / "event") or the persistence raw
    /// value — case-insensitively. Anything else is `nil`.
    static func parsed(from text: String) -> ProjectNextTrigger? {
        let lowered = text.lowercased()
        return allCases.first {
            lowered == $0.displayText.lowercased() || lowered == $0.rawValue.lowercased()
        }
    }
}
