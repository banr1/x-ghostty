import Foundation

/// A layout type (`SPEC.md` §26): the rule that derives the overall-view
/// arrangement from the visible projects in placement order (Core before
/// Side, `WorkspaceStateOf.visibleProjectIDs`). Shape × orientation:
///
/// - **wide** — rows = the integer nearest √n; the projects are dealt to the
///   rows as evenly as possible, the leftover attaching to the trailing rows
///   (n=8 is 2+3+3 from the top — the top rows hold fewer, wider slots). Row
///   heights are equal; a row's width is shared by kind weight (a Side is half
///   as wide as a Core in the same row).
/// - **tall** — the transpose: columns = nearest √n, the leftover attaching
///   to the trailing columns (the left columns hold fewer slots). Column
///   widths are equal; a column's height is shared by kind weight.
///
/// Every project counts as one slot whatever its kind, so the kinds never
/// change how many slots a tier holds — only how a tier divides its length.
///
/// The orientation decides the ordinal progression (Cmd+1–9) and so which
/// project takes which slot: row-major runs top row first, left to right;
/// column-major runs left column first, top to bottom. It never changes the
/// shape.
///
/// The set is closed by design (user-defined layouts are a declared
/// non-goal), so the definitions live here as data and the geometry as pure
/// functions, verifiable from `XGhosttyTests`. Nothing here knows about the
/// list or the model — the model applies the type to its visible projects and
/// re-derives the canonical tree (`WorkspaceStateOf.relayout()`).
struct ProjectLayoutType: Equatable, Hashable, Codable, Identifiable {
    enum Shape: String, Codable, CaseIterable {
        case wide, tall
    }

    enum Orientation: String, Codable, CaseIterable {
        case rowMajor, columnMajor
    }

    var shape: Shape
    var orientation: Orientation

    /// The type used when nothing is saved (`SPEC.md` §26.4).
    static let `default` = ProjectLayoutType(shape: .wide, orientation: .rowMajor)

    /// Every shape × orientation, in canonical enumeration order (shape
    /// first). `choices(forKinds:)` keeps the first of each collapsed group,
    /// so this order also decides the representative.
    static let all: [ProjectLayoutType] = Shape.allCases.flatMap { shape in
        Orientation.allCases.map { ProjectLayoutType(shape: shape, orientation: $0) }
    }

    var id: String { "\(shape.rawValue)-\(orientation.rawValue)" }

