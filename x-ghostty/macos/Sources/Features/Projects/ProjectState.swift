import Foundation

/// State for a single project: a named container around a pane split tree.
///
/// See `SPEC.md` §5.3. Per the Phase 0 design decision, the runtime pane tree
/// keeps the existing `SplitTree<XGhostty.SurfaceView>` element type rather
/// than the `SplitTree<SurfaceRef>` shown in the spec, so the existing
/// rendering, action, restore and drag-and-drop pipelines work unchanged.
/// `SurfaceID` values are derived from `SurfaceView.id`.
///
/// The struct itself is generic over the pane element (`ProjectStateOf<Pane>`,
/// with `ProjectState` as the runtime specialization) so the model-layer
/// judgment logic — the note rules and the primary-pane rules (SPEC §22) —
/// can be exercised from `XGhosttyTests` with value-type panes: constructing a
/// real `SurfaceView` requires a live XGhostty app, which unit tests do not
/// have.
struct ProjectStateOf<Pane: Codable & Identifiable & Equatable>: Identifiable where Pane.ID == UUID {
    /// The maximum number of lines a note may hold. Text beyond this is
    /// dropped at every entry point — `init`, `setNote`, and decode — so an
    /// over-long note is never retained anywhere.
    static var maxNoteLines: Int { 10 }

    let id: ProjectID
    var name: String

