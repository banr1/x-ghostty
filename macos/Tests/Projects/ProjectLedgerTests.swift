import Foundation
import Testing
@testable import XGhostty

/// A value-type pane element standing in for `XGhostty.SurfaceView`, which
/// cannot be constructed without a live XGhostty app. The generic model layer
/// runs the exact same code for both element types, so these tests exercise
/// the real ledger judgment logic (SPEC §26–27) with real leaves in the trees.
private struct TestPane: Codable, Identifiable, Equatable {
    let id: UUID
    init(id: UUID = UUID()) { self.id = id }
}

private typealias TestProjectState = ProjectStateOf<TestPane>
private typealias TestWorkspaceState = WorkspaceStateOf<TestPane>

/// Tests for the ledger inversion (SPEC §26.3, §27.1): the list's single row
/// order over every project — hidden ones included — is the source of truth,
/// the on-screen arrangement is a projection re-derived from (row order,
/// hidden set, layout type), ordinals are the visible rows counted from the
/// top, and the row order, column order, and layout type persist and restore.
struct ProjectLedgerTests {
    private static func makeProject(name: String, at date: Date) -> TestProjectState {
        TestProjectState(
            id: ProjectID(), name: name, paneTree: .init(view: TestPane()), createdAt: date)
    }

    /// A state with `count` projects in ledger rows a, b, c, …, all visible,
    /// the first focused.
    private static func makeState(_ count: Int) -> (state: TestWorkspaceState, ids: [ProjectID]) {
        let base = Date(timeIntervalSince1970: 0)
        let projects = (0..<count).map {
            makeProject(name: "p\($0)", at: base.addingTimeInterval(Double($0)))
        }
        let ids = projects.map(\.id)
        let state = TestWorkspaceState(
            projects: Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) }),
            projectOrder: ids,
            focusedProject: ids.first)
        return (state, ids)
    }

    private static func roundTrip(_ state: TestWorkspaceState) throws -> TestWorkspaceState {
        let data = try JSONEncoder().encode(state)
        return try JSONDecoder().decode(TestWorkspaceState.self, from: data)
    }

    /// Encodes `state`, removes the given top-level keys from the JSON, and
    /// decodes the result — a save written before those fields existed.
    private static func decodeDropping(
        _ keys: [String], from state: TestWorkspaceState
    ) throws -> TestWorkspaceState {
        let data = try JSONEncoder().encode(state)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in keys { object.removeValue(forKey: key) }
        let stripped = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(TestWorkspaceState.self, from: stripped)
    }

    // MARK: One unpartitioned row order (SPEC §27.1)

    @Test func rowsAreAllProjectsInOneUnpartitionedOrder() {
        // Hide the *middle* row: it keeps its position between the visible
        // rows — the list is never partitioned into visible-then-hidden.
        var (state, ids) = Self.makeState(3)
        state.setProjectHidden(ids[1], true)

        let rows = state.projectListRows
        #expect(rows.map(\.id) == ids)
        #expect(Set(rows.map(\.id)) == Set(state.projects.keys))
        #expect(rows.map(\.isHidden) == [false, true, false])
        #expect(state.projectOrder == ids)
    }

    @Test func ordinalsAreVisibleRowsCountedFromTheTopSkippingHidden() {
        var (state, ids) = Self.makeState(4)
        state.setProjectHidden(ids[1], true)

        // p0 p1(hidden) p2 p3 → ordinals 1, –, 2, 3.
        #expect(state.projectListRows.map(\.ordinal) == [1, nil, 2, 3])
        #expect(state.ordinal(of: ids[0]) == 1)
        #expect(state.ordinal(of: ids[1]) == nil)
        #expect(state.ordinal(of: ids[2]) == 2)
        #expect(state.visibleProjectID(ordinal: 2) == ids[2])
        #expect(state.visibleProjectIDs == [ids[0], ids[2], ids[3]])
    }

    // MARK: Row reorder persists and restores (SPEC §27.1)

    @Test func moveProjectRowReordersAndSurvivesARoundTrip() throws {
        var (state, ids) = Self.makeState(3)
        state.setProjectHidden(ids[2], true)

        // Move the last row to the top; the hidden row rides along like any
        // other row.
        state.moveProjectRow(ids[2], to: 0)
        #expect(state.projectOrder == [ids[2], ids[0], ids[1]])
        // Ordinals follow the visible rows of the new order.
        #expect(state.ordinal(of: ids[0]) == 1)
        #expect(state.ordinal(of: ids[1]) == 2)
        #expect(state.ordinal(of: ids[2]) == nil)

        let decoded = try Self.roundTrip(state)
        #expect(decoded.projectOrder == [ids[2], ids[0], ids[1]])
        #expect(decoded.hiddenProjectIDs == [ids[2]])
    }

    @Test func applyProjectOrderRequiresAPermutationAndRelayouts() {
        var (state, ids) = Self.makeState(3)

        // A non-permutation is rejected.
        #expect(state.applyProjectOrder([ids[0], ids[1]]) == false)
        #expect(state.applyProjectOrder([ids[0], ids[1], ProjectID()]) == false)
        #expect(state.projectOrder == ids)

        // A permutation applies, and the arrangement follows the new order.
        #expect(state.applyProjectOrder([ids[2], ids[1], ids[0]]) == true)
        #expect(state.projectOrder == [ids[2], ids[1], ids[0]])
        #expect(state.canonicalProjectTree.map(\.id) == [ids[2], ids[1], ids[0]])
    }

    // MARK: Column order persists and restores (SPEC §27.1)

    @Test func defaultColumnOrderIsVisibilityTitlePriorityDeadlineNextTriggerNote() throws {
        let (state, _) = Self.makeState(1)
        #expect(state.listColumnOrder == [
            .visibility, .title, .priority, .deadline, .nextTrigger, .note,
        ])
        // A save without the key — written before the column order existed —
        // decodes to the default.
        let decoded = try Self.decodeDropping(["listColumnOrder"], from: state)
        #expect(decoded.listColumnOrder == ProjectListColumn.defaultOrder)
    }

    @Test func columnOrderRoundTripsAndNormalizesCorruptSaves() throws {
        var (state, _) = Self.makeState(1)
        let custom: [ProjectListColumn] = [.title, .note, .visibility, .priority, .deadline, .nextTrigger]
        state.listColumnOrder = custom

        let decoded = try Self.roundTrip(state)
        #expect(decoded.listColumnOrder == custom)

        // Repair: duplicates collapse to their first occurrence and missing
        // columns append in default order.
        #expect(ProjectListColumn.normalizedOrder([.note, .note, .title])
            == [.note, .title, .visibility, .priority, .deadline, .nextTrigger])
        #expect(ProjectListColumn.normalizedOrder([]) == ProjectListColumn.defaultOrder)
    }

    // MARK: Layout type persists with the wide/row-major default (SPEC §26.4)

    @Test func layoutTypeDefaultsToWideRowMajorWhenNothingIsSaved() throws {
        let (state, _) = Self.makeState(2)
        #expect(state.layoutType == .default)
        #expect(ProjectLayoutType.default == ProjectLayoutType(shape: .wide, orientation: .rowMajor))

        let decoded = try Self.decodeDropping(["layoutType"], from: state)
        #expect(decoded.layoutType == .default)
    }

    @Test func chosenLayoutTypeRoundTrips() throws {
        var (state, ids) = Self.makeState(3)
        state.layoutType = ProjectLayoutType(shape: .tall, orientation: .columnMajor)
        state.relayout()

        let decoded = try Self.roundTrip(state)
        #expect(decoded.layoutType == ProjectLayoutType(shape: .tall, orientation: .columnMajor))
        // The restored arrangement is the remembered type's projection over
        // the visible rows.
        #expect(decoded.canonicalProjectTree.root
            == decoded.layoutType.tree(over: ids).root)
    }

    // MARK: The arrangement is a projection (SPEC §26.3)

    @Test func arrangementReDerivesFromTheLedgerOnEveryChangeAndOnRestore() throws {
        var (state, ids) = Self.makeState(4)
        let type = state.layoutType
        #expect(state.canonicalProjectTree.root == type.tree(over: ids).root)

        // Hiding re-derives over the remaining visible rows.
        state.setProjectHidden(ids[1], true)
        #expect(state.canonicalProjectTree.root
            == type.tree(over: [ids[0], ids[2], ids[3]]).root)

        // Showing re-derives with the row back in place.
        state.setProjectHidden(ids[1], false)
        #expect(state.canonicalProjectTree.root == type.tree(over: ids).root)

        // Removing a row re-derives without it.
        state.removeProject(ids[3])
        #expect(state.canonicalProjectTree.root
            == type.tree(over: [ids[0], ids[1], ids[2]]).root)

        // And a decode rebuilds the projection from the ledger alone.
        let decoded = try Self.roundTrip(state)
        #expect(decoded.canonicalProjectTree.root
            == type.tree(over: [ids[0], ids[1], ids[2]]).root)
    }

    @Test func insertProjectEntersBelowTheAnchorRowAndHiddenAtTheCap() {
        var (state, ids) = Self.makeState(3)
        let base = Date(timeIntervalSince1970: 100)

        // Below the anchor row, visible while there is room.
        let inserted = Self.makeProject(name: "new", at: base)
        state.insertProject(inserted, after: ids[0])
        #expect(state.projectOrder == [ids[0], inserted.id, ids[1], ids[2]])
        #expect(state.isProjectHidden(inserted.id) == false)

        // At the cap (9 visible), a new row comes in hidden.
        var (full, fullIDs) = Self.makeState(TestWorkspaceState.maxVisibleProjects)
        let tenth = Self.makeProject(name: "tenth", at: base)
        full.insertProject(tenth, after: fullIDs.last)
        #expect(full.projectOrder.count == 10)
        #expect(full.isProjectHidden(tenth.id) == true)
        #expect(full.visibleProjectCount == TestWorkspaceState.maxVisibleProjects)
    }
}
