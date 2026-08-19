import Foundation
import Testing
@testable import XGhostty

/// A value-type pane element standing in for `XGhostty.SurfaceView`, which
/// cannot be constructed without a live XGhostty app. The generic model layer
/// runs the exact same code for both element types, so these tests exercise
/// the real sort-state judgment logic (SPEC §24.4–24.5) with real rows in the
/// ledger.
private struct TestPane: Codable, Identifiable, Equatable {
    let id: UUID
    init(id: UUID = UUID()) { self.id = id }
}

private typealias TestProjectState = ProjectStateOf<TestPane>
private typealias TestWorkspaceState = WorkspaceStateOf<TestPane>
private typealias TestWorkspaceModel = WorkspaceModelOf<TestPane>

/// Tests for the sort state (SPEC §24.4–24.5, success condition 20): the
/// manual default, persistence and restore, the fixed direction and stability
/// of every key (next / show / deadline / priority), the immediate re-sort on
/// cell-value changes and creation while a key state is active, the re-sort
/// on load, and the manual handover inheriting the current display order.
struct ProjectSortStateTests {
    private static func makeProject(name: String, at offset: TimeInterval = 0) -> TestProjectState {
        TestProjectState(
            id: ProjectID(), name: name, paneTree: .init(view: TestPane()),
            createdAt: Date(timeIntervalSince1970: offset))
    }

