import Foundation

/// One of the built-in registered layouts (`SPEC.md` §26): a fixed arrangement
/// template the layout selector (`choose_project_layout`, Cmd+L) can apply to
/// the visible projects.
///
/// Eleven layouts exist: equal-split for 4–9 projects (6 kinds) and X+1 for
/// X = 4–8 (5 kinds: X projects equal-split on top, 1 full-width at the
/// bottom). The set is closed by design — user-defined layouts are a declared
/// non-goal — so the definitions live here as data and the geometry as pure
/// functions, verifiable from `XGhosttyTests`.
struct ProjectLayout: Equatable, Identifiable {
    enum Kind: Equatable {
        /// `projectCount` projects on a near-square grid.
        case equalSplit
        /// `projectCount - 1` projects equal-split on top, plus one
        /// full-width project as the bottom row.
        case xPlusOne
    }

    let kind: Kind

    /// The total number of projects this layout arranges (the +1 included).
    let projectCount: Int

    var id: String {
        switch kind {
        case .equalSplit: "equal-\(projectCount)"
        case .xPlusOne: "xplus1-\(projectCount - 1)"
        }
    }

    /// The 11 registered layouts, in selector display order: equal-split
    /// 4–9, then X+1 for X = 4–8.
    static let registered: [ProjectLayout] =
        (4...9).map { ProjectLayout(kind: .equalSplit, projectCount: $0) } +
        (4...8).map { ProjectLayout(kind: .xPlusOne, projectCount: $0 + 1) }

    /// The equal-split row distribution rule (`SPEC.md` §26.1): the row count
    /// is the integer nearest √n, and the projects are dealt to the rows from
    /// the top as evenly as possible — the leftover projects go one each to
    /// the top rows (4 = 2+2, 5 = 3+2, 6 = 3+3, 7 = 3+2+2, 8 = 3+3+2,
    /// 9 = 3+3+3).
    static func equalSplitRowCounts(_ n: Int) -> [Int] {
        let rows = max(1, Int(Double(n).squareRoot().rounded()))
        let base = n / rows
        let extra = n % rows
        return (0..<rows).map { $0 < extra ? base + 1 : base }
    }

    /// The projects-per-row distribution, top row first. The X part of X+1
    /// follows the equal-split rule; the +1 is its own final full-width row.
    var rowCounts: [Int] {
        switch kind {
        case .equalSplit: Self.equalSplitRowCounts(projectCount)
        case .xPlusOne: Self.equalSplitRowCounts(projectCount - 1) + [1]
        }
    }

    /// The slot rectangles in the unit square (origin top-left, y growing
    /// downward), in assignment order: top row first, left to right within a
    /// row, so the X+1 bottom slot is naturally last. Row heights are equal
    /// (the +1 row is an equal-height row like the others) and each row's
    /// slot widths are equal (`SPEC.md` §26.1).
    var slotFrames: [CGRect] {
        let rows = rowCounts
        let rowHeight = 1.0 / Double(rows.count)
        var frames: [CGRect] = []
        for (rowIndex, cellCount) in rows.enumerated() {
            let cellWidth = 1.0 / Double(cellCount)
            for cell in 0..<cellCount {
                frames.append(CGRect(
                    x: Double(cell) * cellWidth,
                    y: Double(rowIndex) * rowHeight,
                    width: cellWidth,
                    height: rowHeight))
            }
        }
        return frames
    }

    /// A compact display label for the selector list, e.g. "3+2" for the
    /// 5-project equal split and "2+2 +1" for the X=4 X+1 layout.
    var label: String {
        switch kind {
        case .equalSplit:
            rowCounts.map(String.init).joined(separator: "+")
        case .xPlusOne:
            Self.equalSplitRowCounts(projectCount - 1).map(String.init)
                .joined(separator: "+") + " +1"
        }
    }
}
