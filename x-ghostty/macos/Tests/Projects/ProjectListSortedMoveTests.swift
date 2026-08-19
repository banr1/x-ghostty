import Foundation
import Testing
@testable import XGhostty

/// A value-type pane element standing in for `XGhostty.SurfaceView`, which
/// cannot be constructed without a live XGhostty app. The generic model layer
/// runs the exact same code for both element types, so these tests exercise
/// the real sorted-move approval and sorted-insertion judgment (SPEC §24.5,
/// §27.1).
private struct TestPane: Codable, Identifiable, Equatable {
    let id: UUID
    init(id: UUID = UUID()) { self.id = id }
}

private typealias TestProjectState = ProjectStateOf<TestPane>
private typealias TestWorkspaceState = WorkspaceStateOf<TestPane>
private typealias TestWorkspaceModel = WorkspaceModelOf<TestPane>

/// Tests for row moves and creation under the sort state (SPEC §24.5,
/// §27.1): the approved sorted move inherits the display order as manual and
/// then moves (one call, no half-apply), manual moves stay approval-free
/// through the plain move path, and a Cmd+N creation while a key sort is
/// active lands at the position the stable sort assigns by value.
struct ProjectListSortedMoveTests {
    private static func makeProject(
        name: String,
        priority: ProjectPriority? = nil,
        deadline: ProjectDeadline? = nil,
        at date: Date = Date(timeIntervalSince1970: 0)
    ) -> TestProjectState {
        TestProjectState(
            id: ProjectID(),
            name: name,
            paneTree: .init(view: TestPane()),
            note: "",
            priority: priority,
            deadline: deadline,
            nextTrigger: nil,
            createdAt: date)
    }

    private static func makeListModel(_ projects: [TestProjectState]) -> TestWorkspaceModel {
        var state = TestWorkspaceState(
            projects: Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) }),
            projectOrder: projects.map(\.id),
            focusedProject: projects.first?.id)
        state.relayout()
        let model = TestWorkspaceModel(state)
        model.beginProjectList()
        return model
    }

    // MARK: The approved sorted move (SPEC §24.5)

    @Test func approvalInheritsTheDisplayOrderAsManualAndMoves() {
        let high = Self.makeProject(name: "high", priority: .high)
        let medium = Self.makeProject(
            name: "medium", priority: .medium, at: Date(timeIntervalSince1970: 1))
        let low = Self.makeProject(
            name: "low", priority: .low, at: Date(timeIntervalSince1970: 2))
        let model = Self.makeListModel([low, medium, high])
        model.setProjectSortState(.priority)
        #expect(model.state.projectOrder == [high.id, medium.id, low.id])

        // OK: the sort state returns to manual with the sorted order
        // inherited, and the move applies on top of it.
        #expect(model.approveSortedRowMove(medium.id, by: 1) == 2)
        #expect(model.state.sortState == .manual)
        #expect(model.state.projectOrder == [high.id, low.id, medium.id])

        // Manual from here on: a later value change re-sorts nothing.
        model.setProjectPriority(low.id, to: nil)
        #expect(model.state.projectOrder == [high.id, low.id, medium.id])
    }

    @Test func approvalIsRefusedInManualStateAndWithoutTheSession() {
        let a = Self.makeProject(name: "alpha")
        let b = Self.makeProject(name: "beta", at: Date(timeIntervalSince1970: 1))
        let model = Self.makeListModel([a, b])

        // Manual moves are approval-free: they go through the plain move
        // path, and the approval call refuses so the two cannot blur.
        #expect(model.approveSortedRowMove(a.id, by: 1) == nil)
        #expect(model.state.projectOrder == [a.id, b.id])
        #expect(model.moveProjectListRow(a.id, by: 1) == 1)
        #expect(model.state.projectOrder == [b.id, a.id])

        // No list session: refused even under an active sort.
        model.endProjectList()
        model.setProjectSortState(.priority)
        #expect(model.approveSortedRowMove(a.id, by: 1) == nil)
        #expect(model.state.sortState == .priority)
    }

    @Test func aClampedApprovedMoveStillKeepsTheSwitchToManual() {
        let high = Self.makeProject(name: "high", priority: .high)
        let low = Self.makeProject(
            name: "low", priority: .low, at: Date(timeIntervalSince1970: 1))
        let model = Self.makeListModel([high, low])
        model.setProjectSortState(.priority)

        // The user approved leaving the sort; the edge clamp only means the
        // row had nowhere to go. The order they saw is the order they keep.
        #expect(model.approveSortedRowMove(low.id, by: 1) == nil)
        #expect(model.state.sortState == .manual)
        #expect(model.state.projectOrder == [high.id, low.id])
    }

    // MARK: Creation under an active sort (SPEC §27.1)

    @Test func sortedInsertionLandsAtTheStableSortPosition() throws {
        let early = Self.makeProject(
            name: "early", deadline: ProjectDeadline(parsing: "2026-08-01"))
        let late = Self.makeProject(
            name: "late", deadline: ProjectDeadline(parsing: "2026-08-03"),
            at: Date(timeIntervalSince1970: 1))
        let model = Self.makeListModel([early, late])
        model.setProjectSortState(.deadline)
        #expect(model.state.projectOrder == [early.id, late.id])

        // Anchored at the end, but the active sort governs: the new row's
        // own deadline places it between the two (SPEC §27.1 — the position
        // is the stable sort's consequence, not the anchor's).
        let middle = Self.makeProject(
            name: "middle", deadline: ProjectDeadline(parsing: "2026-08-02"),
            at: Date(timeIntervalSince1970: 2))
        #expect(model.insertProjectFromList(middle, after: late.id))
        #expect(model.state.projectOrder == [early.id, middle.id, late.id])

        // An unset sort key sorts last (SPEC §24.3): a fresh default row
        // lands at the end regardless of its anchor.
        let fresh = Self.makeProject(name: "fresh", at: Date(timeIntervalSince1970: 3))
        #expect(model.insertProjectFromList(fresh, after: early.id))
        #expect(model.state.projectOrder == [early.id, middle.id, late.id, fresh.id])
    }
}
