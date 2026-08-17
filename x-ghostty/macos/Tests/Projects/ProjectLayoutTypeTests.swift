import Foundation
import Testing
@testable import XGhostty

/// A value-type pane element standing in for `XGhostty.SurfaceView`, which
/// cannot be constructed without a live XGhostty app. The generic model layer
/// runs the exact same code for both element types, so these tests exercise
/// the real layout-type judgment logic (SPEC §26) with real leaves in the trees.
private struct TestPane: Codable, Identifiable, Equatable {
    let id: UUID
    init(id: UUID = UUID()) { self.id = id }
}

private typealias TestProjectState = ProjectStateOf<TestPane>
private typealias TestWorkspaceState = WorkspaceStateOf<TestPane>
private typealias TestWorkspaceModel = WorkspaceModelOf<TestPane>

/// Tests for the layout types (SPEC §26, success condition 15): slot
/// computation for every visible count 1–9 across wide/tall/pedestal ×
/// row-/column-major, per-count exact-match collapsing of the choice set,
/// orientation-driven assignment of the list's visible rows with ordinals
/// following, and auto-apply of the remembered type on visible-count changes
/// (with no change for count-preserving operations). Persistence and the
/// wide/row-major default are covered in `ProjectLedgerTests`.
struct ProjectLayoutTypeTests {
    private static func approx(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 1e-9 && abs(a.minY - b.minY) < 1e-9
            && abs(a.width - b.width) < 1e-9 && abs(a.height - b.height) < 1e-9
    }

    private static func approxAll(_ a: [CGRect], _ b: [CGRect]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { approx($0, $1) }
    }

    /// x/y (and width/height) swapped — the wide↔tall transpose.
    private static func transposed(_ frames: [CGRect]) -> [CGRect] {
        frames.map { CGRect(x: $0.minY, y: $0.minX, width: $0.height, height: $0.width) }
    }

    // MARK: The distribution rule (SPEC §26.1)

    @Test func tierCountsDealFromTheTopAsEvenlyAsPossible() {
        // Rows (wide) / columns (tall) = the integer nearest √n; the leftover
        // projects go one each to the leading tiers.
        let expected: [[Int]] = [
            [1], [2], [2, 1], [2, 2], [3, 2], [3, 3], [3, 2, 2], [3, 3, 2], [3, 3, 3],
        ]
        for (n, tiers) in zip(1...9, expected) {
            #expect(ProjectLayoutType.tierCounts(n) == tiers, "n=\(n)")
        }
    }

    // MARK: Slot computation for every visible count (SPEC §26.1)

    /// The wide-shape frames in row-major order, computed here from the
    /// Essence definition (equal row heights, equal in-row widths, dealt from
    /// the top), independently of the production slot builder.
    private static func expectedWideFrames(_ n: Int, height: Double = 1) -> [CGRect] {
        let rows = ProjectLayoutType.tierCounts(n)
        let rowHeight = height / Double(rows.count)
        var frames: [CGRect] = []
        for (row, count) in rows.enumerated() {
            let width = 1.0 / Double(count)
            for cell in 0..<count {
                frames.append(CGRect(
                    x: Double(cell) * width,
                    y: Double(row) * rowHeight,
                    width: width,
                    height: rowHeight))
            }
        }
        return frames
    }

