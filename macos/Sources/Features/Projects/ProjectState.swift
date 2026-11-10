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
    /// The maximum number of lines a note may hold in storage. Editing input
    /// and paste are never limited; the save operation decides: an over-limit
    /// draft is judged by `noteExceedsLimit` so the UI can ask for
    /// confirmation, and only a confirmed save applies the truncation. The
    /// storage entry points — `init`, `setNote`, and decode — still normalize,
    /// so an over-long note is never retained anywhere.
    static var maxNoteLines: Int { 100 }

    let id: ProjectID
    var name: String

    /// The pane layout for this project. Element type intentionally kept as
    /// `XGhostty.SurfaceView` at runtime (see the type doc above).
    ///
    /// Every replacement re-reconciles the primary flag (SPEC §22.2): panes
    /// added by later splits never take the flag, and when the primary pane
    /// leaves the tree — only an explicit close (Cmd+W) removes a pane; a
    /// command exit keeps it terminated (must 143) — the nearest remaining
    /// leaf is promoted.
    var paneTree: SplitTree<Pane> {
        didSet {
            primaryPane = paneTree.reconciledPrimary(
                previousTree: oldValue,
                previousPrimary: primaryPane?.rawValue
            ).map(SurfaceID.init(rawValue:))
            // A terminated pane stays terminated only while it is in the tree
            // (SPEC §23.2): a pane closed explicitly takes its state with it.
            terminatedPanes = terminatedPanes.filter { paneTree.find(id: $0.rawValue) != nil }
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

    /// The panes held in the terminated state (`SPEC.md` §23.2, must 29): panes
    /// whose command (shell, tmux client, or ssh) has exited. Each stays in the
    /// tree where it was — with or without siblings — and Enter on any of them
    /// restarts all of them (must 30).
    ///
    /// Invariant: a subset of the tree's leaves, maintained by
    /// `markPaneTerminated` and the `paneTree` observer. Runtime-only: never
    /// persisted — a restore re-attaches every pane to its saved session, so a
    /// restored project is live again (`SPEC.md` §23.4).
    private(set) var terminatedPanes: Set<SurfaceID> = []

    /// The display name of the registered terminal this project's panes run
    /// on, or `nil` for the local terminal — the default (must 128).
    /// Persisted like the note. A name no longer registered is kept as is
    /// and resolves to the local terminal (`ProjectTerminalRegistry
    /// .terminal(named:)`), so re-registering it brings the project back.
    var terminalName: String?

    /// How much of the overall view this project takes (must 140): Core — the
    /// default — or Side. Persisted like the note. It changes nothing but
    /// the size in the overall view: the label band, the note overview and the
    /// zoom show no mark for it.
    var kind: ProjectKind

    /// The tmux session each started pane lives in (must 129): its terminal
    /// and pane index, fixed by `bindPane` when the pane is first started.
    ///
    /// Persisted with the pane layout for the panes in `paneTree`, so a
    /// restored pane re-attaches to the same session on the same terminal.
    /// In memory a pane that left the tree keeps its entry: undo may bring it
    /// back, and the session kill after the undo period needs it.
    private(set) var paneBindings: [SurfaceID: TmuxPaneBinding] = [:]

    /// The highest pane index ever handed out in this project. Persisted, so
    /// an index is not reused even after a restart — a session left behind by
    /// a pane closed just before quitting is never attached by a new pane.
    private(set) var lastPaneIndex: Int = 0

    var createdAt: Date
    var lastFocusedAt: Date?

    init(
        id: ProjectID,
        name: String,
        paneTree: SplitTree<Pane>,
        focusedSurface: SurfaceID? = nil,
        note: String = "",
        primaryPane: SurfaceID? = nil,
        terminalName: String? = nil,
        kind: ProjectKind = .core,
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
        self.terminalName = terminalName
        self.kind = kind
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

    /// The save-time over-limit judgment (`SPEC.md` §21.1): whether saving
    /// `raw` would exceed `maxNoteLines` and therefore needs the user's
    /// confirmation before the truncation is applied. Counts lines after the
    /// same newline unification as `normalizedNote`, so a CRLF paste cannot
    /// dodge the judgment. Within the limit, a save stays silent.
    static func noteExceedsLimit(_ raw: String) -> Bool {
        let unified = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return unified.components(separatedBy: "\n").count > maxNoteLines
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

    /// Whether any pane of this project is in the terminated state.
    var isTerminated: Bool {
        !terminatedPanes.isEmpty
    }

    /// Whether `paneID` is in the terminated state.
    func isPaneTerminated(_ paneID: SurfaceID) -> Bool {
        terminatedPanes.contains(paneID)
    }

    /// The terminated panes in tree order — the order a restart replaces them.
    var terminatedPanesInTreeOrder: [SurfaceID] {
        paneTree.compactMap { pane in
            let id = SurfaceID(rawValue: pane.id)
            return terminatedPanes.contains(id) ? id : nil
        }
    }

    /// Enter the terminated state for `paneID` (`SPEC.md` §23.2, must 29):
    /// a pane whose command exited stays in the tree — siblings or not — with
    /// the project, its note, the layout and the primary flag unchanged. A
    /// command exit never closes a pane (must 143) and never promotes another
    /// pane to primary (must 23).
    ///
    /// - Returns: `false` (and changes nothing) unless `paneID` is a leaf of
    ///   the tree.
    @discardableResult
    mutating func markPaneTerminated(_ paneID: SurfaceID) -> Bool {
        guard paneTree.find(id: paneID.rawValue) != nil else { return false }
        terminatedPanes.insert(paneID)
        return true
    }

    /// Restart every terminated pane (`SPEC.md` §23.3, must 30): each dead pane
    /// is replaced in its own slot by the new pane `replacements` maps it to,
    /// which carries the same attach command (must 132). The split layout and
    /// the primary flag stay where they were — a replaced primary hands the
    /// flag to its replacement — and panes that are not terminated are not
    /// touched.
    ///
    /// - Returns: `false` (and changes nothing) when no pane is terminated or
    ///   `replacements` does not map exactly the terminated panes.
    @discardableResult
    mutating func restartTerminatedPanes(with replacements: [SurfaceID: Pane]) -> Bool {
        guard !terminatedPanes.isEmpty,
              Set(replacements.keys) == terminatedPanes else { return false }

        var tree = paneTree
        for (deadPane, newPane) in replacements {
            guard let node = tree.find(id: deadPane.rawValue),
                  let replaced = try? tree.replacing(node: node, with: .leaf(view: newPane))
            else { return false }
            tree = replaced
        }

        let mapped = { (id: SurfaceID?) -> SurfaceID? in
            guard let id, let pane = replacements[id] else { return id }
            return SurfaceID(rawValue: pane.id)
        }
        let primary = mapped(primaryPane)
        let focus = mapped(focusedSurface)

        // The new pane takes over the dead pane's session rather than
        // starting another one.
        for (deadPane, newPane) in replacements {
            let newID = SurfaceID(rawValue: newPane.id)
            if let binding = paneBindings.removeValue(forKey: deadPane), newID != deadPane {
                paneBindings[newID] = binding
            }
        }

        // The tree observer drops the dead panes from `terminatedPanes`; the
        // primary is set after it so the flag stays in the replaced slot
        // instead of being promoted to a neighbor.
        paneTree = tree
        if let primary { primaryPane = primary }
        focusedSurface = focus
        return true
    }

    // MARK: tmux sessions (must 129, 133)

    /// The tmux session of `paneID`, binding it on first use: a pane not yet
    /// bound takes the project's current terminal and the next unused pane
    /// index. A bound pane keeps its binding, so changing the project's
    /// terminal never moves an open pane.
    ///
    /// - Returns: `nil` (and changes nothing) when `paneID` is not a leaf of
    ///   `paneTree`.
    @discardableResult
    mutating func bindPane(_ paneID: SurfaceID) -> TmuxPaneBinding? {
        guard paneTree.find(id: paneID.rawValue) != nil else { return nil }
        return binding(forStarting: paneID)
    }

    /// The binding of `paneID`, binding it to the project's current terminal
    /// and the next unused index if it has none. No tree check: a pane's
    /// surface is created with its attach command, so a new pane is bound
    /// before it joins the tree.
    private mutating func binding(forStarting paneID: SurfaceID) -> TmuxPaneBinding {
        if let existing = paneBindings[paneID] { return existing }
        let index = TmuxSession.nextIndex(
            after: paneBindings.values.map(\.index) + [lastPaneIndex])
        let binding = TmuxPaneBinding(terminalName: terminalName, index: index)
        paneBindings[paneID] = binding
        lastPaneIndex = index
        return binding
    }

    /// The pane command of `paneID`, a pane about to be created in this
    /// project (must 129): bind it (unless already bound) and attach to its
    /// session, starting a new session in `start`.
    mutating func launchCommand(
        forNewPane paneID: SurfaceID,
        start: TmuxStartDirectory,
        registry: ProjectTerminalRegistry
    ) -> String {
        attachCommand(binding: binding(forStarting: paneID), start: start, registry: registry)
    }

    /// The pane command of `newPane`, about to split `origin` (must 130): the
    /// new session starts in the current path of `origin`'s session when
    /// `origin` is bound, otherwise by the project rule.
    mutating func splitLaunchCommand(
        newPane: SurfaceID,
        splitting origin: SurfaceID,
        registry: ProjectTerminalRegistry
    ) -> String {
        let start: TmuxStartDirectory = sessionName(for: origin)
            .map { .inherit(fromSession: $0) } ?? .project
        return launchCommand(forNewPane: newPane, start: start, registry: registry)
    }

    /// The pane command of `newPane`, about to replace the terminated pane
    /// `deadPane` (must 132): the same attach command, re-attaching to the
    /// dead pane's session or creating it again. `restartTerminatedPanes` then
    /// moves the binding over. A dead pane that was never bound (a save from
    /// before tmux sessions) gives the new pane a fresh session.
    ///
    /// - Returns: `nil` (and changes nothing) when `deadPane` is not
    ///   terminated.
    mutating func restartLaunchCommand(
        newPane: SurfaceID,
        replacing deadPane: SurfaceID,
        registry: ProjectTerminalRegistry
    ) -> String? {
        guard terminatedPanes.contains(deadPane) else { return nil }
        if let binding = paneBindings[deadPane] {
            return attachCommand(binding: binding, start: .project, registry: registry)
        }
        return launchCommand(forNewPane: newPane, start: .project, registry: registry)
    }

    /// The attach command of a session on its bound terminal. A terminal no
    /// longer registered resolves to the local one, like the project's.
    func attachCommand(
        binding: TmuxPaneBinding,
        start: TmuxStartDirectory,
        registry: ProjectTerminalRegistry
    ) -> String {
        let terminal = registry.terminal(named: binding.terminalName)
        return TmuxSession.attachCommand(
            session: binding.sessionName(project: id),
            title: name,
            start: start,
            terminal: terminal,
            isLocal: registry.isLocal(terminal))
    }

    /// A new project whose single pane is made by `makePane` from the pane's
    /// id and its attach command (must 129). The pane is bound before it
    /// exists, so the surface starts with the command itself.
    static func new(
        id: ProjectID,
        name: String,
        createdAt: Date,
        lastFocusedAt: Date? = nil,
        registry: ProjectTerminalRegistry,
        makePane: (UUID, String) -> Pane
    ) -> Self {
        var project = Self(id: id, name: name, paneTree: .init(), createdAt: createdAt)
        let paneID = UUID()
        let command = project.launchCommand(
            forNewPane: SurfaceID(rawValue: paneID), start: .project, registry: registry)
        let pane = makePane(paneID, command)
        project.paneTree = SplitTree<Pane>(view: pane)
        project.focusedSurface = SurfaceID(rawValue: pane.id)
        project.lastFocusedAt = lastFocusedAt
        return project
    }

    /// The tmux session name of a bound pane, or `nil` when it is unbound.
    func sessionName(for paneID: SurfaceID) -> String? {
        paneBindings[paneID]?.sessionName(project: id)
    }

    /// The bound panes among `paneIDs`, as recorded when they are closed.
    /// Unbound panes never started a session and have nothing to kill.
    func closedTmuxPanes(_ paneIDs: some Sequence<SurfaceID>) -> [TmuxClosedPane] {
        paneIDs.compactMap { pane in
            paneBindings[pane].map { TmuxClosedPane(project: id, pane: pane, binding: $0) }
        }
    }

    /// Every bound pane of the tree — what closing the whole project records,
    /// a terminated pane included.
    var tmuxPanesInTree: [TmuxClosedPane] {
        closedTmuxPanes(paneTree.map { SurfaceID(rawValue: $0.id) })
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
        case terminal
        case kind
        case paneSessions
        case lastPaneIndex
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
        // Saves written before terminals existed have no key: the local
        // terminal, the default.
        self.terminalName = (try? c.decodeIfPresent(String.self, forKey: .terminal)) ?? nil
        // Saves written before kinds existed have no key, and an unknown value
        // follows the invalid-to-default rule: Core (must 140).
        self.kind = (try? c.decodeIfPresent(ProjectKind.self, forKey: .kind)) ?? .core
        // The saved sessions are read before the tree: a restored surface
        // starts with the attach command of its session (must 129), so the
        // tree is decoded inside `TmuxPaneRestore.decoding`. Saves written
        // before tmux sessions existed have neither key; their panes are bound
        // as they are restored. Entries for panes not in the tree are dropped.
        let sessions = (try? c.decodeIfPresent([PaneSessionRecord].self, forKey: .paneSessions)) ?? []
        var saved: [SurfaceID: TmuxPaneBinding] = [:]
        for record in sessions {
            saved[record.pane] = TmuxPaneBinding(terminalName: record.terminal, index: record.index)
        }
        let storedLast = (try? c.decodeIfPresent(Int.self, forKey: .lastPaneIndex)) ?? nil
        let (tree, restored, restoredLast) = try TmuxPaneRestore.decoding(
            project: id,
            title: name,
            terminalName: terminalName,
            bindings: saved,
            lastIndex: max(storedLast ?? 0, saved.values.map(\.index).max() ?? 0)
        ) {
            try c.decode(SplitTree<Pane>.self, forKey: .paneTree)
        }
        self.paneTree = tree
        self.focusedSurface = try c.decodeIfPresent(SurfaceID.self, forKey: .focusedSurface)
        self.note = Self.normalizedNote(try c.decodeIfPresent(String.self, forKey: .note) ?? "")
        let flagged = try c.decodeIfPresent([SurfaceID].self, forKey: .primaryPanes) ?? []
        self.primaryPane = paneTree.normalizedPrimary(
            from: flagged.map(\.rawValue)
        ).map(SurfaceID.init(rawValue:))
        // Saves written while priorities, deadlines, and next triggers existed
        // still carry `priority` / `deadline` / `nextTrigger`: the keyed
        // container ignores keys it does not declare, so they are dropped
        // silently and never written again (must 145).
        self.paneBindings = restored.filter { tree.find(id: $0.key.rawValue) != nil }
        self.lastPaneIndex = restoredLast
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
        try c.encodeIfPresent(terminalName, forKey: .terminal)
        // Core is the default and writes no key, like the local terminal.
        if kind != .core { try c.encode(kind, forKey: .kind) }
        // Pane sessions ride the same record as the pane layout (must 129),
        // in tree order, only for the panes in the tree.
        let sessions = paneTree.compactMap { pane -> PaneSessionRecord? in
            let id = SurfaceID(rawValue: pane.id)
            return paneBindings[id].map {
                PaneSessionRecord(pane: id, terminal: $0.terminalName, index: $0.index)
            }
        }
        try c.encode(sessions, forKey: .paneSessions)
        try c.encode(lastPaneIndex, forKey: .lastPaneIndex)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(lastFocusedAt, forKey: .lastFocusedAt)
    }

    /// One pane's saved tmux session.
    private struct PaneSessionRecord: Codable {
        let pane: SurfaceID
        let terminal: String?
        let index: Int
    }
}

/// The runtime specialization: pane elements are live surface views.
typealias ProjectState = ProjectStateOf<XGhostty.SurfaceView>

/// A project's kind (must 140): the size class it takes in the overall view.
/// `allCases` is the candidate order, Core then Side.
enum ProjectKind: String, Codable, CaseIterable, Equatable {
    case core
    case side

    /// The spelling the list cell, the candidate menu, and the clipboard share.
    var displayText: String {
        switch self {
        case .core: return "Core"
        case .side: return "Side"
        }
    }

    /// The share of a layout tier's length this kind takes (`SPEC.md` §26.1):
    /// a Side is half a Core.
    var layoutWeight: Double {
        switch self {
        case .core: return 1
        case .side: return 0.5
        }
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
    ///   among the panes that survive into `self`. Only an explicit close
    ///   (Cmd+W) removes a pane; a command exit keeps it (must 143).
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
