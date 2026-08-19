import Foundation

/// The sort state of the project list (`SPEC.md` §24.4): the persisted rule
/// that *governs* the ledger's row order — not a disposable action. Five
/// values, manual by default. Because it is a state, it decides the display
/// order (and with it the ordinals, Cmd+1–9) even while the list overlay is
/// closed: any change to a sort key re-sorts immediately.
///
/// The row order model is deliberately single-track: `projectOrder` *is* the
/// display order at all times. While a key state is active, every trigger
/// (cell-value change, creation, load, the morning priority reset) re-applies
/// the key's stable ordering to `projectOrder` in place, so ties keep the
/// previous display order — exactly the spec's stability rule. Selecting
/// manual therefore inherits the current display order for free: the rows
/// simply stop being re-sorted (`SPEC.md` §24.5).
enum ProjectSortState: String, Codable, CaseIterable, Equatable {
    /// The human's own order. Never re-sorts; rows move only by explicit
    /// row moves (`Opt+↑↓`).
    case manual
    /// By next trigger: myself → external → event → unset.
    case next
    /// By visibility: visible rows above hidden ones.
    case show
    /// By deadline: nearest date first, unset last.
    case deadline
    /// By priority: high → medium → low → unset.
    case priority

    /// The label the sort bar and the docs show for this state.
    var displayText: String {
        switch self {
        case .manual: return "manual"
        case .next: return "next"
        case .show: return "show"
        case .deadline: return "deadline"
        case .priority: return "priority"
        }
    }
}

extension ProjectNextTrigger {
    /// Position of this value in the next-trigger sort order (`SPEC.md`
    /// §24.4): myself → external → event, with unset after all of them
    /// (`unsetSortRank`) — the same shape as `ProjectPriority.sortRank`.
    var sortRank: Int {
        switch self {
        case .myself: return 0
        case .externalPerson: return 1
        case .event: return 2
        }
    }

    /// The sort rank of an unset next trigger: last (`SPEC.md` §24.4).
    static var unsetSortRank: Int { 3 }
}

extension WorkspaceStateOf {
    /// Every row — hidden ones included — in next-trigger order (`SPEC.md`
    /// §24.4): myself → external → event → unset. Same contract as the
    /// priority/deadline orderings: pure, stable within a rank.
    func nextTriggerOrderedProjectIDs() -> [ProjectID] {
        stableOrderedProjectIDs { id in
            projects[id]?.nextTrigger?.sortRank ?? ProjectNextTrigger.unsetSortRank
        }
    }

    /// Every row in visibility order (`SPEC.md` §24.4): visible rows above
    /// hidden ones, each block keeping its current relative order.
    func visibilityOrderedProjectIDs() -> [ProjectID] {
        stableOrderedProjectIDs { hiddenProjectIDs.contains($0) ? 1 : 0 }
    }

    /// The ledger in `state`'s order: the current row order for manual (a
    /// manual "sort" is the absence of one), the key's stable ordering
    /// otherwise. Pure — applying it is `resortProjects()`.
    func orderedProjectIDs(by state: ProjectSortState) -> [ProjectID] {
        switch state {
        case .manual: return projectOrder
        case .next: return nextTriggerOrderedProjectIDs()
        case .show: return visibilityOrderedProjectIDs()
        case .deadline: return deadlineOrderedProjectIDs()
        case .priority: return priorityOrderedProjectIDs()
        }
    }

    /// Re-apply the active sort state to the row order (`SPEC.md` §24.4).
    /// The re-sort trigger, called after every mutation that can change a
    /// sort key (cell edits, value cycling, visibility changes, creation,
    /// restore, the morning priority reset). A no-op in the manual state and
    /// when the order is already sorted; stable, so ties keep the previous
    /// display order.
    ///
    /// - Returns: whether the row order changed.
    @discardableResult
    mutating func resortProjects() -> Bool {
        guard sortState != .manual else { return false }
        return applyProjectOrder(orderedProjectIDs(by: sortState))
    }

    /// Select a sort state (the sort bar's Enter, `SPEC.md` §24.5). A key
    /// state applies its ordering immediately; selecting manual inherits the
    /// current display order as the manual order — `projectOrder` *is* the
    /// display order, so stopping the re-sorts is the whole inheritance.
    /// This is also the model half of the row-move approval (§27.3): the
    /// caller flips to manual here, then performs the move.
    ///
    /// - Returns: whether the row order changed (a state change alone,
    ///   order intact, returns false).
    @discardableResult
    mutating func setSortState(_ newState: ProjectSortState) -> Bool {
        sortState = newState
        return resortProjects()
    }
}
