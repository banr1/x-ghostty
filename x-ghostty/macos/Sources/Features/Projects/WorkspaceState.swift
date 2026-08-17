import Foundation

/// The persistent + runtime state of the project layer for a single terminal
/// window/tab.
///
/// The **project list is the source of truth** (`SPEC.md` §4.1, §27): every
/// project — hidden ones included — sits in one persisted row order
/// (`projectOrder`), visibility is a persisted per-project fact
/// (`hiddenProjectIDs`), and the on-screen arrangement is a *projection*:
/// `canonicalProjectTree` is re-derived from the visible rows in row order and
/// the remembered `layoutType` by `relayout()`, and is never persisted or
/// hand-edited. Ordinals (Cmd+1–9) are the visible rows counted from the top.
/// `zoomedProject` stays runtime-only display state (§12.2, §13).
///
/// Generic over the pane element for the same reason as `ProjectStateOf`:
/// `WorkspaceState` is the runtime specialization, and `XGhosttyTests`
/// exercises the same code with value-type panes.
struct WorkspaceStateOf<Pane: Codable & Identifiable & Equatable> where Pane.ID == UUID {
    static var currentVersion: Int { 1 }

    /// The maximum number of simultaneously *visible* projects.
    ///
    /// Visible projects are numbered 1..9 in the header (`ordinal(of:)`) and are
    /// addressed directly by `goto_project:<1-9>` (Cmd+1..9), so nine is the
    /// hard ceiling: `show_project` is silently rejected once it is reached, a
    /// new project row comes in hidden, and a restore caps the visible set at
    /// this many (the extras stay alive, hidden).
    static var maxVisibleProjects: Int { 9 }

    var version: Int

    /// The arrangement of the visible projects: a projection of
    /// (`projectOrder`, `hiddenProjectIDs`, `layoutType`) rebuilt by
    /// `relayout()` after every ledger change and on restore. Read freely
    /// (rendering, spatial navigation, hit-testing); never assign it to change
    /// placement — change the ledger and relayout.
    private(set) var canonicalProjectTree: SplitTree<ProjectRef>

    /// The list's row order over **every** project, hidden ones included —
    /// the ledger (`SPEC.md` §27.1). Persisted. Invariant: a permutation of
    /// `projects.keys` (see `normalizeLedger`).
    var projectOrder: [ProjectID]

    /// The remembered layout type (`SPEC.md` §26.4). Persisted; wide/row-major
    /// when nothing is saved.
    var layoutType: ProjectLayoutType

    /// The list's column order (`SPEC.md` §27.1). Persisted; the default order
    /// when nothing is saved.
    var listColumnOrder: [ProjectListColumn]

    /// All projects keyed by id. Invariant: every leaf in `canonicalProjectTree`
    /// has a matching entry here (`SPEC.md` §14.1). The converse holds only for
    /// *visible* projects: hiding removes a project's leaf from the canonical tree
    /// while its `ProjectState` (and its live panes) stay here, so the entries not
    /// covered by a leaf are exactly `hiddenProjectIDs` (§14.2).
    var projects: [ProjectID: ProjectStateOf<Pane>]

    /// The workday the daily priority reset last ran for, or `nil` when it never
    /// has (`SPEC.md` §28.2). Persisted — unlike the display state below — so
    /// the "once per workday" rule survives a quit and relaunch, which is the
    /// whole point: an app restarted after the boundary must still reset once,
    /// and one restarted before it must not reset again.
    var lastPriorityResetWorkday: Workday?

    /// The hidden projects — the list's visibility column (`SPEC.md` §27.2).
    /// Persisted: a project hidden at quit comes back hidden.
    var hiddenProjectIDs: Set<ProjectID> = []
    var focusedProject: ProjectID?

    // MARK: Runtime-only (never persisted; cleared on decode)

    var zoomedProject: ProjectID?