    /// A short label for the selector and the docs.
    var label: String {
        let shapeName: String = switch shape {
        case .wide: "wide"
        case .tall: "tall"
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

    /// The ordinals laid out tier by tier: `tiers(n)[t][p]` is the 0-based
    /// ordinal of the project at position `p` of tier `t`, where a tier is a
    /// row (wide, top first, left to right) or a column (tall, left first, top
    /// to bottom). The orientation ranks the cells, independently of the kinds.
    private func tiers(_ n: Int) -> [[Int]] {
        let counts = Self.tierCounts(n)
        let cells = counts.enumerated().flatMap { tier, count in
            (0..<count).map { (tier: tier, position: $0) }
        }
        // A wide tier is a row and a tall tier a column, so the progression
        // runs along the tiers exactly when the two agree.
        let alongTiers = (shape == .wide) == (orientation == .rowMajor)
        let ranked = cells.sorted { a, b in
            alongTiers
                ? (a.tier, a.position) < (b.tier, b.position)
                : (a.position, a.tier) < (b.position, b.tier)
        }
        var result = counts.map { [Int](repeating: 0, count: $0) }
        for (ordinal, cell) in ranked.enumerated() {
            result[cell.tier][cell.position] = ordinal
        }
        return result
    }

    // MARK: Slots

    /// The slot rectangles in the unit square (origin top-left, y growing
    /// downward) **in ordinal (assignment) order**, for projects of `kinds` in
    /// placement order: the k-th frame is where the k-th project goes and what
    /// Cmd+(k+1) jumps to. Empty for no projects.
    func slotFrames(forKinds kinds: [ProjectKind]) -> [CGRect] {
        let tiers = tiers(kinds.count)
        let tierLength = 1.0 / Double(max(tiers.count, 1))
        var frames = [CGRect](repeating: .zero, count: kinds.count)
        for (tier, ordinals) in tiers.enumerated() {
            let total = ordinals.reduce(0) { $0 + kinds[$1].layoutWeight }
            var offset = 0.0
            for ordinal in ordinals {
                let share = kinds[ordinal].layoutWeight / total
                let across = Double(tier) * tierLength
                frames[ordinal] = switch shape {
                case .wide: CGRect(x: offset, y: across, width: share, height: tierLength)
                case .tall: CGRect(x: across, y: offset, width: tierLength, height: share)
                }
                offset += share
            }
        }
        return frames
    }

    /// The slot rectangles for `n` Core projects (equal shares).
    func slotFrames(forVisibleCount n: Int) -> [CGRect] {
        slotFrames(forKinds: Self.allCore(n))
    }

    private static func allCore(_ n: Int) -> [ProjectKind] {
        Array(repeating: .core, count: max(n, 0))
    }

    // MARK: Choices per visible count (SPEC §26.2)

    /// A comparable key of the ordered arrangement, rounded so two rules that
    /// produce the same geometry through different arithmetic still compare
    /// equal.
    private func arrangementKey(forKinds kinds: [ProjectKind]) -> [[Int]] {
        slotFrames(forKinds: kinds).map { frame in
            [frame.minX, frame.minY, frame.width, frame.height].map { Int(($0 * 1_000_000).rounded()) }
        }
    }

    /// The selectable types for projects of `kinds` in placement order: of the
    /// 2 shapes × 2 orientations, those whose arrangement **and** ordinal
    /// progression coincide exactly are collapsed into one (the first in `all`
    /// order is kept), and the rest are the choices. E.g. nine Cores keep the
    /// two progressions of the 3×3 grid apart while collapsing each wide/tall
    /// pair that runs the same way; a Side among them tells wide from tall (half
    /// the width vs half the height), so those stay apart too. A single choice
    /// means there is nothing to choose.
    static func choices(forKinds kinds: [ProjectKind]) -> [ProjectLayoutType] {
        var seen: [[[Int]]] = []
        var result: [ProjectLayoutType] = []
        for type in all {
            let key = type.arrangementKey(forKinds: kinds)
            if seen.contains(key) { continue }
            seen.append(key)
            result.append(type)
        }
        return result
    }

    /// The selectable types for `n` Core projects.
    static func choices(forVisibleCount n: Int) -> [ProjectLayoutType] {
        choices(forKinds: allCore(n))
    }

    /// The choice that stands for `self` at `kinds`: `self` when it is a kept
    /// representative, otherwise the representative it collapsed into. Lets
    /// the selector highlight the current type even when the saved type is not
    /// the kept spelling for these projects.
    func representative(forKinds kinds: [ProjectKind]) -> ProjectLayoutType {
        let key = arrangementKey(forKinds: kinds)
        return Self.choices(forKinds: kinds).first {
            $0.arrangementKey(forKinds: kinds) == key
        } ?? self
    }

    /// The choice that stands for `self` at `n` Core projects.
    func representative(forVisibleCount n: Int) -> ProjectLayoutType {
        representative(forKinds: Self.allCore(n))
    }

    // MARK: Tree derivation (SPEC §26.3)

    /// The canonical project tree that places `ids` — the visible projects in
    /// placement order — into this type's slots: the k-th id takes the k-th
    /// slot, sized by the k-th of `kinds` (a missing kind reads as Core). Rows
    /// stack vertically and columns sit horizontally at equal shares, and each
    /// tier divides its length by kind weight. Traversal order of the result
    /// is *not* the ordinal order in general (column-major over a wide grid
    /// runs down the columns); ordinals derive from the placement order, never
    /// from the tree.
    func tree(over ids: [ProjectID], kinds: [ProjectKind] = []) -> SplitTree<ProjectRef> {
        let weighted = tiers(ids.count).map { tier in
            tier.map { ordinal in
                (
                    element: ProjectRef(id: ids[ordinal]),
                    weight: (ordinal < kinds.count ? kinds[ordinal] : .core).layoutWeight
                )
            }
        }
        return switch shape {
        case .wide: SplitTree(weightedRows: weighted)
        case .tall: SplitTree(weightedColumns: weighted)
        }
    }
}

// MARK: Codable (SPEC §26.4)

extension ProjectLayoutType {
    private enum CodingKeys: String, CodingKey {
        case shape, orientation
    }

    /// The pedestal shape no longer exists: a saved one reads as wide, keeping
    /// its orientation. Any other unknown shape is corrupt and throws (the
    /// workspace decode falls back to the default type).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawShape = try c.decode(String.self, forKey: .shape)
        guard let shape = rawShape == "pedestal" ? .wide : Shape(rawValue: rawShape) else {
            throw DecodingError.dataCorruptedError(
                forKey: .shape, in: c, debugDescription: "Unknown layout shape \(rawShape)")
        }
        self.init(
            shape: shape,
            orientation: try c.decode(Orientation.self, forKey: .orientation))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(shape, forKey: .shape)
        try c.encode(orientation, forKey: .orientation)
    }
}