    /// A model over `projects` in exactly that ledger row order, with
    /// `hidden` naming the hidden rows (which may sit anywhere in the order —
    /// the ledger is a single, unpartitioned sequence, SPEC §27.1).
    private static func makeModel(
        _ projects: [TestProjectState], hidden: [ProjectID] = []
    ) -> TestWorkspaceModel {
        TestWorkspaceModel(TestWorkspaceState(
            projects: Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) }),
            projectOrder: projects.map(\.id),
            hiddenProjectIDs: Set(hidden),
            focusedProject: projects.first { !hidden.contains($0.id) }?.id))
    }

    private static func deadline(_ year: Int, _ month: Int, _ day: Int) -> ProjectDeadline {
        ProjectDeadline(year: year, month: month, day: day)!
    }

    // MARK: Default & persistence (SPEC §24.4)

    @Test func sortStateDefaultsToManual() {
        let model = Self.makeModel([Self.makeProject(name: "only")])
        #expect(model.projectSortState == .manual)
    }

    @Test func sortStatePersistsThroughSaveRestore() throws {
        let alpha = Self.makeProject(name: "alpha")
        let beta = Self.makeProject(name: "beta")
        let model = Self.makeModel([alpha, beta])
        model.setProjectSortState(.deadline)

        let data = try JSONEncoder().encode(model.state)
        let decoded = try JSONDecoder().decode(TestWorkspaceState.self, from: data)
        #expect(decoded.sortState == .deadline)
    }

    @Test func aSaveWithoutASortStateDecodesAsManual() throws {
        let model = Self.makeModel([Self.makeProject(name: "alpha")])
        let json = String(decoding: try JSONEncoder().encode(model.state), as: UTF8.self)
            .replacingOccurrences(of: "\"sortState\":\"manual\"", with: "\"sortState\":\"bogus\"")
        let decoded = try JSONDecoder().decode(TestWorkspaceState.self, from: Data(json.utf8))
        // A corrupt (or missing) stored value means the default: manual.
        #expect(decoded.sortState == .manual)
    }

    @Test func loadReassertsAnActiveSortState() throws {
        // A save can carry a stale order next to an active sort state (e.g.
        // written by an older build). Load is a re-sort trigger (SPEC §24.4):
        // the persisted state re-asserts its order on decode.
        let low = Self.makeProject(name: "low")
        let high = Self.makeProject(name: "high")
        let model = Self.makeModel([low, high])
        model.setProjectPriority(low.id, to: .low)
        model.setProjectPriority(high.id, to: .high)

        // Encoded in manual order (low before high), then the stored state is
        // flipped to priority without touching the stored row order.
        let json = String(decoding: try JSONEncoder().encode(model.state), as: UTF8.self)
            .replacingOccurrences(of: "\"sortState\":\"manual\"", with: "\"sortState\":\"priority\"")
        let decoded = try JSONDecoder().decode(TestWorkspaceState.self, from: Data(json.utf8))

        #expect(decoded.sortState == .priority)
        #expect(decoded.projectOrder == [high.id, low.id])
    }

    // MARK: Fixed key directions, stability, all rows (SPEC §24.4)

    @Test func nextKeyOrdersMyselfExternalEventUnsetStable() {
        let unset = Self.makeProject(name: "unset")
        let event = Self.makeProject(name: "event")
        let external1 = Self.makeProject(name: "external-1")
        let myself = Self.makeProject(name: "myself")
        let external2 = Self.makeProject(name: "external-2")
        let model = Self.makeModel([unset, event, external1, myself, external2])

        model.setProjectNextTrigger(event.id, to: .event)
        model.setProjectNextTrigger(external1.id, to: .externalPerson)
        model.setProjectNextTrigger(myself.id, to: .myself)
        model.setProjectNextTrigger(external2.id, to: .externalPerson)

        // myself → external → event → unset; the two externals keep their
        // current relative order (stable).
        #expect(model.setProjectSortState(.next))
        #expect(model.state.projectOrder
                == [myself.id, external1.id, external2.id, event.id, unset.id])
    }

    @Test func showKeyOrdersVisibleAboveHiddenStable() {
        let hidden1 = Self.makeProject(name: "hidden-1")
        let visible1 = Self.makeProject(name: "visible-1")
        let hidden2 = Self.makeProject(name: "hidden-2")
        let visible2 = Self.makeProject(name: "visible-2")
        let model = Self.makeModel(
            [hidden1, visible1, hidden2, visible2],
            hidden: [hidden1.id, hidden2.id])

        // visible → hidden over the whole ledger, each block keeping its
        // current relative order (stable).
        #expect(model.setProjectSortState(.show))
        #expect(model.state.projectOrder
                == [visible1.id, visible2.id, hidden1.id, hidden2.id])
        #expect(model.state.ordinal(of: visible1.id) == 1)
        #expect(model.state.ordinal(of: visible2.id) == 2)
    }

    // MARK: Immediate re-sort on value change & creation (SPEC §24.4)

    @Test func cellValueChangesResortImmediatelyWhileAKeyStateIsActive() {
        let alpha = Self.makeProject(name: "alpha")
        let beta = Self.makeProject(name: "beta")
        let gamma = Self.makeProject(name: "gamma")
        let model = Self.makeModel([alpha, beta, gamma])
        model.setProjectPriority(beta.id, to: .high)
        #expect(model.setProjectSortState(.priority))
        #expect(model.state.projectOrder == [beta.id, alpha.id, gamma.id])

        // While the priority state is active, a priority change re-sorts on
        // its own — no separate act needed. gamma (newly high) ties with beta
        // and slots after it (stable), ahead of the unset alpha.
        model.setProjectPriority(gamma.id, to: .high)
        #expect(model.state.projectOrder == [beta.id, gamma.id, alpha.id])

        // A non-key change (here: a deadline, while sorting by priority)
        // leaves the order alone — the re-sort is stable, so nothing moves.
        model.setProjectDeadline(alpha.id, to: Self.deadline(2026, 8, 20))
        #expect(model.state.projectOrder == [beta.id, gamma.id, alpha.id])
    }

    @Test func manualStateNeverResortsOnValueChanges() {
        let alpha = Self.makeProject(name: "alpha")
        let beta = Self.makeProject(name: "beta")
        let model = Self.makeModel([alpha, beta])
        #expect(model.projectSortState == .manual)

        // In manual, value changes never reorder — the human's order is the
        // order.
        model.setProjectPriority(beta.id, to: .high)
        model.setProjectDeadline(beta.id, to: Self.deadline(2026, 1, 1))
        model.setProjectNextTrigger(beta.id, to: .myself)
        #expect(model.state.projectOrder == [alpha.id, beta.id])
    }

    @Test func visibilityChangesResortImmediatelyUnderTheShowKey() {
        let alpha = Self.makeProject(name: "alpha")
        let beta = Self.makeProject(name: "beta")
        let gamma = Self.makeProject(name: "gamma")
        let model = Self.makeModel([alpha, beta, gamma])
        model.setProjectSortState(.show)
        #expect(model.state.projectOrder == [alpha.id, beta.id, gamma.id])

        // Hiding the top row is a value change of the show key: the row
        // re-sorts below the visible ones immediately.
        model.beginProjectList()
        _ = model.toggleProjectListVisibility(alpha.id, savingOutgoingPaneTree: .init())
        #expect(model.state.projectOrder == [beta.id, gamma.id, alpha.id])
        #expect(model.state.hiddenProjectIDs == [alpha.id])
    }

    @Test func creationInsertsAtTheStableSortPositionWhileSorted() {
        let base = Date(timeIntervalSince1970: 0)
        let high = Self.makeProject(name: "high")
        let medium = Self.makeProject(name: "medium", at: 1)
        let model = Self.makeModel([high, medium])
        model.setProjectPriority(high.id, to: .high)
        model.setProjectPriority(medium.id, to: .medium)
        model.setProjectSortState(.priority)
        #expect(model.state.projectOrder == [high.id, medium.id])

        // A new (unset-priority) row inserted right below the top row lands
        // at its stable-sort position instead: below every set priority.
        var state = model.state
        let fresh = TestProjectState(
            id: ProjectID(), name: "fresh", paneTree: .init(view: TestPane()),
            createdAt: base.addingTimeInterval(2))
        state.insertProject(fresh, after: high.id)
        #expect(state.projectOrder == [high.id, medium.id, fresh.id])

        // The same insert in manual stays exactly where it was inserted.
        var manual = model.state
        manual.setSortState(.manual)
        manual.insertProject(fresh, after: high.id)
        #expect(manual.projectOrder == [high.id, fresh.id, medium.id])
    }

    // MARK: Sort bar movement (SPEC §24.5)

    @Test func barOrderListsTheFiveStatesManualFirst() {
        #expect(ProjectSortState.barOrder
                == [.manual, .next, .show, .deadline, .priority])
    }

    @Test func barMovementStepsLeftRightAndClampsAtTheEnds() {
        // One step right/left along the fixed bar order.
        #expect(ProjectSortState.manual.movedInBar(by: 1) == .next)
        #expect(ProjectSortState.show.movedInBar(by: 1) == .deadline)
        #expect(ProjectSortState.show.movedInBar(by: -1) == .next)

        // The ends absorb: there is nothing past manual or priority.
        #expect(ProjectSortState.manual.movedInBar(by: -1) == .manual)
        #expect(ProjectSortState.priority.movedInBar(by: 1) == .priority)

        // Larger deltas clamp rather than wrap.
        #expect(ProjectSortState.next.movedInBar(by: 10) == .priority)
        #expect(ProjectSortState.deadline.movedInBar(by: -10) == .manual)
    }

    // MARK: Manual handover (SPEC §24.5)

    @Test func selectingManualInheritsTheCurrentDisplayOrder() {
        let low = Self.makeProject(name: "low")
        let high = Self.makeProject(name: "high")
        let medium = Self.makeProject(name: "medium")
        let model = Self.makeModel([low, high, medium])
        model.setProjectPriority(low.id, to: .low)
        model.setProjectPriority(high.id, to: .high)
        model.setProjectPriority(medium.id, to: .medium)
        model.setProjectSortState(.priority)
        #expect(model.state.projectOrder == [high.id, medium.id, low.id])

        // Selecting manual on the sort bar inherits the sorted display order
        // as the manual order — the rows stay put …
        #expect(!model.setProjectSortState(.manual))
        #expect(model.projectSortState == .manual)
        #expect(model.state.projectOrder == [high.id, medium.id, low.id])

        // … and later value changes no longer reorder anything.
        model.setProjectPriority(low.id, to: .high)
        #expect(model.state.projectOrder == [high.id, medium.id, low.id])
    }
}