    /// Build a state from a ledger. `projectOrder` defaults to `projects` in
    /// creation order; when a `canonicalProjectTree` is given (legacy callers,
    /// tests that describe an arrangement), its traversal order seeds the row
    /// order for the projects it places and the rest follow by creation. The
    /// tree itself is always re-derived from the ledger.
    init(
        canonicalProjectTree: SplitTree<ProjectRef> = .init(),
        projects: [ProjectID: ProjectStateOf<Pane>],
        projectOrder: [ProjectID]? = nil,
        hiddenProjectIDs: Set<ProjectID> = [],
        focusedProject: ProjectID? = nil,
        zoomedProject: ProjectID? = nil,
        lastPriorityResetWorkday: Workday? = nil,
        layoutType: ProjectLayoutType = .default,
        listColumnOrder: [ProjectListColumn] = ProjectListColumn.defaultOrder,
        version: Int = Self.currentVersion
    ) {
        self.version = version
        self.canonicalProjectTree = .init()
        self.projects = projects
        self.projectOrder = projectOrder ?? canonicalProjectTree.map(\.id)
        self.hiddenProjectIDs = hiddenProjectIDs
        self.focusedProject = focusedProject
        self.zoomedProject = zoomedProject
        self.lastPriorityResetWorkday = lastPriorityResetWorkday
        self.layoutType = layoutType
        self.listColumnOrder = listColumnOrder
        // A caller that hands over a tree but no hidden set means "these are
        // the visible ones": everything the tree does not place starts hidden,
        // matching how the old tree-as-truth model read such a state.
        if projectOrder == nil, canonicalProjectTree.count > 0 {
            let placed = Set(canonicalProjectTree.map(\.id))
            for id in projects.keys where !placed.contains(id) {
                self.hiddenProjectIDs.insert(id)
            }
        }
        normalizeLedger()
        relayout()
    }

    /// The tree used for rendering / focus / hit-testing. Derived from
    /// `canonicalProjectTree`, applying zoom (`SPEC.md` §13).
    ///
    /// Hidden projects are already absent from `canonicalProjectTree` (hiding removes
    /// the leaf, §11.7), so the pruning pass below is only a defensive backstop
    /// against a stale `hiddenProjectIDs` entry.
    ///
    /// - Returns `nil` when a zoomed project is no longer renderable (hidden or
    ///   missing from the canonical tree).
    var effectiveVisibleProjectTree: SplitTree<ProjectRef>? {
        if let zoomedProject {
            guard !hiddenProjectIDs.contains(zoomedProject),
                  canonicalProjectTree.find(id: zoomedProject) != nil
            else { return nil }
            return canonicalProjectTree.treeContainingOnly(ProjectRef(id: zoomedProject))
        }

        return canonicalProjectTree.pruningLeaves { hiddenProjectIDs.contains($0.id) }
    }

    // MARK: Project numbering (SPEC §4.1)

    /// Every visible project in **list row order** — the visible rows of the
    /// ledger counted from the top (`SPEC.md` §27.1). This, not the tree's
    /// traversal, defines the ordinals: the layout type places the k-th
    /// visible row into its k-th slot, so the numbering follows the list and
    /// the arrangement follows the numbering. A zoomed project keeps its
    /// number.
    var visibleProjectIDs: [ProjectID] {
        projectOrder.filter { !hiddenProjectIDs.contains($0) }
    }

    /// The number of currently visible projects. Capped at `maxVisibleProjects`.
    var visibleProjectCount: Int {
        visibleProjectIDs.count
    }

    /// Whether `id` is currently hidden: it exists as a project and is in the
    /// hidden set. (Visibility is a ledger fact, not a tree fact.)
    func isProjectHidden(_ id: ProjectID) -> Bool {
        projects[id] != nil && hiddenProjectIDs.contains(id)
    }

    // MARK: Ledger → arrangement (SPEC §26.3)

    /// Re-derive the arrangement from the ledger: the visible rows in row
    /// order take the remembered layout type's slots. Called after every
    /// change to `projectOrder` / `hiddenProjectIDs` / `layoutType` and on
    /// restore. A zoom on a project that is no longer visible is released.
    mutating func relayout() {
        canonicalProjectTree = layoutType.tree(over: visibleProjectIDs)
        if let zoomedProject, hiddenProjectIDs.contains(zoomedProject) || projects[zoomedProject] == nil {
            self.zoomedProject = nil
        }
    }

