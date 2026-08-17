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
/// deadline, empty `noteFirstLine`); the view renders those as blanks.
struct ProjectListRow: Equatable, Identifiable {
    let id: ProjectID
    let title: String
    let ordinal: Int?
    let isHidden: Bool
    let priority: ProjectPriority?
    let deadline: ProjectDeadline?
    let noteFirstLine: String
}

/// A column of the project list (`SPEC.md` §27.1). The raw value is the
/// persistence spelling of the column order.
enum ProjectListColumn: String, Codable, CaseIterable, Identifiable {
    case visibility, title, priority, deadline, nextTrigger, note

    var id: String { rawValue }

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
            noteFirstLine: firstNoteLine(project.note))
    }

    /// The note's first line — what a one-line-per-project table can show.
    /// Empty for an empty note, which the view renders as a blank cell.
    static func firstNoteLine(_ note: String) -> String {
        note.components(separatedBy: "\n").first ?? ""
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
