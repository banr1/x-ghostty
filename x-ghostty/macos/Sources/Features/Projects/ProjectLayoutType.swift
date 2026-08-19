import Foundation

/// A layout type (`SPEC.md` §26): the rule that derives the overall-view
/// arrangement from the visible rows of the project list. Shape × orientation:
///
/// - **wide** — rows = the integer nearest √n; the projects are dealt to the
///   rows as evenly as possible, the leftover attaching to the trailing rows
///   (n=8 is 2+3+3 from the top — the top rows hold fewer, wider slots); row
///   heights and in-row widths are equal.
/// - **tall** — the transpose: columns = nearest √n, the leftover attaching
///   to the trailing columns (the left columns hold fewer slots), equal
///   column widths and in-column heights.
/// - **pedestal** — n−1 projects on top (by the wide rule for row-major, by
///   the tall rule for column-major) plus one full-width project as the
///   bottom row.
///
/// The orientation decides the ordinal progression (Cmd+1–9): row-major runs
/// top row first, left to right; column-major runs left column first, top to
/// bottom. For wide and tall it changes only the progression, never the
/// shape; for pedestal it also picks the top part's rule. The bottom pedestal
/// slot is always last.
///
/// The set is closed by design (user-defined layouts are a declared
/// non-goal), so the definitions live here as data and the geometry as pure
/// functions, verifiable from `XGhosttyTests`. Nothing here knows about the
/// list or the model — the model applies the type to its visible rows and
/// re-derives the canonical tree (`WorkspaceStateOf.relayout()`).
struct ProjectLayoutType: Equatable, Hashable, Codable, Identifiable {
    enum Shape: String, Codable, CaseIterable {
        case wide, tall, pedestal
    }

    enum Orientation: String, Codable, CaseIterable {
        case rowMajor, columnMajor
    }

    var shape: Shape
    var orientation: Orientation

    /// The type used when nothing is saved (`SPEC.md` §26.4).
    static let `default` = ProjectLayoutType(shape: .wide, orientation: .rowMajor)

    /// Every shape × orientation, in canonical enumeration order (shape
    /// first). `choices(forVisibleCount:)` keeps the first of each
    /// collapsed group, so this order also decides the representative.
    static let all: [ProjectLayoutType] = Shape.allCases.flatMap { shape in
        Orientation.allCases.map { ProjectLayoutType(shape: shape, orientation: $0) }
    }

    var id: String { "\(shape.rawValue)-\(orientation.rawValue)" }

    /// A short label for the selector and the docs.
    var label: String {
        let shapeName: String = switch shape {
        case .wide: "wide"
        case .tall: "tall"
        case .pedestal: "pedestal"
        }
        let orientationName: String = switch orientation {
        case .rowMajor: "by rows"
        case .columnMajor: "by columns"
        }
        return "\(shapeName) · \(orientationName)"
    }

    // MARK: Distribution rules

    /// The wide-shape row distribution (`SPEC.md` §26.1): the row count is the
    /// integer nearest √n, and the projects are dealt to the rows as evenly as
    /// possible — the indivisible leftover goes one each to the *trailing*
    /// rows, so the leading rows hold fewer, wider slots (4 = 2+2, 5 = 2+3,
    /// 6 = 3+3, 7 = 2+2+3, 8 = 2+3+3, 9 = 3+3+3). Sorted rows put the
    /// important projects on top, and the top rows are the wide ones. The
    /// tall shape uses the same numbers as its column distribution (the
    /// leading — leftmost — columns hold fewer slots).
    static func tierCounts(_ n: Int) -> [Int] {
        guard n > 0 else { return [] }
        let tiers = max(1, Int(Double(n).squareRoot().rounded()))
        let base = n / tiers
        let extra = n % tiers
        return (0..<tiers).map { $0 >= tiers - extra ? base + 1 : base }
    }

    // MARK: Slots

    /// One slot of an arrangement: its rectangle in the unit square (origin
    /// top-left, y growing downward) and its grid position, which is what the
    /// orientation sorts by. For the pedestal bottom slot `row`/`column` are
    /// past every top slot so it always sorts last.
    struct Slot: Equatable {
        let frame: CGRect
        let row: Int
        let column: Int
    }