    /// Repair the ledger invariants after a structural change or a decode:
    /// `projectOrder` is a permutation of `projects.keys` (unknown ids drop,
    /// missing projects append in creation order), the hidden set names only
    /// live projects, at most `maxVisibleProjects` rows are visible (the
    /// extras beyond the ninth visible row become hidden), and at least one
    /// row is visible while any project exists (the first row is shown).
    mutating func normalizeLedger() {
        var seen = Set<ProjectID>()
        var order: [ProjectID] = []
        for id in projectOrder where projects[id] != nil && !seen.contains(id) {
            seen.insert(id)
            order.append(id)
        }
        let missing = projects
            .filter { !seen.contains($0.key) }
            .sorted { ($0.value.createdAt, $0.key.rawValue.uuidString) <
                      ($1.value.createdAt, $1.key.rawValue.uuidString) }
            .map(\.key)
        order += missing
        projectOrder = order

        hiddenProjectIDs = hiddenProjectIDs.filter { projects[$0] != nil }

        var visibleCount = 0
        for id in projectOrder where !hiddenProjectIDs.contains(id) {
            visibleCount += 1
            if visibleCount > Self.maxVisibleProjects {
                hiddenProjectIDs.insert(id)
            }
        }
        if visibleCount == 0, let first = projectOrder.first {
            hiddenProjectIDs.remove(first)
        }
    }

    /// Move `id` to `index` in the row order (clamped), keeping every other
    /// row's relative order. Relayouts. No-op for an unknown id.
    mutating func moveProjectRow(_ id: ProjectID, to index: Int) {
        guard let from = projectOrder.firstIndex(of: id) else { return }
        projectOrder.remove(at: from)
        let clamped = min(max(index, 0), projectOrder.count)
        projectOrder.insert(id, at: clamped)
        relayout()
    }

    /// Insert `project` into the ledger right after row `anchor` (or at the
    /// tail when `anchor` is nil / unknown), visible when fewer than
    /// `maxVisibleProjects` rows are visible and hidden otherwise
    /// (`SPEC.md` §27.4). Relayouts.
    mutating func insertProject(_ project: ProjectStateOf<Pane>, after anchor: ProjectID?) {
        // Judged BEFORE the row goes in: a new row is visible while fewer than
        // `maxVisibleProjects` rows are visible, and hidden only at the cap.
        let wasAtCap = visibleProjectCount >= Self.maxVisibleProjects
        projects[project.id] = project
        let index = anchor.flatMap { projectOrder.firstIndex(of: $0) }.map { $0 + 1 } ?? projectOrder.count
        projectOrder.insert(project.id, at: min(index, projectOrder.count))
        if wasAtCap {
            hiddenProjectIDs.insert(project.id)
        }
        relayout()
    }

    /// Remove `id` from the ledger entirely (`close_project`). Relayouts.
    mutating func removeProject(_ id: ProjectID) {
        projects.removeValue(forKey: id)
        projectOrder.removeAll { $0 == id }
        hiddenProjectIDs.remove(id)
        if focusedProject == id { focusedProject = nil }
        relayout()
    }

    /// Hide / show `id` (`SPEC.md` §27.2). Relayouts. The at-least-one-visible
    /// and the visible-cap rules are the model's to check first
    /// (`canToggleProjectVisibility`); this is the mutation.
    mutating func setProjectHidden(_ id: ProjectID, _ hidden: Bool) {
        guard projects[id] != nil else { return }
        if hidden { hiddenProjectIDs.insert(id) } else { hiddenProjectIDs.remove(id) }
        relayout()
    }

    /// The 1-based display number of `id`, or `nil` when it is not visible.
    /// This is a pure display/addressing derivation — it is never stored into
    /// `ProjectState.name`.
    func ordinal(of id: ProjectID) -> Int? {
        visibleProjectIDs.firstIndex(of: id).map { $0 + 1 }
    }

    /// The visible project with 1-based number `ordinal`, or `nil` when there are
    /// fewer than `ordinal` visible projects. The inverse of `ordinal(of:)`.
    func visibleProjectID(ordinal: Int) -> ProjectID? {
        let ids = visibleProjectIDs
        guard ordinal >= 1, ordinal <= ids.count else { return nil }
        return ids[ordinal - 1]
    }