    /// The pane layout for this project. Element type intentionally kept as
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
            // the project is no longer "terminated" — the dead pane, if still
            // present, is just an exited sibling pane.
            if let terminated = terminatedPane,
               paneTree.isSplit || paneTree.find(id: terminated.rawValue) == nil {
                terminatedPane = nil
            }
        }
    }

    /// The surface that last held focus within this project, identified by
    /// `SurfaceView.id`.
    var focusedSurface: SurfaceID?

    /// The human-written note attached to this project (`SPEC.md` §21.1).
    /// Belongs to the project as a whole, never to individual panes. Always
    /// normalized: at most `maxNoteLines` lines, `\n` separators. Empty means
    /// "no note".
    private(set) var note: String

    /// The pane whose primary flag is set (`SPEC.md` §22.1): the project's
    /// representative pane, the only one the overall (non-zoomed) view draws.
    ///
    /// Invariant: exactly one pane holds the flag whenever `paneTree` is
    /// non-empty; `nil` only for an empty tree. Maintained at every entry
    /// point — `init` and decode normalize, `paneTree`'s observer reconciles,
    /// `setPrimaryPane` rejects panes outside the tree — so an invalid state
    /// (zero or several primaries) is unrepresentable in memory.
    private(set) var primaryPane: SurfaceID?

    /// The pane held in the terminated state, or `nil` (`SPEC.md` §23.2): the
    /// project's last pane whose shell has exited. The project stays — with its
    /// note — instead of closing, and Enter starts a new shell in the pane.
    ///
    /// Invariant: non-`nil` only while that pane is the tree's sole leaf,
    /// maintained by `markPaneTerminated` and the `paneTree` observer.
    /// Runtime-only: never persisted — a restore recreates every pane with a
    /// fresh shell, so a restored project is live again (`SPEC.md` §23.4).
    private(set) var terminatedPane: SurfaceID?

    /// The human-set priority of this project, or `nil` for unset — the default
    /// (`SPEC.md` §24.1). Like the note, it belongs to the project as a whole
    /// and persists through the same record.
    var priority: ProjectPriority?

    /// The human-set deadline of this project (date only, no time), or `nil`
    /// for unset — the default (`SPEC.md` §24.1). Validation lives in
    /// `ProjectDeadline`: an invalid date cannot be represented, so an invalid
    /// input is rejected to unset at the model boundary. Persists through the
    /// same record as the note.
    var deadline: ProjectDeadline?

    /// Who or what moves this project next (`SPEC.md` §24.6), or `nil` for
    /// unset — the default. Human-written workspace information like the
    /// priority, persisted through the same record; the daily priority reset
    /// never touches it, and the label band never shows it.
    var nextTrigger: ProjectNextTrigger?

    var createdAt: Date
    var lastFocusedAt: Date?

    init(
        id: ProjectID,
        name: String,
        paneTree: SplitTree<Pane>,
        focusedSurface: SurfaceID? = nil,
        note: String = "",
        primaryPane: SurfaceID? = nil,
        priority: ProjectPriority? = nil,
        deadline: ProjectDeadline? = nil,
        nextTrigger: ProjectNextTrigger? = nil,
        createdAt: Date,
        lastFocusedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.paneTree = paneTree
        self.focusedSurface = focusedSurface
        self.note = Self.normalizedNote(note)
        // The first pane of a new project is the default primary (SPEC §22.1):
        // with no explicit candidate this resolves to the tree's first leaf.
        self.primaryPane = paneTree.normalizedPrimary(
            from: [primaryPane?.rawValue].compactMap { $0 }
        ).map(SurfaceID.init(rawValue:))
        self.priority = priority
        self.deadline = deadline
        self.nextTrigger = nextTrigger
        self.createdAt = createdAt
        self.lastFocusedAt = lastFocusedAt
    }

    /// What the note overview shows for this project (`SPEC.md` §21.3, §24):
    /// the note together with the priority, deadline, and next trigger. One
    /// model judgment shared by the overlay and the tests, so "what the
    /// overview displays" cannot drift from what is asserted. The label band
    /// deliberately reads priority/deadline directly and never the next
    /// trigger (§24.6).
    var overviewContent: ProjectOverviewContent {
        ProjectOverviewContent(
            note: note,
            priority: priority,
            deadline: deadline,
            nextTrigger: nextTrigger)
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

    /// Whether `paneID`'s primary flag is set. Exactly one pane per project
    /// answers `true` while the tree is non-empty (SPEC §22.1).
    func isPrimary(_ paneID: SurfaceID) -> Bool {
        primaryPane == paneID
    }

    /// The pane tree the overall (non-zoomed) view renders for this project: a
    /// single-leaf tree holding only the primary pane (SPEC §22.3). The
    /// zoomed local view renders `paneTree` unchanged. An empty project renders
    /// nothing; a missing primary (unreachable while the invariant holds)
    /// falls back to the full tree rather than blanking the project.
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
    ///   `paneTree`, so a stale id can never point the flag outside the project.
    @discardableResult
    mutating func setPrimaryPane(_ paneID: SurfaceID) -> Bool {
        guard paneTree.find(id: paneID.rawValue) != nil else { return false }
        primaryPane = paneID
        return true
    }

    // MARK: Terminated state (SPEC §23.2–23.3)

    /// Whether this project is in the terminated state: its last pane's shell
    /// has exited and the pane is kept instead of closing the project.
    var isTerminated: Bool {
        terminatedPane != nil
    }

    /// Enter the terminated state for `paneID` (`SPEC.md` §23.2): the project's
    /// last pane whose shell exited is kept — with the project and its note —
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
    /// which carries a fresh shell (`SPEC.md` §23.3): the project resumes work
    /// in the same pane slot, keeping its note, name, and layout position.
    ///
    /// - Returns: `false` (and changes nothing) when the project is not
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

extension ProjectStateOf: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case paneTree
        case focusedSurface
        case note
        case primaryPanes
        case priority
        case deadline
        case nextTrigger
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
        self.id = try c.decode(ProjectID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.paneTree = try c.decode(SplitTree<Pane>.self, forKey: .paneTree)
        self.focusedSurface = try c.decodeIfPresent(SurfaceID.self, forKey: .focusedSurface)
        self.note = Self.normalizedNote(try c.decodeIfPresent(String.self, forKey: .note) ?? "")
        let flagged = try c.decodeIfPresent([SurfaceID].self, forKey: .primaryPanes) ?? []
        self.primaryPane = paneTree.normalizedPrimary(
            from: flagged.map(\.rawValue)
        ).map(SurfaceID.init(rawValue:))
        // Priority/deadline follow the invalid-to-unset rule (SPEC §24.1) on
        // the restore path too: a save carrying an unknown priority value or
        // an impossible date decodes as unset rather than rejecting the whole
        // project record.
        self.priority = (try? c.decodeIfPresent(ProjectPriority.self, forKey: .priority)) ?? nil
        self.deadline = (try? c.decodeIfPresent(ProjectDeadline.self, forKey: .deadline)) ?? nil
        // The next trigger follows the same invalid-to-unset rule (SPEC
        // §24.6): an unknown value in a save decodes as unset.
        self.nextTrigger =
            (try? c.decodeIfPresent(ProjectNextTrigger.self, forKey: .nextTrigger)) ?? nil
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
        try c.encodeIfPresent(priority, forKey: .priority)
        try c.encodeIfPresent(deadline, forKey: .deadline)
        try c.encodeIfPresent(nextTrigger, forKey: .nextTrigger)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(lastFocusedAt, forKey: .lastFocusedAt)
    }
}

/// The runtime specialization: pane elements are live surface views.
typealias ProjectState = ProjectStateOf<XGhostty.SurfaceView>

// MARK: Priority (SPEC §24.1)