    /// The slots for `n` visible projects **in ordinal (assignment) order**:
    /// the k-th slot is where the k-th visible row of the list goes and what
    /// Cmd+(k+1) jumps to. Empty for `n <= 0`.
    func slots(forVisibleCount n: Int) -> [Slot] {
        guard n > 0 else { return [] }
        let unordered: [Slot]
        switch shape {
        case .wide:
            unordered = Self.wideSlots(n, verticalScale: 1)
        case .tall:
            unordered = Self.tallSlots(n, verticalScale: 1)
        case .pedestal:
            guard n > 1 else { return [Slot(frame: CGRect(x: 0, y: 0, width: 1, height: 1), row: 0, column: 0)] }
            let top: [Slot]
            let tiers: Int
            switch orientation {
            case .rowMajor:
                tiers = Self.tierCounts(n - 1).count
                top = Self.wideSlots(n - 1, verticalScale: Double(tiers) / Double(tiers + 1))
            case .columnMajor:
                tiers = Self.tierCounts(n - 1).max() ?? 1
                top = Self.tallSlots(n - 1, verticalScale: Double(tiers) / Double(tiers + 1))
            }
            let topHeight = Double(tiers) / Double(tiers + 1)
            let bottom = Slot(
                frame: CGRect(x: 0, y: topHeight, width: 1, height: 1 - topHeight),
                row: Int.max, column: Int.max)
            unordered = top + [bottom]
        }
        return Self.ordered(unordered, by: orientation)
    }

    /// The slot rectangles for `n` visible projects in ordinal order — the
    /// geometry alone, which is what "arrangement and ordinal progression
    /// coincide" compares (`SPEC.md` §26.1).
    func slotFrames(forVisibleCount n: Int) -> [CGRect] {
        slots(forVisibleCount: n).map(\.frame)
    }

    private static func wideSlots(_ n: Int, verticalScale: Double) -> [Slot] {
        let rows = tierCounts(n)
        let rowHeight = verticalScale / Double(rows.count)
        var slots: [Slot] = []
        for (row, count) in rows.enumerated() {
            let width = 1.0 / Double(count)
            for column in 0..<count {
                slots.append(Slot(
                    frame: CGRect(
                        x: Double(column) * width,
                        y: Double(row) * rowHeight,
                        width: width,
                        height: rowHeight),
                    row: row, column: column))
            }
        }
        return slots
    }

    private static func tallSlots(_ n: Int, verticalScale: Double) -> [Slot] {
        let columns = tierCounts(n)
        let columnWidth = 1.0 / Double(columns.count)
        var slots: [Slot] = []
        for (column, count) in columns.enumerated() {
            let height = verticalScale / Double(count)
            for row in 0..<count {
                slots.append(Slot(
                    frame: CGRect(
                        x: Double(column) * columnWidth,
                        y: Double(row) * height,
                        width: columnWidth,
                        height: height),
                    row: row, column: column))
            }
        }
        return slots
    }

    /// Row-major: top row first, left to right. Column-major: left column
    /// first, top to bottom (`SPEC.md` §26.1). The pedestal bottom slot sorts
    /// last under both because its row and column are `Int.max`.
    private static func ordered(_ slots: [Slot], by orientation: Orientation) -> [Slot] {
        switch orientation {
        case .rowMajor:
            slots.sorted { ($0.row, $0.column) < ($1.row, $1.column) }
        case .columnMajor:
            slots.sorted { ($0.column, $0.row) < ($1.column, $1.row) }
        }
    }

    // MARK: Choices per visible count (SPEC §26.2)

    /// A comparable key of the ordered arrangement, rounded so two rules that
    /// produce the same geometry through different arithmetic still compare
    /// equal.
    private func arrangementKey(forVisibleCount n: Int) -> [[Int]] {
        slotFrames(forVisibleCount: n).map { frame in
            [frame.minX, frame.minY, frame.width, frame.height].map { Int(($0 * 1_000_000).rounded()) }
        }
    }