    /// Every visible project's display number, keyed by id. Computed once per
    /// render pass so the view tree does not do a linear scan per project.
    var projectOrdinals: [ProjectID: Int] {
        var result: [ProjectID: Int] = [:]
        for (index, id) in visibleProjectIDs.enumerated() {
            result[id] = index + 1
        }
        return result
    }

    // MARK: Overall-view display target (SPEC §22.3)

    /// The single pane each project draws in the overall (non-zoomed) view:
    /// exactly the project's primary pane. This is the model-layer judgment the
    /// render path consumes — a project appears here iff it is visible, and its
    /// value is its one flagged pane (a project with an empty pane tree has
    /// nothing to draw and is absent). The zoomed local view does not use
    /// this: it shows the full pane layout as before.
    var overallViewPaneIDs: [ProjectID: SurfaceID] {
        var result: [ProjectID: SurfaceID] = [:]
        for id in visibleProjectIDs {
            if let primary = projects[id]?.primaryPane {
                result[id] = primary
            }
        }
        return result
    }

    // MARK: Primary mark (SPEC §22.6)

    /// The pane that shows the primary mark, keyed by project: the zoomed
    /// project's primary pane, and only while that project holds multiple panes.
    /// Empty in the overall view (which renders nothing but primaries, so a
    /// mark would be noise) and for single-pane projects (the only pane is
    /// trivially the primary).
    var primaryMarkPaneIDs: [ProjectID: SurfaceID] {
        guard let zoomedProject,
              let project = projects[zoomedProject],
              project.paneTree.isSplit,
              let primary = project.primaryPane else { return [:] }
        return [zoomedProject: primary]
    }

    // MARK: Overall-view pane-count badge (SPEC §22.7)

    /// The pane-count badge each project shows in the overall (non-zoomed)
    /// view, keyed by project: the project's total pane count, present only for
    /// visible projects that hold non-primary panes (a split tree, so two or
    /// more panes). The overall view renders nothing but the primary, so this
    /// is the subtle cue that more panes exist behind it. Empty while zoomed
    /// (the local view shows the real layout) and absent for single-pane
    /// projects (there is nothing hidden to point at).
    var overallViewPaneCountBadges: [ProjectID: Int] {
        guard zoomedProject == nil else { return [:] }
        var result: [ProjectID: Int] = [:]
        for id in visibleProjectIDs {
            guard let project = projects[id], project.paneTree.isSplit else { continue }
            result[id] = project.paneTree.count
        }
        return result
    }

    // MARK: Priority / deadline sort orderings & overdue judgment (SPEC §24.2–24.3)

    /// Every row — hidden ones included — in priority order (SPEC §24.3):
    /// high → medium → low → unset. A pure ordering judgment — nothing is
    /// reordered here; the sort *actions* (SPEC §24.4) apply it to the ledger.
    /// Stability is explicit: within equal priorities the current row order
    /// is preserved.
    func priorityOrderedProjectIDs() -> [ProjectID] {
        stableOrderedProjectIDs { id in
            projects[id]?.priority?.sortRank ?? ProjectPriority.unsetSortRank
        }
    }

    /// Every row in deadline order (SPEC §24.3): nearest date first, unset
    /// last. Same contract as `priorityOrderedProjectIDs`: pure, stable
    /// within the same date, hidden rows included.
    func deadlineOrderedProjectIDs() -> [ProjectID] {
        stableOrderedProjectIDs { id in
            projects[id]?.deadline?.ordinalValue ?? Int.max
        }
    }

    /// `projectOrder` sorted by `key` with explicit stability: ties keep
    /// their current relative order (the standard-library sort does not
    /// document stability, and the stable-tie rule is a spec requirement, so
    /// it is enforced by construction here).
    private func stableOrderedProjectIDs(key: (ProjectID) -> Int) -> [ProjectID] {
        projectOrder.enumerated()
            .sorted { a, b in
                let ka = key(a.element)
                let kb = key(b.element)
                if ka != kb { return ka < kb }
                return a.offset < b.offset
            }
            .map(\.element)
    }

