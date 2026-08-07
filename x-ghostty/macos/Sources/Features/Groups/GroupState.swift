import Foundation

/// State for a single group: a named container around a pane split tree.
///
/// See `SPEC.md` §5.3. Per the Phase 0 design decision, `paneTree` keeps the
/// existing `SplitTree<XGhostty.SurfaceView>` element type rather than the
/// `SplitTree<SurfaceRef>` shown in the spec, so the existing rendering,
/// action, restore and drag-and-drop pipelines work unchanged. `SurfaceID`
/// values are derived from `SurfaceView.id`.
struct GroupState: Identifiable {
    /// The maximum number of lines a note may hold. Text beyond this is
    /// dropped at every entry point — `init`, `setNote`, and decode — so an
    /// over-long note is never retained anywhere.
    static let maxNoteLines = 10

    let id: GroupID
    var name: String

    /// The pane layout for this group. Element type intentionally kept as
    /// `XGhostty.SurfaceView` (see the type doc above).
    var paneTree: SplitTree<XGhostty.SurfaceView>

    /// The surface that last held focus within this group, identified by
    /// `SurfaceView.id`.
    var focusedSurface: SurfaceID?

    /// The human-written note attached to this group. Belongs to the group as
    /// a whole, never to individual panes. Always normalized: at most
    /// `maxNoteLines` lines, `\n` separators. Empty means "no note".
    private(set) var note: String

    var createdAt: Date
    var lastFocusedAt: Date?

    init(
        id: GroupID,
        name: String,
        paneTree: SplitTree<XGhostty.SurfaceView>,
        focusedSurface: SurfaceID? = nil,
        note: String = "",
        createdAt: Date,
        lastFocusedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.paneTree = paneTree
        self.focusedSurface = focusedSurface
        self.note = Self.normalizedNote(note)
        self.createdAt = createdAt
        self.lastFocusedAt = lastFocusedAt
    }

    /// Replace the note with `raw`, normalized through `normalizedNote`. The
    /// only mutation path, so the line cap can never be bypassed.
    mutating func setNote(_ raw: String) {
        note = Self.normalizedNote(raw)
    }

    /// Canonical note form: line endings unified to `\n` and everything past
    /// `maxNoteLines` lines dropped. A "line" is one `\n`-separated component,
    /// so a trailing newline counts as starting an (empty) next line.
    static func normalizedNote(_ raw: String) -> String {
        let unified = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = unified.components(separatedBy: "\n")
        guard lines.count > maxNoteLines else { return unified }
        return lines.prefix(maxNoteLines).joined(separator: "\n")
    }
}

// MARK: Codable

extension GroupState: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case paneTree
        case focusedSurface
        case note
        case createdAt
        case lastFocusedAt
    }

    /// Custom decode for two reasons: saves written before notes existed have
    /// no `note` key (decode as empty), and a hand-edited or corrupted save
    /// must not smuggle in an over-long note (re-normalized on decode).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(GroupID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.paneTree = try c.decode(SplitTree<XGhostty.SurfaceView>.self, forKey: .paneTree)
        self.focusedSurface = try c.decodeIfPresent(SurfaceID.self, forKey: .focusedSurface)
        self.note = Self.normalizedNote(try c.decodeIfPresent(String.self, forKey: .note) ?? "")
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.lastFocusedAt = try c.decodeIfPresent(Date.self, forKey: .lastFocusedAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(paneTree, forKey: .paneTree)
        try c.encodeIfPresent(focusedSurface, forKey: .focusedSurface)
        try c.encode(note, forKey: .note)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(lastFocusedAt, forKey: .lastFocusedAt)
    }
}