    @Test func wideSlotsMatchTheDefinitionForEveryCount() {
        for n in 1...9 {
            let type = ProjectLayoutType(shape: .wide, orientation: .rowMajor)
            #expect(Self.approxAll(
                type.slotFrames(forVisibleCount: n), Self.expectedWideFrames(n)), "n=\(n)")
        }
    }

    @Test func tallIsTheExactTransposeOfWide() {
        // Transposing swaps rows↔columns AND row-major↔column-major, so the
        // tall/column-major ordinal sequence is the transposed wide/row-major
        // one, and vice versa.
        for n in 1...9 {
            let wideRow = ProjectLayoutType(shape: .wide, orientation: .rowMajor)
            let wideColumn = ProjectLayoutType(shape: .wide, orientation: .columnMajor)
            let tallRow = ProjectLayoutType(shape: .tall, orientation: .rowMajor)
            let tallColumn = ProjectLayoutType(shape: .tall, orientation: .columnMajor)

            #expect(Self.approxAll(
                tallColumn.slotFrames(forVisibleCount: n),
                Self.transposed(wideRow.slotFrames(forVisibleCount: n))), "n=\(n)")
            #expect(Self.approxAll(
                tallRow.slotFrames(forVisibleCount: n),
                Self.transposed(wideColumn.slotFrames(forVisibleCount: n))), "n=\(n)")
        }
    }

    @Test func wideOrientationChangesOnlyTheOrdinalProgression() {
        // The two wide orientations place the same slot set; only the ordinal
        // sequence differs (row-major: top row left→right; column-major: left
        // column top→bottom). Concrete pin at n=3 (rows 2+1): row-major runs
        // top-left, top-right, bottom; column-major runs top-left, bottom,
        // top-right.
        for n in 1...9 {
            let row = ProjectLayoutType(shape: .wide, orientation: .rowMajor)
                .slotFrames(forVisibleCount: n)
            let column = ProjectLayoutType(shape: .wide, orientation: .columnMajor)
                .slotFrames(forVisibleCount: n)
            #expect(Set(row.map { "\($0)" }) == Set(column.map { "\($0)" }), "n=\(n)")
        }

        let column3 = ProjectLayoutType(shape: .wide, orientation: .columnMajor)
            .slotFrames(forVisibleCount: 3)
        #expect(Self.approxAll(column3, [
            CGRect(x: 0, y: 0, width: 0.5, height: 0.5),
            CGRect(x: 0, y: 0.5, width: 1, height: 0.5),
            CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
        ]))
    }

    @Test func pedestalStacksTheTopRuleOverAFullWidthBottom() {
        for n in 2...9 {
            // Row-major: n−1 on top by the wide rule, scaled to t/(t+1) of the
            // height where t is the wide tier count; one full-width bottom slot
            // takes the remaining tier. The bottom slot is always last.
            let rowType = ProjectLayoutType(shape: .pedestal, orientation: .rowMajor)
            let tiers = ProjectLayoutType.tierCounts(n - 1).count
            let scale = Double(tiers) / Double(tiers + 1)
            var expected = Self.expectedWideFrames(n - 1, height: scale)
            expected.append(CGRect(x: 0, y: scale, width: 1, height: 1 - scale))
            #expect(Self.approxAll(rowType.slotFrames(forVisibleCount: n), expected), "n=\(n)")

            // Column-major: the top follows the tall rule (transpose of wide,
            // then y-scaled), with the deepest column deciding the top share.
            let columnType = ProjectLayoutType(shape: .pedestal, orientation: .columnMajor)
            let deepest = ProjectLayoutType.tierCounts(n - 1).max() ?? 1
            let columnScale = Double(deepest) / Double(deepest + 1)
            var columnExpected = Self.transposed(Self.expectedWideFrames(n - 1))
                .map { CGRect(x: $0.minX, y: $0.minY * columnScale,
                              width: $0.width, height: $0.height * columnScale) }
            columnExpected.append(CGRect(x: 0, y: columnScale, width: 1, height: 1 - columnScale))
            #expect(Self.approxAll(columnType.slotFrames(forVisibleCount: n), columnExpected), "n=\(n)")
        }

        // n=1 degenerates to the single full slot for every shape.
        for type in ProjectLayoutType.all {
            #expect(Self.approxAll(
                type.slotFrames(forVisibleCount: 1), [CGRect(x: 0, y: 0, width: 1, height: 1)]))
        }
    }

    // MARK: Exact-match collapsing of the choice set (SPEC §26.2)

    @Test func choiceSetsCollapseExactMatchesPerCount() {
        let wideRow = ProjectLayoutType(shape: .wide, orientation: .rowMajor)
        let wideColumn = ProjectLayoutType(shape: .wide, orientation: .columnMajor)
        let tallRow = ProjectLayoutType(shape: .tall, orientation: .rowMajor)
        let tallColumn = ProjectLayoutType(shape: .tall, orientation: .columnMajor)
        let pedestalRow = ProjectLayoutType(shape: .pedestal, orientation: .rowMajor)
        let pedestalColumn = ProjectLayoutType(shape: .pedestal, orientation: .columnMajor)

        // n=1: every type is the same single slot — nothing to choose.
        #expect(ProjectLayoutType.choices(forVisibleCount: 1) == [wideRow])

        // n=2: orientation never changes a 1-tier arrangement, and the
        // pedestal (1 on top of 1) is exactly the stacked tall pair.
        #expect(ProjectLayoutType.choices(forVisibleCount: 2) == [wideRow, tallRow])

        // n=3: the Essence's own example — pedestal/row-major (2 over 1
        // full-width) coincides with wide/row-major and collapses into it.
        let three = ProjectLayoutType.choices(forVisibleCount: 3)
        #expect(three == [wideRow, wideColumn, tallRow, tallColumn, pedestalColumn])
        #expect(!three.contains(pedestalRow))
        #expect(pedestalRow.representative(forVisibleCount: 3) == wideRow)

        // n=9: the Essence's other example — the 3×3 grid is one shape, but
        // the two ordinal progressions stay apart (wide/row-major absorbs
        // tall/row-major, wide/column-major absorbs tall/column-major).
        let nine = ProjectLayoutType.choices(forVisibleCount: 9)
        #expect(nine == [wideRow, wideColumn, pedestalRow, pedestalColumn])
        #expect(tallRow.representative(forVisibleCount: 9) == wideRow)
        #expect(tallColumn.representative(forVisibleCount: 9) == wideColumn)
    }

    @Test func everyTypeResolvesToAKeptRepresentative() {
        for n in 1...9 {
            let choices = ProjectLayoutType.choices(forVisibleCount: n)
            #expect(!choices.isEmpty)
            for type in ProjectLayoutType.all {
                #expect(choices.contains(type.representative(forVisibleCount: n)),
                        "n=\(n) \(type.id)")
            }
        }
    }

    // MARK: Orientation assignment of the list's visible rows (SPEC §26.1, §26.3)

    private static func refs(_ n: Int) -> [ProjectRef] {
        (0..<n).map { _ in ProjectRef(id: ProjectID()) }
    }

    @Test func rowMajorAssignsTopRowLeftToRight() {
        let r = Self.refs(4)
        let tree = ProjectLayoutType(shape: .wide, orientation: .rowMajor)
            .tree(over: r.map(\.id))
        #expect(tree.root == SplitTree(gridRows: [[r[0], r[1]], [r[2], r[3]]]).root)
    }

    @Test func columnMajorAssignsLeftColumnTopToBottom() {
        let r = Self.refs(4)
        // Tall/column-major: rows 1 and 2 fill the left column top→bottom,
        // rows 3 and 4 the right column.
        let tall = ProjectLayoutType(shape: .tall, orientation: .columnMajor)
            .tree(over: r.map(\.id))
        #expect(tall.root == SplitTree(gridColumns: [[r[0], r[1]], [r[2], r[3]]]).root)

        // Tall/row-major over the same grid: rows 1 and 2 spread across the
        // top (left column's top, right column's top), 3 and 4 across the
        // bottom — the progression, not the shape, changed.
        let tallRow = ProjectLayoutType(shape: .tall, orientation: .rowMajor)
            .tree(over: r.map(\.id))
        #expect(tallRow.root == SplitTree(gridColumns: [[r[0], r[2]], [r[1], r[3]]]).root)

        // Wide/column-major at n=3 (rows 2+1): row 1 top-left, row 2 the
        // full-width bottom, row 3 top-right.
        let three = Self.refs(3)
        let wideColumn = ProjectLayoutType(shape: .wide, orientation: .columnMajor)
            .tree(over: three.map(\.id))
        #expect(wideColumn.root == SplitTree(gridRows: [[three[0], three[2]], [three[1]]]).root)
    }

    @Test func pedestalAssignsTheBottomSlotLast() {
        let r = Self.refs(3)
        let tree = ProjectLayoutType(shape: .pedestal, orientation: .rowMajor)
            .tree(over: r.map(\.id))
        #expect(tree.root == SplitTree(
            stacking: SplitTree(gridRows: [[r[0], r[1]]]),
            over: r[2],
            topRatio: 0.5).root)
    }

    @Test func ordinalsFollowTheListOrderNotTheVisualPosition() {
        // Under tall/column-major, row 2 renders BELOW row 1 in the left
        // column — but the ordinals stay the visible rows counted from the
        // top of the list.
        let base = Date(timeIntervalSince1970: 0)
        let projects = (0..<4).map { i in
            TestProjectState(
                id: ProjectID(), name: "p\(i)",
                paneTree: .init(view: TestPane()),
                createdAt: base.addingTimeInterval(Double(i)))
        }
        let ids = projects.map(\.id)
        let state = TestWorkspaceState(
            projects: Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) }),
            projectOrder: ids,
            focusedProject: ids[0],
            layoutType: ProjectLayoutType(shape: .tall, orientation: .columnMajor))

        #expect(state.canonicalProjectTree.root
            == state.layoutType.tree(over: ids).root)
        #expect(ids.map { state.ordinal(of: $0) } == [1, 2, 3, 4])
        #expect(state.visibleProjectID(ordinal: 2) == ids[1])
    }

    // MARK: Auto-apply of the remembered type (SPEC §26.3)

    private static func makeModel(
        _ count: Int, type: ProjectLayoutType
    ) -> (model: TestWorkspaceModel, ids: [ProjectID], panes: [TestPane]) {
        let base = Date(timeIntervalSince1970: 0)
        let panes = (0..<count).map { _ in TestPane() }
        let projects = panes.enumerated().map { i, pane in
            TestProjectState(
                id: ProjectID(), name: "p\(i)",
                paneTree: .init(view: pane),
                createdAt: base.addingTimeInterval(Double(i)))
        }
        let ids = projects.map(\.id)
        let state = TestWorkspaceState(
            projects: Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) }),
            projectOrder: ids,
            focusedProject: ids[0],
            layoutType: type)
        return (TestWorkspaceModel(state), ids, panes)
    }

    @Test func visibleCountChangesReapplyTheRememberedType() throws {
        let type = ProjectLayoutType(shape: .tall, orientation: .columnMajor)
        let (model, ids, _) = Self.makeModel(4, type: type)

        // Hide (Cmd+Opt+H path): the remaining three re-form in the
        // remembered type.
        try #require(model.hideFocusedProject(savingOutgoingPaneTree: .init()))
        #expect(model.state.layoutType == type)
        #expect(model.state.canonicalProjectTree.root
            == type.tree(over: [ids[1], ids[2], ids[3]]).root)

        // List visibility toggle: showing the row back re-forms with four.
        model.beginProjectList()
        model.toggleProjectListVisibility(ids[0], savingOutgoingPaneTree: .init())
        model.endProjectList()
        #expect(model.state.canonicalProjectTree.root == type.tree(over: ids).root)

        // New project: five visible, same type.
        let extra = TestProjectState(
            id: ProjectID(), name: "extra",
            paneTree: .init(view: TestPane()),
            createdAt: Date(timeIntervalSince1970: 100))
        model.switchFocusedProject(to: ids[3], savingOutgoingPaneTree: .init())
        try model.openNewProject(extra, direction: .right, savingOutgoingPaneTree: .init())
        #expect(model.state.canonicalProjectTree.root
            == type.tree(over: [ids[0], ids[1], ids[2], ids[3], extra.id]).root)

        // Close: back to four, same type.
        #expect(model.closeFocusedProject() != nil)
        #expect(model.state.canonicalProjectTree.root == type.tree(over: ids).root)
        #expect(model.state.layoutType == type)
    }

    @Test func countPreservingOperationsDoNotChangeTheArrangement() {
        let type = ProjectLayoutType(shape: .tall, orientation: .columnMajor)
        let (model, ids, panes) = Self.makeModel(3, type: type)
        let before = model.state.canonicalProjectTree.root

        // Rename, priority, note: ledger rows and visibility untouched.
        model.renameProject(ids[1], to: "renamed")
        model.setProjectPriority(ids[2], to: .high)
        model.setProjectNote(ids[0], to: "note")
        #expect(model.state.canonicalProjectTree.root == before)

        // The terminated-state transition keeps the visible count: the pane
        // stays, the project stays, and the arrangement must not re-form.
        #expect(model.markPaneTerminated(SurfaceID(rawValue: panes[1].id)))
        #expect(model.isProjectTerminated(ids[1]))
        #expect(model.state.canonicalProjectTree.root == before)

        // A row *move* re-derives (the order changed) but keeps the count —
        // and the type still decides the shape.
        #expect(model.moveFocusedProject(.next))
        #expect(model.state.canonicalProjectTree.root
            == type.tree(over: model.state.visibleProjectIDs).root)
    }
}