    /// Apply `order` — a permutation of every row — as the new ledger order
    /// (SPEC §24.4) and relayout: ordinals are the visible rows counted from
    /// the top, so they follow the sort, and the arrangement follows the
    /// ordinals. The sort actions and the list's manual row moves are the only
    /// callers — reordering happens exclusively through an explicit act,
    /// never as a side effect of a priority or deadline change — and the
    /// applied order persists until the next such act.
    ///
    /// - Returns: whether the order changed (`order` must be a permutation
    ///   of `projectOrder`).
    @discardableResult
    mutating func applyProjectOrder(_ order: [ProjectID]) -> Bool {
        guard order.count == projectOrder.count,
              Set(order) == Set(projectOrder) else { return false }
        guard order != projectOrder else { return false }
        projectOrder = order
        relayout()
        return true
    }

    /// Every project whose deadline is past `today` (SPEC §24.2): the
    /// single-stage overdue set behind the subtle emphasis in the label band
    /// and the note overview. Judged over all projects — the display layers are
    /// already visibility-scoped, and a hidden project's overdue-ness must
    /// survive hiding.
    func overdueProjectIDs(today: ProjectDeadline) -> Set<ProjectID> {
        Set(projects.compactMap { id, project in
            (project.deadline?.isOverdue(today: today) ?? false) ? id : nil
        })
    }

    // MARK: Overall-view focus & pane operations (SPEC §22.4–22.5)

    /// Whether pane-level operations (split, inter-pane focus movement, pane
    /// zoom, resize/equalize) are currently allowed: only while the focused
    /// project is zoomed (SPEC §22.5). In the overall view they are no-ops —
    /// only the primary pane is even rendered there — and a zoom on a
    /// *different* project (a transient divergence) disables them too, since
    /// they would act on an invisible tree.
    var paneOperationsEnabled: Bool {
        zoomedProject != nil && zoomedProject == focusedProject
    }

    /// While in the overall (non-zoomed) view, keyboard input and focus always
    /// go to the focused project's primary pane (SPEC §22.4): it is the only
    /// pane rendered. Called after every mutation that can land the state in
    /// the overall view, so a zoom release — or any focus move outside zoom —
    /// snaps the stored focus onto the primary. No-op while zoomed, and for
    /// an empty pane tree (no primary to snap to).
    mutating func snapFocusToPrimaryInOverallView() {
        guard zoomedProject == nil,
              let id = focusedProject,
              var project = projects[id],
              let primary = project.primaryPane,
              project.focusedSurface != primary else { return }
        project.focusedSurface = primary
        projects[id] = project
    }

    // MARK: Mutations

    /// Persist `paneTree` into the focused project. No-op when nothing is focused.
    /// Called before every focused-project switch so the outgoing project's layout
    /// is not lost.
    mutating func saveOutgoingPaneTree(_ paneTree: SplitTree<Pane>) {
        guard let id = focusedProject, var project = projects[id] else { return }
        project.paneTree = paneTree
        projects[id] = project
    }

    // MARK: Restore (SPEC §12.3)

    /// Apply restore semantics to a decoded/saved workspace (`SPEC.md` §12.3):
    /// the ledger is normalized (permutation of the projects, hidden set over
    /// live projects, at most `maxVisibleProjects` visible, at least one
    /// visible), nothing comes back zoomed, the arrangement is re-derived
    /// from the ledger and the remembered layout type, and `focusedProject`
    /// is validated against the visible projects — falling back to the first
    /// visible row.
    static func restoring(_ saved: Self) -> Self {
        var restored = saved
        restored.zoomedProject = nil
        restored.normalizeLedger()
        restored.relayout()

        let focusValid = restored.focusedProject.map { id in
            restored.projects[id] != nil && !restored.hiddenProjectIDs.contains(id)
        } ?? false
        if !focusValid {
            restored.focusedProject = restored.visibleProjectIDs.first
        }

        return restored
    }
}

// MARK: Codable

/// The runtime specialization: pane elements are live surface views.
typealias WorkspaceState = WorkspaceStateOf<XGhostty.SurfaceView>

extension WorkspaceStateOf: Codable {
    enum CodingKeys: String, CodingKey {
        // `zoomedProject` is runtime-only and intentionally omitted; the
        // arrangement (`canonicalProjectTree`) is a projection of the ledger
        // and is not persisted either — it is rebuilt on decode. It is still
        // *read* from older saves to seed the row order.
        case version
        case canonicalProjectTree
        case projects
        case projectOrder
        case hiddenProjectIDs
        case focusedProject
        case lastPriorityResetWorkday
        case layoutType
        case listColumnOrder
    }