/// The human-set priority of a project: `high` / `medium` / `low`. "Unset" —
/// the default — is the absence of a value (`ProjectState.priority == nil`),
/// mirroring how the deadline models it, so a fourth case cannot drift from
/// the optional's semantics.
enum ProjectPriority: String, Codable, CaseIterable, Equatable {
    case high
    case medium
    case low

    /// Position of this priority in the priority sort order (SPEC §24.3):
    /// high → medium → low, with unset after all of them (`unsetSortRank`).
    var sortRank: Int {
        switch self {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        }
    }

    /// The sort rank of an unset priority: last (SPEC §24.3).
    static var unsetSortRank: Int { 3 }
}

// MARK: Next trigger (SPEC §24.6)

/// Who or what moves a project next: the human's own action, a team member,
/// someone outside the organization, or an external event. "Unset" — the
/// default — is the absence of a value (`ProjectState.nextTrigger == nil`),
/// mirroring the priority. Human-written workspace information, distinct from
/// any terminal-observed live state.
enum ProjectNextTrigger: String, Codable, CaseIterable, Equatable {
    case myself
    case teamMember
    case externalPerson
    case event

    /// The compact terminal-style readout the note overview and the list
    /// cell show for this value. The bare value carries no prefix: it is
    /// self-evident next to the note (and under the list's "next" header).
    var displayText: String {
        switch self {
        case .myself: return "me"
        case .teamMember: return "team"
        case .externalPerson: return "external"
        case .event: return "event"
        }
    }
}

// MARK: Overview content (SPEC §21.3, §24)

/// The display content of one project's note-overview panel: the note plus
/// the priority, deadline, and next trigger. A pure model value so the
/// overview's "what is shown" is a single testable judgment.
struct ProjectOverviewContent: Equatable {
    let note: String
    let priority: ProjectPriority?
    let deadline: ProjectDeadline?
    let nextTrigger: ProjectNextTrigger?
}

// MARK: Deadline (SPEC §24.1)

/// A project's deadline: a calendar date with no time component (SPEC §24.1).
///
/// Validation is constructive — the failable initializers are the only way to
/// obtain a value, and they reject anything that is not a real Gregorian
/// calendar date, so an invalid deadline (2026-02-30, month 13, garbage text)
/// is unrepresentable and collapses to unset (`nil`) at the model boundary.
struct ProjectDeadline: Codable, Equatable, Hashable, Comparable {
    let year: Int
    let month: Int
    let day: Int

    /// A single date-only value for ordering and equality: later dates are
    /// strictly greater. Also the deadline sort key (SPEC §24.3).
    var ordinalValue: Int { year * 10_000 + month * 100 + day }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.ordinalValue < rhs.ordinalValue
    }

    /// Build from components, rejecting anything that is not a real date on
    /// the Gregorian calendar (leap days included; year bounded to four
    /// digits so the text form stays unambiguous).
    init?(year: Int, month: Int, day: Int) {
        guard (1000...9999).contains(year) else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard components.isValidDate(in: Self.gregorian) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parse user input of the form `YYYY-MM-DD` (or `YYYY/MM/DD`; month and
    /// day may be one or two digits). Anything else — wrong shape, non-digits,
    /// or an impossible date — is `nil`: the save-time rejection of invalid
    /// deadline input (SPEC §24.1).
    init?(parsing input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed
            .replacingOccurrences(of: "/", with: "-")
            .components(separatedBy: "-")
        guard parts.count == 3,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              parts[0].count == 4, parts[1].count <= 2, parts[2].count <= 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// The date-only value of `date` in the current (or given) calendar — the
    /// runtime "today" the overdue judgment compares against (SPEC §24.2).
    init(from date: Date, calendar: Calendar = Calendar.current) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        // Direct member init bypassing validation: real calendar components
        // are a real date by construction.
        self.year = components.year ?? 0
        self.month = components.month ?? 0
        self.day = components.day ?? 0
    }

    /// Whether this deadline is past `today` (SPEC §24.2): strictly earlier —
    /// the deadline's own day is not yet overdue. Date-only comparison; the
    /// single-stage judgment behind the subtle overdue emphasis.
    func isOverdue(today: ProjectDeadline) -> Bool {
        self < today
    }

    /// The canonical `YYYY-MM-DD` text form (also what the editor shows).
    var displayText: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static let gregorian = Calendar(identifier: .gregorian)

    // Codable: persist as the canonical text form so the saved record stays
    // readable, and re-validate on decode — a hand-edited or corrupt save
    // holding an impossible date fails decode, which the project record's
    // lenient decode turns into unset (SPEC §24.1).
    init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = ProjectDeadline(parsing: text) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "invalid deadline: \(text)"))
        }
        self = parsed
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(displayText)
    }
}

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