    /// The selectable types for `n` visible projects: of the 3 shapes × 2
    /// orientations, those whose arrangement **and** ordinal progression
    /// coincide exactly are collapsed into one (the first in `all` order is
    /// kept), and the rest are the choices. E.g. n = 9 keeps wide and tall
    /// apart (same 3×3 shape, different progression), while n = 3 pedestal
    /// collapses into wide/row-major (2 on top, 1 full-width below, same
    /// progression). A single choice means there is nothing to choose.
    static func choices(forVisibleCount n: Int) -> [ProjectLayoutType] {
        var seen: [[[Int]]] = []
        var result: [ProjectLayoutType] = []
        for type in all {
            let key = type.arrangementKey(forVisibleCount: n)
            if seen.contains(key) { continue }
            seen.append(key)
            result.append(type)
        }
        return result
    }

    /// The choice that stands for `self` at `n` visible projects: `self` when
    /// it is a kept representative, otherwise the representative it collapsed
    /// into. Lets the selector highlight the current type even when the saved
    /// type is not the kept spelling for this count.
    func representative(forVisibleCount n: Int) -> ProjectLayoutType {
        let key = arrangementKey(forVisibleCount: n)
        return Self.choices(forVisibleCount: n).first {
            $0.arrangementKey(forVisibleCount: n) == key
        } ?? self
    }

    // MARK: Tree derivation (SPEC §26.3)

    /// The canonical project tree that places `ids` — the list's visible rows
    /// in row order — into this type's slots: the k-th id takes the k-th slot.
    /// Rows stack vertically and columns sit horizontally at equal shares
    /// (the pedestal bottom row is one more equal tier). Traversal order of the
    /// result is *not* the ordinal order in general (column-major over a
    /// wide grid runs down the columns); ordinals derive from the list order,
    /// never from the tree.
    func tree(over ids: [ProjectID]) -> SplitTree<ProjectRef> {
        let n = ids.count
        guard n > 0 else { return .init() }
        let slots = slots(forVisibleCount: n)
        // slot index (in ordinal order) → project ref
        var bySlot: [Slot: ProjectRef] = [:]
        for (index, slot) in slots.enumerated() {
            bySlot[slot] = ProjectRef(id: ids[index])
        }
        func ref(_ slot: Slot) -> ProjectRef { bySlot[slot]! }

        switch shape {
        case .wide:
            return SplitTree(gridRows: Self.rowsOf(slots).map { $0.map(ref) })
        case .tall:
            return SplitTree(gridColumns: Self.columnsOf(slots).map { $0.map(ref) })
        case .pedestal:
            guard n > 1 else { return .init(view: ref(slots[0])) }
            let bottom = slots.last!
            let top = Array(slots.dropLast())
            let topTree: SplitTree<ProjectRef> = switch orientation {
            case .rowMajor: SplitTree(gridRows: Self.rowsOf(top).map { $0.map(ref) })
            case .columnMajor: SplitTree(gridColumns: Self.columnsOf(top).map { $0.map(ref) })
            }
            return SplitTree(stacking: topTree, over: ref(bottom), topRatio: bottom.frame.minY)
        }
    }

    /// Slots grouped by grid row (top first), left to right within a row.
    private static func rowsOf(_ slots: [Slot]) -> [[Slot]] {
        Dictionary(grouping: slots, by: \.row)
            .sorted { $0.key < $1.key }
            .map { $0.value.sorted { $0.column < $1.column } }
    }

    /// Slots grouped by grid column (left first), top to bottom within one.
    private static func columnsOf(_ slots: [Slot]) -> [[Slot]] {
        Dictionary(grouping: slots, by: \.column)
            .sorted { $0.key < $1.key }
            .map { $0.value.sorted { $0.row < $1.row } }
    }
}

extension ProjectLayoutType.Slot: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(row)
        hasher.combine(column)
        hasher.combine(frame.minX)
        hasher.combine(frame.minY)
    }
}