    /// Pre-rename key spellings ("group" vocabulary). Workspaces saved before
    /// the project rename decode through these so no persisted state is lost;
    /// `encode(to:)` always writes the current keys.
    private enum LegacyCodingKeys: String, CodingKey {
        case canonicalProjectTree = "canonicalGroupTree"
        case projects = "groups"
        case focusedProject = "focusedGroup"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        self.version = try c.decodeIfPresent(Int.self, forKey: .version)
            ?? Self.currentVersion

        // Dictionaries with non-String/Int keys encode as JSON arrays by
        // default; we persist `projects` as a keyed object using uuid strings so
        // the JSON stays a readable object (see `encode(to:)`).
        let keyed = try c.decodeIfPresent([String: ProjectStateOf<Pane>].self, forKey: .projects)
            ?? legacy.decode([String: ProjectStateOf<Pane>].self, forKey: .projects)
        self.projects = Dictionary(uniqueKeysWithValues: keyed.compactMap { key, value in
            UUID(uuidString: key).map { (ProjectID(rawValue: $0), value) }
        })

        // A save written before the ledger existed carries only the tree: its
        // traversal order seeds the row order (the projects it placed were the
        // visible ones) and everything else was hidden at quit.
        let savedTree = (try? c.decodeIfPresent(SplitTree<ProjectRef>.self, forKey: .canonicalProjectTree))
            ?? (try? legacy.decodeIfPresent(SplitTree<ProjectRef>.self, forKey: .canonicalProjectTree))
            ?? nil
        if let order = try c.decodeIfPresent([ProjectID].self, forKey: .projectOrder) {
            self.projectOrder = order
            self.hiddenProjectIDs = (try? c.decodeIfPresent(Set<ProjectID>.self, forKey: .hiddenProjectIDs)) ?? []
        } else if let savedTree {
            self.projectOrder = savedTree.map(\.id)
            let placed = Set(self.projectOrder)
            self.hiddenProjectIDs = Set(self.projects.keys.filter { !placed.contains($0) })
        } else {
            self.projectOrder = []
            self.hiddenProjectIDs = []
        }
        self.canonicalProjectTree = .init()

        self.focusedProject = try c.decodeIfPresent(ProjectID.self, forKey: .focusedProject)
            ?? legacy.decodeIfPresent(ProjectID.self, forKey: .focusedProject)

        // A save written before the reset existed has no key, and a corrupt one
        // decodes as `nil`: both mean "never reset", so the reset runs once at
        // the next check (`SPEC.md` §28.2).
        self.lastPriorityResetWorkday =
            (try? c.decodeIfPresent(Workday.self, forKey: .lastPriorityResetWorkday)) ?? nil

        // No saved type / column order (or a corrupt one) means the defaults
        // (`SPEC.md` §26.4, §27.1).
        self.layoutType = (try? c.decodeIfPresent(ProjectLayoutType.self, forKey: .layoutType)) ?? .default
        let columns = (try? c.decodeIfPresent([ProjectListColumn].self, forKey: .listColumnOrder)) ?? nil
        self.listColumnOrder = ProjectListColumn.normalizedOrder(columns ?? ProjectListColumn.defaultOrder)
        self.zoomedProject = nil

        // Runtime-only state is always reset on decode (`SPEC.md` §12.2) and
        // the arrangement is a projection of the ledger, so it is rebuilt.
        normalizeLedger()
        relayout()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)

        let keyed = Dictionary(
            uniqueKeysWithValues: projects.map { ($0.key.rawValue.uuidString, $0.value) }
        )
        try c.encode(keyed, forKey: .projects)
        try c.encode(projectOrder, forKey: .projectOrder)
        try c.encode(hiddenProjectIDs, forKey: .hiddenProjectIDs)

        try c.encodeIfPresent(focusedProject, forKey: .focusedProject)
        try c.encodeIfPresent(lastPriorityResetWorkday, forKey: .lastPriorityResetWorkday)
        try c.encode(layoutType, forKey: .layoutType)
        try c.encode(listColumnOrder, forKey: .listColumnOrder)
    }
}
