import Foundation

// MARK: Value-candidate menus (SPEC §27.6)

/// One selectable value of a candidate menu (`SPEC.md` §27.6): the real
/// values a selection cell can take. "Unset" is deliberately absent from
/// every menu — clearing a value is Delete's job, not the menu's.
enum ProjectListCandidateValue: Equatable {
    case priority(ProjectPriority)
    case nextTrigger(ProjectNextTrigger)
    case deadline(ProjectDeadline)

    /// The text the menu row shows: the cell's own compact spelling for the
    /// selection values, a real date like `Aug 19` for a date candidate.
    var displayText: String {
        switch self {
        case .priority(let priority): return priority.displayText
        case .nextTrigger(let trigger): return trigger.displayText
        case .deadline(let deadline): return deadline.monthDayText
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
    /// The priority and next-trigger menus list every real value — never
    /// unset (SPEC §27.6). The deadline menu lists the 10 date candidates
    /// derived from `today` (`ProjectDeadline.dateCandidates`).
    static func opened(
        on row: ProjectListRow, column: ProjectListColumn, today: ProjectDeadline
    ) -> ProjectListCandidateMenu? {
        guard column.enterAction == .enumerateCandidates else { return nil }
        let items: [ProjectListCandidateValue]
        switch column {
        case .priority:
            items = ProjectPriority.allCases.map { .priority($0) }
        case .nextTrigger:
            items = ProjectNextTrigger.allCases.map { .nextTrigger($0) }
        case .deadline:
            items = ProjectDeadline.dateCandidates(from: today).map { .deadline($0) }
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

extension ProjectPriority {
    /// The compact spelling the list cell and the candidate menu share.
    var displayText: String {
        switch self {
        case .high: return "high"
        case .medium: return "med"
        case .low: return "low"
        }
    }
}

// MARK: Date candidates (SPEC §27.6)

extension ProjectDeadline {
    /// The deadline cell's 10 date candidates (`SPEC.md` §27.6): today
    /// through 7 days ahead (8), then the same day next month and the same
    /// day in 3 months — a nonexistent same day (e.g. the month after
    /// Jan 31) clamps to that month's last day (`sameDayAddingMonths`).
    /// "Unset" is never a candidate; arbitrary dates stay typed input.
    static func dateCandidates(from today: ProjectDeadline) -> [ProjectDeadline] {
        let days = (0...7).compactMap { today.advanced(by: $0) }
        let months = [1, 3].compactMap { today.sameDayAddingMonths($0) }
        return days + months
    }

    /// The same calendar day `months` (non-negative) ahead, with a day the
    /// target month does not have clamped to its last day (Jan 31 + 1 month
    /// = Feb 28/29). `nil` only when the arithmetic leaves the representable
    /// four-digit-year range.
    func sameDayAddingMonths(_ months: Int) -> ProjectDeadline? {
        guard months >= 0 else { return nil }
        let zeroBased = month - 1 + months
        let targetYear = year + zeroBased / 12
        let targetMonth = zeroBased % 12 + 1
        // Constructive clamp: the first valid day at or below this one is
        // the target month's last day when the same day does not exist.
        for candidate in stride(from: min(day, 31), through: 1, by: -1) {
            if let clamped = ProjectDeadline(
                year: targetYear, month: targetMonth, day: candidate) {
                return clamped
            }
        }
        return nil
    }

    /// The `Aug 19` spelling the date candidates are shown as (SPEC §27.6).
    /// Fixed English month abbreviations, matching the product's other
    /// terminal-style readouts regardless of locale.
    var monthDayText: String {
        let names = [
            "Jan", "Feb", "Mar", "Apr", "May", "Jun",
            "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
        ]
        guard (1...12).contains(month) else { return displayText }
        return "\(names[month - 1]) \(day)"
    }
}
