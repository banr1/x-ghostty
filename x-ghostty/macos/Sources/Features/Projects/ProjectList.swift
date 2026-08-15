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

// MARK: Row derivation (SPEC §27.1)

extension WorkspaceStateOf {
    /// Every project — hidden ones included — as list rows: the visible
    /// projects first, in ordinal order, then the hidden ones (`SPEC.md`
    /// §27.1).
    ///
    /// "Hidden" is derived from the canonical tree rather than read out of
    /// `hiddenProjectIDs`: a project is visible exactly while it holds a
    /// canonical leaf (invariant §14.3), so this stays correct even if the
    /// runtime hidden set were stale.
    ///
    /// Hidden rows are ordered by creation (ties broken by id) — the same
    /// deterministic order `reconcileOrphanedProjects` re-attaches them in, so
    /// the list reads the same way twice and matches the order a restore would
    /// bring them back in.
    var projectListRows: [ProjectListRow] {
        let visible = visibleProjectIDs
        var rows: [ProjectListRow] = []
        rows.reserveCapacity(projects.count)

        for (index, id) in visible.enumerated() {
            guard let project = projects[id] else { continue }
            rows.append(Self.listRow(id: id, project: project, ordinal: index + 1))
        }

        let placed = Set(visible)
        let hidden = projects
            .filter { !placed.contains($0.key) }
            .sorted { ($0.value.createdAt, $0.key.rawValue.uuidString) <
                      ($1.value.createdAt, $1.key.rawValue.uuidString) }
        for (id, project) in hidden {
            rows.append(Self.listRow(id: id, project: project, ordinal: nil))
        }

        return rows
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

    /// Whether `id` is currently hidden: it exists as a project but holds no
    /// canonical leaf (invariant §14.3).
    func isProjectHidden(_ id: ProjectID) -> Bool {
        projects[id] != nil && canonicalProjectTree.find(id: id) == nil
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
