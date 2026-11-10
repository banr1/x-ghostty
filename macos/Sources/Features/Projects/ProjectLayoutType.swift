import Foundation

/// A layout type (`SPEC.md` §26): the rule that derives the overall-view
/// arrangement from the visible projects in placement order (Core before
/// Side, `WorkspaceStateOf.visibleProjectIDs`). Two shapes:
///
/// - **wide** — rows = the integer nearest √n; the projects are dealt to the
///   rows as evenly as possible, the leftover attaching to the trailing rows
///   (n=8 is 2+3+3 from the top — the top rows hold fewer, wider slots). Row
///   heights are equal; a row's width is shared by kind weight (a Side is half
///   as wide as a Core in the same row). The ordinals (Cmd+1–9) run along the
///   rows: top row first, left to right.
/// - **tall** — the transpose: columns = nearest √n, the leftover attaching
///   to the trailing columns (the left columns hold fewer slots). Column
///   widths are equal; a column's height is shared by kind weight. The
///   ordinals run along the columns: left column first, top to bottom.
///
/// Every project counts as one slot whatever its kind, so the kinds never
/// change how many slots a tier holds — only how a tier divides its length.
/// The ordinal progression follows the shape; there is no independent
/// orientation (must 49).
///
/// The set is closed by design (user-defined layouts are a declared
/// non-goal), so the definitions live here as data and the geometry as pure
/// functions, verifiable from `XGhosttyTests`. Nothing here knows about the
/// list or the model — the model applies the type to its visible projects and
/// re-derives the canonical tree (`WorkspaceStateOf.relayout()`).
enum ProjectLayoutType: String, CaseIterable, Identifiable {
    case wide, tall

    /// The type used when nothing is saved (`SPEC.md` §26.4).
    static let `default`: ProjectLayoutType = .wide

    /// Every type, in canonical enumeration order. `choices(forKinds:)` keeps
    /// the first of each collapsed group, so this order also decides the
    /// representative.
    static let all: [ProjectLayoutType] = allCases

    var id: String { rawValue }

    /// The label the selector shows (must 51).
    var label: String {
        switch self {
        case .wide: "Wide"
        case .tall: "Tall"
        }
    }

    // MARK: Distribution rules

    /// The wide-shape row distribution (`SPEC.md` §26.1): the row count is the
    /// integer nearest √n, and the projects are dealt to the rows as evenly as
    /// possible — the indivisible leftover goes one each to the *trailing*
    /// rows, so the leading rows hold fewer, wider slots (4 = 2+2, 5 = 2+3,
    /// 6 = 3+3, 7 = 2+2+3, 8 = 2+3+3, 9 = 3+3+3). The tall shape uses the same
    /// numbers as its column distribution (the leading — leftmost — columns
    /// hold fewer slots).
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
    /// to bottom). The progression always runs along the tiers.
    private func tiers(_ n: Int) -> [[Int]] {
        var next = 0
        return Self.tierCounts(n).map { count in
            defer { next += count }
            return Array(next..<(next + count))
        }
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
                frames[ordinal] = switch self {
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

    /// The selectable types for projects of `kinds` in placement order: wide
    /// and tall collapse into one (wide is kept) when their arrangement **and**
    /// ordinal progression coincide exactly — only a single project does. Nine
    /// Cores share the 3×3 grid but run their ordinals along rows vs columns,
    /// so they stay apart. A single choice means there is nothing to choose.
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
    /// tier divides its length by kind weight. Ordinals derive from the
    /// placement order, never from the tree.
    func tree(over ids: [ProjectID], kinds: [ProjectKind] = []) -> SplitTree<ProjectRef> {
        let weighted = tiers(ids.count).map { tier in
            tier.map { ordinal in
                (
                    element: ProjectRef(id: ids[ordinal]),
                    weight: (ordinal < kinds.count ? kinds[ordinal] : .core).layoutWeight
                )
            }
        }
        return switch self {
        case .wide: SplitTree(weightedRows: weighted)
        case .tall: SplitTree(weightedColumns: weighted)
        }
    }
}

// MARK: Codable (SPEC §26.4)

extension ProjectLayoutType: Codable {
    private enum CodingKeys: String, CodingKey {
        case shape
    }

    /// Saved as `{"shape": …}`. Saves written while the orientation existed
    /// also carry an `orientation` key: it is ignored, keeping the shape
    /// (wide · by columns → wide, tall · by rows → tall). The pedestal shape no
    /// longer exists: a saved one reads as wide whatever its orientation. Any
    /// other unknown shape is corrupt and throws (the workspace decode falls
    /// back to the default type).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawShape = try c.decode(String.self, forKey: .shape)
        guard let type = rawShape == "pedestal" ? .wide : ProjectLayoutType(rawValue: rawShape) else {
            throw DecodingError.dataCorruptedError(
                forKey: .shape, in: c, debugDescription: "Unknown layout shape \(rawShape)")
        }
        self = type
    }

    /// Writes the shape only — never an orientation.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(rawValue, forKey: .shape)
    }
}
