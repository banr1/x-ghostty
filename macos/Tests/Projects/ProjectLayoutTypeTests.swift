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

/// Tests for the layout types (SPEC §26, must 102): slot computation for every
/// visible count 1–24 across wide/tall × row-/column-major with the kind
/// weights, per-count exact-match collapsing of the choice set,
/// orientation-driven assignment of the visible projects (Core → Side) with
/// ordinals following, the saved pedestal migration, and auto-apply of the
/// remembered type on visible-count and visible-kind changes (with no change
/// for operations preserving both). Persistence and the wide/row-major default
/// are covered in `ProjectLedgerTests`.
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

    @Test func tierCountsAttachTheLeftoverToTheTrailingTiers() {
        // Rows (wide) / columns (tall) = the integer nearest √n; the
        // indivisible leftover goes one each to the *trailing* tiers, so the
        // leading tiers hold fewer, wider slots — n=8 is 2+3+3 from the top.
        let expected: [[Int]] = [
            [1], [2], [1, 2], [2, 2], [2, 3], [3, 3], [2, 2, 3], [2, 3, 3], [3, 3, 3],
            [3, 3, 4], [3, 4, 4], [4, 4, 4], [3, 3, 3, 4], [3, 3, 4, 4], [3, 4, 4, 4],
            [4, 4, 4, 4], [4, 4, 4, 5], [4, 4, 5, 5], [4, 5, 5, 5], [5, 5, 5, 5],
            [4, 4, 4, 4, 5], [4, 4, 4, 5, 5], [4, 4, 5, 5, 5], [4, 5, 5, 5, 5],
        ]
        for (n, tiers) in zip(1...24, expected) {
            #expect(ProjectLayoutType.tierCounts(n) == tiers, "n=\(n)")
        }
    }

    // MARK: Slot computation for every visible count (SPEC §26.1)

    /// The wide-shape frames in row-major order, computed here from the
    /// Essence definition (equal row heights, equal in-row widths, dealt from
    /// the top), independently of the production slot builder.
    private static func expectedWideFrames(_ n: Int) -> [CGRect] {
        let rows = ProjectLayoutType.tierCounts(n)
        let rowHeight = 1.0 / Double(rows.count)
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
        for n in 1...24 {
            let type = ProjectLayoutType(shape: .wide, orientation: .rowMajor)
            #expect(Self.approxAll(
                type.slotFrames(forVisibleCount: n), Self.expectedWideFrames(n)), "n=\(n)")
        }
    }

    @Test func tallIsTheExactTransposeOfWide() {
        // Transposing swaps rows↔columns AND row-major↔column-major, so the
        // tall/column-major ordinal sequence is the transposed wide/row-major
        // one, and vice versa.
        for n in 1...24 {
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
        // column top→bottom). Concrete pin at n=5 (rows 2+3): row-major runs
        // the top pair then the bottom trio; column-major starts down the
        // left column (top-left, bottom-left) before moving right.
        for n in 1...24 {
            let row = ProjectLayoutType(shape: .wide, orientation: .rowMajor)
                .slotFrames(forVisibleCount: n)
            let column = ProjectLayoutType(shape: .wide, orientation: .columnMajor)
                .slotFrames(forVisibleCount: n)
            #expect(Set(row.map { "\($0)" }) == Set(column.map { "\($0)" }), "n=\(n)")
        }

        let column5 = ProjectLayoutType(shape: .wide, orientation: .columnMajor)
            .slotFrames(forVisibleCount: 5)
        #expect(Self.approxAll(column5, [
            CGRect(x: 0, y: 0, width: 0.5, height: 0.5),
            CGRect(x: 0, y: 0.5, width: 1.0 / 3, height: 0.5),
            CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
            CGRect(x: 1.0 / 3, y: 0.5, width: 1.0 / 3, height: 0.5),
            CGRect(x: 2.0 / 3, y: 0.5, width: 1.0 / 3, height: 0.5),
        ]))
    }

    @Test func aSingleProjectFillsTheWholeAreaWhateverItsKind() {
        for type in ProjectLayoutType.all {
            for kind in ProjectKind.allCases {
                #expect(Self.approxAll(
                    type.slotFrames(forKinds: [kind]), [CGRect(x: 0, y: 0, width: 1, height: 1)]))
            }
        }
    }

    // MARK: Kind weights (SPEC §26.1)

    /// Every mix of Core then Side over `n` projects: the placement order
    /// always runs Core first, so this is every arrangement the model can ask
    /// for at `n`.
    private static func kindMixes(_ n: Int) -> [[ProjectKind]] {
        (0...n).map { sides in
            Array(repeating: .core, count: n - sides) + Array(repeating: .side, count: sides)
        }
    }

    @Test func aSideIsHalfTheWidthOfACoreInTheSameRow() {
        // Two projects share one row: Core 2/3, Side 1/3.
        let wide = ProjectLayoutType(shape: .wide, orientation: .rowMajor)
        #expect(Self.approxAll(wide.slotFrames(forKinds: [.core, .side]), [
            CGRect(x: 0, y: 0, width: 2.0 / 3, height: 1),
            CGRect(x: 2.0 / 3, y: 0, width: 1.0 / 3, height: 1),
        ]))

        // Rows 2+3 (n=5) with the Sides last: the top row is all Core at equal
        // widths, and the bottom row splits 1 : ½ : ½.
        #expect(Self.approxAll(wide.slotFrames(forKinds: [.core, .core, .core, .side, .side]), [
            CGRect(x: 0, y: 0, width: 0.5, height: 0.5),
            CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
            CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5),
            CGRect(x: 0.5, y: 0.5, width: 0.25, height: 0.5),
            CGRect(x: 0.75, y: 0.5, width: 0.25, height: 0.5),
        ]))
    }

    @Test func aRowOfOnlySidesSharesItsWidthEqually() {
        let wide = ProjectLayoutType(shape: .wide, orientation: .rowMajor)
        #expect(Self.approxAll(wide.slotFrames(forKinds: [.side, .side]), [
            CGRect(x: 0, y: 0, width: 0.5, height: 1),
            CGRect(x: 0.5, y: 0, width: 0.5, height: 1),
        ]))
    }

    @Test func aSideIsHalfTheHeightOfACoreInTheSameColumn() {
        let tall = ProjectLayoutType(shape: .tall, orientation: .columnMajor)
        #expect(Self.approxAll(tall.slotFrames(forKinds: [.core, .side]), [
            CGRect(x: 0, y: 0, width: 1, height: 2.0 / 3),
            CGRect(x: 0, y: 2.0 / 3, width: 1, height: 1.0 / 3),
        ]))
    }

    @Test func weightsHoldInEveryTierForEveryCountAndMix() {
        // Independently of the production share arithmetic: wide rows keep
        // equal heights and tall columns equal widths; within a tier, every
        // slot's length over its kind's weight is one constant, and the tier
        // covers the whole length.
        for n in 1...24 {
            for kinds in Self.kindMixes(n) {
                for type in ProjectLayoutType.all {
                    let frames = type.slotFrames(forKinds: kinds)
                    #expect(frames.count == n)
                    let tiers = Dictionary(grouping: frames.indices) { index -> Int in
                        let origin = type.shape == .wide ? frames[index].minY : frames[index].minX
                        return Int((origin * 1_000_000).rounded())
                    }
                    #expect(tiers.count == ProjectLayoutType.tierCounts(n).count)
                    #expect(tiers.values.map(\.count).sorted()
                        == ProjectLayoutType.tierCounts(n).sorted())
                    for indices in tiers.values {
                        let lengths = indices.map {
                            type.shape == .wide ? frames[$0].width : frames[$0].height
                        }
                        let across = indices.map {
                            type.shape == .wide ? frames[$0].height : frames[$0].width
                        }
                        let perWeight = zip(indices, lengths).map { index, length in
                            length / (kinds[index] == .core ? 1.0 : 0.5)
                        }
                        #expect(abs(lengths.reduce(0, +) - 1) < 1e-9, "n=\(n) \(type.id)")
                        #expect(perWeight.allSatisfy { abs($0 - perWeight[0]) < 1e-9 }, "n=\(n) \(type.id)")
                        #expect(across.allSatisfy {
                            abs($0 - 1.0 / Double(tiers.count)) < 1e-9
                        }, "n=\(n) \(type.id)")
                    }
                }
            }
        }
    }

    @Test func tallIsTheTransposeOfWideWithKindsToo() {
        for n in 1...24 {
            for kinds in Self.kindMixes(n) {
                let tallColumn = ProjectLayoutType(shape: .tall, orientation: .columnMajor)
                let wideRow = ProjectLayoutType(shape: .wide, orientation: .rowMajor)
                #expect(Self.approxAll(
                    tallColumn.slotFrames(forKinds: kinds),
                    Self.transposed(wideRow.slotFrames(forKinds: kinds))), "n=\(n)")
            }
        }
    }

    /// The rectangles a tree realizes on the unit square, by leaf id.
    private static func frames(
        of node: SplitTree<ProjectRef>.Node, in rect: CGRect
    ) -> [ProjectID: CGRect] {
        switch node {
        case .leaf(let ref):
            return [ref.id: rect]
        case .split(let split):
            let first: CGRect
            let second: CGRect
            switch split.direction {
            case .horizontal:
                let width = rect.width * split.ratio
                first = CGRect(x: rect.minX, y: rect.minY, width: width, height: rect.height)
                second = CGRect(
                    x: rect.minX + width, y: rect.minY, width: rect.width - width, height: rect.height)
            case .vertical:
                let height = rect.height * split.ratio
                first = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: height)
                second = CGRect(
                    x: rect.minX, y: rect.minY + height, width: rect.width, height: rect.height - height)
            }
            return frames(of: split.left, in: first).merging(frames(of: split.right, in: second)) { a, _ in a }
        }
    }

    @Test func theTreeRealizesTheSlotFramesForEveryTypeCountAndMix() throws {
        // The tree the view renders is the same geometry the slot computation
        // states: the k-th id lands on the k-th frame.
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        for n in 1...24 {
            for kinds in Self.kindMixes(n) {
                let ids = (0..<n).map { _ in ProjectID() }
                for type in ProjectLayoutType.all {
                    let root = try #require(type.tree(over: ids, kinds: kinds).root)
                    let realized = Self.frames(of: root, in: unit)
                    let expected = type.slotFrames(forKinds: kinds)
                    #expect(Self.approxAll(ids.map { realized[$0] ?? .zero }, expected), "n=\(n) \(type.id)")
                }
            }
        }
    }

    // MARK: Exact-match collapsing of the choice set (SPEC §26.2)

    @Test func choiceSetsCollapseExactMatchesPerCount() {
        let wideRow = ProjectLayoutType(shape: .wide, orientation: .rowMajor)
        let wideColumn = ProjectLayoutType(shape: .wide, orientation: .columnMajor)
        let tallRow = ProjectLayoutType(shape: .tall, orientation: .rowMajor)
        let tallColumn = ProjectLayoutType(shape: .tall, orientation: .columnMajor)
        // n=1: every type is the same single slot — nothing to choose.
        #expect(ProjectLayoutType.choices(forVisibleCount: 1) == [wideRow])

        // n=2: orientation never changes a 1-tier arrangement.
        #expect(ProjectLayoutType.choices(forVisibleCount: 2) == [wideRow, tallRow])

        // n=3: the full-width tier pins the progression, so wide row-/
        // column-major are identical (as are the tall pair); wide and tall
        // differ in shape.
        #expect(ProjectLayoutType.choices(forVisibleCount: 3) == [wideRow, tallRow])
        #expect(wideColumn.representative(forVisibleCount: 3) == wideRow)
        #expect(tallColumn.representative(forVisibleCount: 3) == tallRow)

        // n=9: the 3×3 grid is one shape, but the two ordinal progressions
        // stay apart (wide/row-major absorbs tall/row-major, wide/column-major
        // absorbs tall/column-major).
        let nine = ProjectLayoutType.choices(forVisibleCount: 9)
        #expect(nine == [wideRow, wideColumn])
        #expect(tallRow.representative(forVisibleCount: 9) == wideRow)
        #expect(tallColumn.representative(forVisibleCount: 9) == wideColumn)
    }

    @Test func aSideKeepsTheShapesApartWhereTheyWouldCollapse() {
        // Nine projects with a Side: half the width and half the height are
        // different arrangements, so every shape × orientation is a choice
        // the human can actually reach.
        let kinds: [ProjectKind] = Array(repeating: .core, count: 8) + [.side]
        #expect(ProjectLayoutType.choices(forKinds: kinds) == ProjectLayoutType.all)
        for type in ProjectLayoutType.all {
            #expect(type.representative(forKinds: kinds) == type)
        }
    }

    @Test func noPedestalAmongTheChoices() {
        #expect(Set(ProjectLayoutType.all.map(\.shape)) == [.wide, .tall])
        #expect(ProjectLayoutType.Shape.allCases.map(\.rawValue) == ["wide", "tall"])
        #expect(ProjectLayoutType.all.count == 4)
    }

    // MARK: The saved pedestal migration (SPEC §26.4)

    @Test func aSavedPedestalReadsAsWideKeepingItsOrientation() throws {
        for orientation in ["rowMajor", "columnMajor"] {
            let json = Data(#"{"shape":"pedestal","orientation":"\#(orientation)"}"#.utf8)
            let decoded = try JSONDecoder().decode(ProjectLayoutType.self, from: json)
            #expect(decoded.shape == .wide)
            #expect(decoded.orientation.rawValue == orientation)
        }
    }

    @Test func aWorkspaceSavedOnPedestalComesBackWideWithItsOrientation() throws {
        let (model, ids, _) = Self.makeModel(3, type: .default)
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(model.state)) as? [String: Any])
        object["layoutType"] = ["shape": "pedestal", "orientation": "columnMajor"]
        let decoded = try JSONDecoder().decode(
            TestWorkspaceState.self, from: JSONSerialization.data(withJSONObject: object))

        let expected = ProjectLayoutType(shape: .wide, orientation: .columnMajor)
        #expect(decoded.layoutType == expected)
        #expect(decoded.canonicalProjectTree.root == expected.tree(over: ids).root)

        // What it writes back is the plain current spelling.
        let rewritten = try JSONEncoder().encode(expected)
        #expect(try JSONDecoder().decode(ProjectLayoutType.self, from: rewritten) == expected)
    }

    @Test func anUnknownShapeIsCorruptAndFallsBackToTheDefaultType() throws {
        let json = Data(#"{"shape":"hexagon","orientation":"rowMajor"}"#.utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ProjectLayoutType.self, from: json)
        }

        let (model, _, _) = Self.makeModel(2, type: .default)
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(model.state)) as? [String: Any])
        object["layoutType"] = ["shape": "hexagon", "orientation": "columnMajor"]
        let decoded = try JSONDecoder().decode(
            TestWorkspaceState.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.layoutType == .default)
    }

    @Test func choiceSetsMatchTheSlotFrameCollapseForEveryCount() {
        // Two types coincide exactly when their ordered slot frames agree:
        // same arrangement AND same ordinal progression. Collapse `all` by
        // that criterion, keeping the first of each class, independently of
        // the production arrangement key.
        for n in 1...24 {
            var kept: [(type: ProjectLayoutType, frames: [CGRect])] = []
            for type in ProjectLayoutType.all {
                let frames = type.slotFrames(forVisibleCount: n)
                if kept.contains(where: { Self.approxAll($0.frames, frames) }) { continue }
                kept.append((type, frames))
            }
            #expect(ProjectLayoutType.choices(forVisibleCount: n) == kept.map(\.type), "n=\(n)")
        }
    }

    @Test func everyTypeResolvesToAKeptRepresentative() {
        for n in 1...24 {
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

        // Wide/column-major at n=5 (rows 2+3, the leftover on the trailing
        // row): the progression runs down the left column first — row 1
        // top-left, row 2 bottom-left, row 3 top-right, rows 4–5 the rest of
        // the bottom row.
        let five = Self.refs(5)
        let wideColumn = ProjectLayoutType(shape: .wide, orientation: .columnMajor)
            .tree(over: five.map(\.id))
        #expect(wideColumn.root == SplitTree(
            gridRows: [[five[0], five[2]], [five[1], five[3], five[4]]]).root)
    }

    /// A state over rows of `kinds`, in that row order.
    private static func makeState(
        _ kinds: [ProjectKind], type: ProjectLayoutType = .default
    ) -> (state: TestWorkspaceState, ids: [ProjectID]) {
        let base = Date(timeIntervalSince1970: 0)
        let projects = kinds.enumerated().map { i, kind in
            var project = TestProjectState(
                id: ProjectID(), name: "p\(i)",
                paneTree: .init(view: TestPane()),
                createdAt: base.addingTimeInterval(Double(i)))
            project.kind = kind
            return project
        }
        let ids = projects.map(\.id)
        return (TestWorkspaceState(
            projects: Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) }),
            projectOrder: ids,
            focusedProject: ids[0],
            layoutType: type), ids)
    }

    @Test func coreComesBeforeSideEachKindInRowOrder() {
        // Rows: S0 C1 S2 C3 C4. Placement: C1 C3 C4 S0 S2 — the ordinals, the
        // visible-id order and the slots all follow it. The list keeps its rows.
        let (state, ids) = Self.makeState([.side, .core, .side, .core, .core])
        let placed = [ids[1], ids[3], ids[4], ids[0], ids[2]]

        #expect(state.visibleProjectIDs == placed)
        #expect(state.projectOrder == ids)
        #expect(placed.map { state.ordinal(of: $0) } == [1, 2, 3, 4, 5])
        #expect(state.visibleProjectID(ordinal: 1) == ids[1])
        #expect(state.visibleProjectID(ordinal: 4) == ids[0])
        #expect(state.projectOrdinals[ids[2]] == 5)
        #expect(state.visibleProjectKinds == [.core, .core, .core, .side, .side])
        #expect(state.canonicalProjectTree.root
            == state.layoutType.tree(over: placed, kinds: state.visibleProjectKinds).root)

        // The list shows each row its ordinal, in row order.
        #expect(state.projectListRows.map(\.id) == ids)
        #expect(state.projectListRows.map(\.ordinal) == [4, 1, 5, 2, 3])
    }

    @Test func hiddenRowsAreSkippedInThePlacementOrder() {
        var (state, ids) = Self.makeState([.side, .core, .core, .side])
        state.setProjectHidden(ids[1], true)
        #expect(state.visibleProjectIDs == [ids[2], ids[0], ids[3]])
        #expect(state.ordinal(of: ids[1]) == nil)
    }

    @Test func theSlotsAssignCoreThenSideFollowingTheOrientation() {
        // Wide/column-major at n=5 (rows 2+3), three Cores then two Sides: the
        // progression runs down the left column (top-left, bottom-left), then
        // top-right — the Cores — and the bottom row's other two take the
        // Sides.
        let r = Self.refs(5)
        let type = ProjectLayoutType(shape: .wide, orientation: .columnMajor)
        let kinds: [ProjectKind] = [.core, .core, .core, .side, .side]
        let tree = type.tree(over: r.map(\.id), kinds: kinds)
        let leaves = Array(tree.map(\.id))
        #expect(leaves == [r[0].id, r[2].id, r[1].id, r[3].id, r[4].id])
        #expect(Self.approxAll(type.slotFrames(forKinds: kinds), [
            CGRect(x: 0, y: 0, width: 0.5, height: 0.5),
            CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5),
            CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
            CGRect(x: 0.5, y: 0.5, width: 0.25, height: 0.5),
            CGRect(x: 0.75, y: 0.5, width: 0.25, height: 0.5),
        ]))
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

    @Test func aVisibleKindChangeReappliesTheRememberedType() {
        let type = ProjectLayoutType(shape: .tall, orientation: .columnMajor)
        let (model, ids, _) = Self.makeModel(4, type: type)
        let allCore = model.state.canonicalProjectTree.root
        model.beginProjectList()

        // The candidate menu: ids[0] turns Side, so it goes last and the column
        // it lands in divides by weight.
        #expect(model.commitProjectListCandidate(.kind(.side), for: ids[0]))
        let placed = [ids[1], ids[2], ids[3], ids[0]]
        #expect(model.state.visibleProjectIDs == placed)
        #expect(model.state.projectOrder == ids)
        #expect(model.state.canonicalProjectTree.root
            == type.tree(over: placed, kinds: [.core, .core, .core, .side]).root)
        #expect(model.state.canonicalProjectTree.root != allCore)
        #expect(model.state.layoutType == type)

        // Delete returns it to Core: the arrangement follows back.
        #expect(model.deleteProjectListCellValue(.kind, for: ids[0]))
        #expect(model.state.canonicalProjectTree.root == allCore)
    }

    @Test func aHiddenKindChangeLeavesTheArrangementAlone() {
        let (model, ids, _) = Self.makeModel(3, type: .default)
        model.beginProjectList()
        model.toggleProjectListVisibility(ids[2], savingOutgoingPaneTree: .init())
        let before = model.state.canonicalProjectTree.root

        #expect(model.commitProjectListCandidate(.kind(.side), for: ids[2]))
        #expect(model.state.canonicalProjectTree.root == before)
        #expect(model.state.visibleProjectIDs == [ids[0], ids[1]])

        // Showing it brings it back as a Side, placed last and half as wide.
        model.toggleProjectListVisibility(ids[2], savingOutgoingPaneTree: .init())
        #expect(model.state.canonicalProjectTree.root
            == ProjectLayoutType.default.tree(over: ids, kinds: [.core, .core, .side]).root)
    }

    @Test func theKindSurvivesARestoreIntoTheSameArrangement() throws {
        let (state, ids) = Self.makeState(
            [.side, .core, .core], type: ProjectLayoutType(shape: .wide, orientation: .columnMajor))
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(TestWorkspaceState.self, from: data)
        #expect(decoded.visibleProjectIDs == [ids[1], ids[2], ids[0]])
        #expect(decoded.canonicalProjectTree.root == state.canonicalProjectTree.root)
    }

    @Test func theSelectorListsTheChoicesOfTheActualKinds() {
        let (model, _, _) = Self.makeModel(9, type: .default)
        model.beginLayoutSelection()
        #expect(model.layoutTypeChoices == ProjectLayoutType.choices(forVisibleCount: 9))
        model.cancelLayoutSelection()

        var state = model.state
        let last = state.projectOrder[8]
        state.setProjectKind(last, to: .side)
        let mixed = TestWorkspaceModel(state)
        mixed.beginLayoutSelection()
        #expect(mixed.layoutTypeChoices == ProjectLayoutType.all)
        #expect(mixed.currentLayoutTypeChoice == .default)
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
