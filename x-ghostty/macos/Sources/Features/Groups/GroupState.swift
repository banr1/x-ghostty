import Foundation

/// State for a single group: a named container around a pane split tree.
///
/// See `SPEC.md` §5.3. Per the Phase 0 design decision, the runtime pane tree
/// keeps the existing `SplitTree<XGhostty.SurfaceView>` element type rather
/// than the `SplitTree<SurfaceRef>` shown in the spec, so the existing
/// rendering, action, restore and drag-and-drop pipelines work unchanged.
/// `SurfaceID` values are derived from `SurfaceView.id`.
///
/// The struct itself is generic over the pane element (`GroupStateOf<Pane>`,
/// with `GroupState` as the runtime specialization) so the model-layer
/// judgment logic — the note rules and the primary-pane rules (SPEC §22) —
/// can be exercised from `XGhosttyTests` with value-type panes: constructing a
/// real `SurfaceView` requires a live XGhostty app, which unit tests do not
/// have.
struct GroupStateOf<Pane: Codable & Identifiable & Equatable>: Identifiable where Pane.ID == UUID {
    /// The maximum number of lines a note may hold. Text beyond this is
    /// dropped at every entry point — `init`, `setNote`, and decode — so an
    /// over-long note is never retained anywhere.
    static var maxNoteLines: Int { 10 }

    let id: GroupID
    var name: String

    /// The pane layout for this group. Element type intentionally kept as
    /// `XGhostty.SurfaceView` at runtime (see the type doc above).
    ///
    /// Every replacement re-reconciles the primary flag (SPEC §22.2): panes
    /// added by later splits never take the flag, and when the primary pane
    /// leaves the tree — shell exit, Cmd+W, process death all funnel through a
    /// tree replacement — the nearest remaining leaf is promoted.
    var paneTree: SplitTree<Pane> {
        didSet {
            primaryPane = paneTree.reconciledPrimary(
                previousTree: oldValue,
                previousPrimary: primaryPane?.rawValue
            ).map(SurfaceID.init(rawValue:))
            // The terminated state is valid only while the terminated pane is
            // the tree's sole leaf (SPEC §23.2): if the pane leaves the tree,
            // or the tree grows past one pane (e.g. a split while terminated),
            // the group is no longer "terminated" — the dead pane, if still
            // present, is just an exited sibling pane.
            if let terminated = terminatedPane,
               paneTree.isSplit || paneTree.find(id: terminated.rawValue) == nil {
                terminatedPane = nil
            }
        }
    }

    /// The surface that last held focus within this group, identified by
    /// `SurfaceView.id`.
    var focusedSurface: SurfaceID?

    /// The human-written note attached to this group (`SPEC.md` §21.1).
    /// Belongs to the group as a whole, never to individual panes. Always
    /// normalized: at most `maxNoteLines` lines, `\n` separators. Empty means
    /// "no note".
    private(set) var note: String

    /// The pane whose primary flag is set (`SPEC.md` §22.1): the group's
    /// representative pane, the only one the overall (non-zoomed) view draws.
    ///
    /// Invariant: exactly one pane holds the flag whenever `paneTree` is
    /// non-empty; `nil` only for an empty tree. Maintained at every entry
    /// point — `init` and decode normalize, `paneTree`'s observer reconciles,
    /// `setPrimaryPane` rejects panes outside the tree — so an invalid state
    /// (zero or several primaries) is unrepresentable in memory.
    private(set) var primaryPane: SurfaceID?

    /// The pane held in the terminated state, or `nil` (`SPEC.md` §23.2): the
    /// group's last pane whose shell has exited. The group stays — with its
    /// note — instead of closing, and Enter starts a new shell in the pane.
    ///
    /// Invariant: non-`nil` only while that pane is the tree's sole leaf,
    /// maintained by `markPaneTerminated` and the `paneTree` observer.
    /// Runtime-only: never persisted — a restore recreates every pane with a
    /// fresh shell, so a restored group is live again (`SPEC.md` §23.4).
    private(set) var terminatedPane: SurfaceID?

    var createdAt: Date
    var lastFocusedAt: Date?

    init(
        id: GroupID,
        name: String,
        paneTree: SplitTree<Pane>,
        focusedSurface: SurfaceID? = nil,
        note: String = "",
        primaryPane: SurfaceID? = nil,
        createdAt: Date,
        lastFocusedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.paneTree = paneTree
        self.focusedSurface = focusedSurface
        self.note = Self.normalizedNote(note)
        // The first pane of a new group is the default primary (SPEC §22.1):
        // with no explicit candidate this resolves to the tree's first leaf.
        self.primaryPane = paneTree.normalizedPrimary(
            from: [primaryPane?.rawValue].compactMap { $0 }
        ).map(SurfaceID.init(rawValue:))
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

    // MARK: Primary pane (SPEC §22)

    /// Whether `paneID`'s primary flag is set. Exactly one pane per group
    /// answers `true` while the tree is non-empty (SPEC §22.1).
    func isPrimary(_ paneID: SurfaceID) -> Bool {
        primaryPane == paneID
    }

    /// The pane tree the overall (non-zoomed) view renders for this group: a
    /// single-leaf tree holding only the primary pane (SPEC §22.3). The
    /// zoomed local view renders `paneTree` unchanged. An empty group renders
    /// nothing; a missing primary (unreachable while the invariant holds)
    /// falls back to the full tree rather than blanking the group.
    var overallViewPaneTree: SplitTree<Pane> {
        guard let primary = primaryPane else { return paneTree }
        guard let node = paneTree.find(id: primary.rawValue),
              case .leaf(let pane) = node else { return paneTree }
        return paneTree.subtreeContainingOnly(pane)
    }

    /// Move the primary flag to `paneID` (`set_primary`, SPEC §22.4). The
    /// former primary is demoted implicitly — the flag is single-valued, so
    /// uniqueness cannot break.
    ///
    /// - Returns: `false` (and changes nothing) when `paneID` is not a leaf of
    ///   `paneTree`, so a stale id can never point the flag outside the group.
    @discardableResult
    mutating func setPrimaryPane(_ paneID: SurfaceID) -> Bool {
        guard paneTree.find(id: paneID.rawValue) != nil else { return false }
        primaryPane = paneID
        return true
    }

    // MARK: Terminated state (SPEC §23.2–23.3)

    /// Whether this group is in the terminated state: its last pane's shell
    /// has exited and the pane is kept instead of closing the group.
    var isTerminated: Bool {
        terminatedPane != nil
    }

    /// Enter the terminated state for `paneID` (`SPEC.md` §23.2): the group's
    /// last pane whose shell exited is kept — with the group and its note —
    /// instead of closing.
    ///
    /// - Returns: `false` (and changes nothing) unless `paneID` is the tree's
    ///   sole leaf: the terminated state is defined only for a last pane; an
    ///   exited pane among several simply closes.
    @discardableResult
    mutating func markPaneTerminated(_ paneID: SurfaceID) -> Bool {
        guard !paneTree.isSplit,
              paneTree.find(id: paneID.rawValue) != nil else { return false }
        terminatedPane = paneID
        return true
    }

    /// Leave the terminated state by replacing the dead pane with `newPane`,
    /// which carries a fresh shell (`SPEC.md` §23.3): the group resumes work
    /// in the same pane slot, keeping its note, name, and layout position.
    ///
    /// - Returns: `false` (and changes nothing) when the group is not
    ///   terminated.
    @discardableResult
    mutating func restartTerminatedPane(with newPane: Pane) -> Bool {
        guard isTerminated else { return false }
        // The tree observer clears `terminatedPane` (the dead pane leaves the
        // tree) and re-resolves the primary onto the sole new leaf.
        paneTree = SplitTree<Pane>(view: newPane)
        return true
    }
}

// MARK: Codable

extension GroupStateOf: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case paneTree
        case focusedSurface
        case note
        case primaryPanes
        case createdAt
        case lastFocusedAt
    }

    /// Custom decode for three reasons: saves written before notes existed
    /// have no `note` key (decode as empty), a hand-edited or corrupted save
    /// must not smuggle in an over-long note (re-normalized on decode), and
    /// the persisted primary flags must come back as exactly one primary —
    /// a save carrying zero, dangling, or several flagged panes (or none of
    /// the key at all, for pre-primary saves) is normalized against the
    /// decoded tree (SPEC §22.1).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(GroupID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.paneTree = try c.decode(SplitTree<Pane>.self, forKey: .paneTree)
        self.focusedSurface = try c.decodeIfPresent(SurfaceID.self, forKey: .focusedSurface)
        self.note = Self.normalizedNote(try c.decodeIfPresent(String.self, forKey: .note) ?? "")
        let flagged = try c.decodeIfPresent([SurfaceID].self, forKey: .primaryPanes) ?? []
        self.primaryPane = paneTree.normalizedPrimary(
            from: flagged.map(\.rawValue)
        ).map(SurfaceID.init(rawValue:))
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
        // The save format is the list of panes whose primary flag is set —
        // riding the same record as the pane layout (SPEC §22.1). A healthy
        // save always holds exactly one entry; the list form exists so decode
        // can *repair* a corrupt save rather than reject it.
        try c.encode([primaryPane].compactMap { $0 }, forKey: .primaryPanes)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(lastFocusedAt, forKey: .lastFocusedAt)
    }
}

/// The runtime specialization: pane elements are live surface views.
typealias GroupState = GroupStateOf<XGhostty.SurfaceView>

// MARK: Primary-pane resolution (SPEC §22.1–22.2)

extension SplitTree {
    /// Resolve stored primary-flag candidates against this tree: the first
    /// candidate that is currently a leaf wins; with no valid candidate the
    /// first leaf is the default primary; an empty tree has no primary.
    ///
    /// This is the restore-normalization rule of SPEC §22.1: a save carrying
    /// zero, dangling, or several flagged panes comes back as exactly one.
    func normalizedPrimary(from candidates: [Element.ID]) -> Element.ID? {
        for candidate in candidates where find(id: candidate) != nil {
            return candidate
        }
        return firstLeaf?.id
    }

    /// Carry the primary flag across a tree change (SPEC §22.2), where `self`
    /// is the new tree:
    ///
    /// - A primary still present keeps the flag — panes added by later splits
    ///   never take it.
    /// - A primary that left the tree promotes its nearest leaf, measured on
    ///   `previousTree` (where the departed primary still has a position)
    ///   among the panes that survive into `self`. Shell exit, Cmd+W, and
    ///   process death all reach the model as such a replacement.
    /// - With nothing to promote (no previous primary, or no survivor), the
    ///   first leaf is the default; an empty tree has no primary.
    func reconciledPrimary(previousTree: Self, previousPrimary: Element.ID?) -> Element.ID? {
        guard let previousPrimary else { return firstLeaf?.id }
        if find(id: previousPrimary) != nil { return previousPrimary }

        if let departed = previousTree.first(where: { $0.id == previousPrimary }),
           let promoted = previousTree.nearestLeaf(
               to: departed,
               matching: { find(id: $0.id) != nil }) {
            return promoted.id
        }
        return firstLeaf?.id
    }
}
