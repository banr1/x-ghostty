import Foundation

/// The persistent + runtime state of the project layer for a single terminal
/// window/tab.
///
/// `canonicalProjectTree` is the single source of truth for project placement.
/// Visibility (`hiddenProjectIDs`) and `zoomedProject` are derived display state
/// that must never be persisted (see `SPEC.md` §4.1, §12.2, §13).
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
    /// hard ceiling: `new_project_split` and `show_project` are silently rejected
    /// once it is reached, and a restore caps the visible set at this many
    /// (the extras stay alive on the hidden shelf).
    static var maxVisibleProjects: Int { 9 }

    var version: Int

    /// Canonical placement of every project. Always the source of truth.
    var canonicalProjectTree: SplitTree<ProjectRef>

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

    // MARK: Runtime-only (never persisted; cleared on decode)

    var hiddenProjectIDs: Set<ProjectID> = []
    var focusedProject: ProjectID?
    var zoomedProject: ProjectID?

    init(
        canonicalProjectTree: SplitTree<ProjectRef>,
        projects: [ProjectID: ProjectStateOf<Pane>],
        hiddenProjectIDs: Set<ProjectID> = [],
        focusedProject: ProjectID? = nil,
        zoomedProject: ProjectID? = nil,
        lastPriorityResetWorkday: Workday? = nil,
        version: Int = Self.currentVersion
    ) {
        self.version = version
        self.canonicalProjectTree = canonicalProjectTree
        self.projects = projects
        self.hiddenProjectIDs = hiddenProjectIDs
        self.focusedProject = focusedProject
        self.zoomedProject = zoomedProject
        self.lastPriorityResetWorkday = lastPriorityResetWorkday
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

    /// Every visible project in canonical traversal order.
    ///
    /// Canonical leaves *are* the visible projects (hiding removes the leaf,
    /// §11.7 / §14.3), so iterating `canonicalProjectTree` yields exactly the
    /// visible set. The order is `SplitTree`'s in-order leaf traversal — the
    /// same order `previous`/`next` focus uses — so the numbering matches how
    /// the projects read on screen, left-to-right / top-to-bottom.
    ///
    /// Deliberately derived from the *canonical* tree rather than
    /// `effectiveVisibleProjectTree`: a zoomed project keeps the number it has in
    /// the full layout instead of collapsing to `1`.
    var visibleProjectIDs: [ProjectID] {
        canonicalProjectTree.map(\.id)
    }

    /// The number of currently visible projects. Capped at `maxVisibleProjects`.
    var visibleProjectCount: Int {
        canonicalProjectTree.count
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

    /// The visible projects in priority order (SPEC §24.3): high → medium →
    /// low → unset. A pure ordering judgment — nothing is reordered here; the
    /// sort *actions* (T-027 / SPEC §24.4) apply this order to the real
    /// layout. Stability is explicit: within equal priorities the current
    /// relative order (`visibleProjectIDs`) is preserved. Hidden projects are not
    /// part of the input and therefore can never be affected.
    func priorityOrderedVisibleProjectIDs() -> [ProjectID] {
        stableOrderedVisibleProjectIDs { id in
            projects[id]?.priority?.sortRank ?? ProjectPriority.unsetSortRank
        }
    }

    /// The visible projects in deadline order (SPEC §24.3): nearest date first,
    /// unset last. Same contract as `priorityOrderedVisibleProjectIDs`: pure,
    /// stable within the same date, visible projects only.
    func deadlineOrderedVisibleProjectIDs() -> [ProjectID] {
        stableOrderedVisibleProjectIDs { id in
            projects[id]?.deadline?.ordinalValue ?? Int.max
        }
    }

    /// `visibleProjectIDs` sorted by `key` with explicit stability: ties keep
    /// their current relative order (the standard-library sort does not
    /// document stability, and the stable-tie rule is a spec requirement, so
    /// it is enforced by construction here).
    private func stableOrderedVisibleProjectIDs(key: (ProjectID) -> Int) -> [ProjectID] {
        visibleProjectIDs.enumerated()
            .sorted { a, b in
                let ka = key(a.element)
                let kb = key(b.element)
                if ka != kb { return ka < kb }
                return a.offset < b.offset
            }
            .map(\.element)
    }

    /// Apply `order` to the visible projects' real layout (SPEC §24.4): the
    /// canonical tree keeps its exact shape and every split ratio, and its
    /// leaves are reassigned so traversal order equals `order`. Ordinals
    /// (Cmd+1–9) derive from traversal order, so they follow the new layout
    /// automatically. Hidden projects have no canonical leaf and are untouched.
    /// The sort actions are the only callers — reordering happens exclusively
    /// through an explicit action, never as a side effect of a priority or
    /// deadline change — and the applied order persists until the next sort
    /// because nothing else rewrites the leaf assignment.
    ///
    /// - Returns: whether the layout was reordered (`order` must be a
    ///   permutation of the current visible projects).
    mutating func applyVisibleProjectOrder(_ order: [ProjectID]) -> Bool {
        guard let reordered = canonicalProjectTree.reorderingLeaves(
            to: order.map { ProjectRef(id: $0) }) else { return false }
        canonicalProjectTree = reordered
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

    /// Zero-out the runtime-only fields that must never be persisted or survive
    /// a restore (`SPEC.md` §12.2). Called from both the Codable init and
    /// `restoring(_:)` so the list of reset fields is defined once.
    private mutating func clearRuntimeState() {
        hiddenProjectIDs = []
        zoomedProject = nil
    }

    /// Prune the canonical tree down to `maxVisibleProjects` leaves, moving the
    /// extras onto the hidden shelf.
    ///
    /// Only a legacy save (written before the cap existed) can carry more than
    /// nine canonical leaves. The first nine in traversal order keep their slot
    /// — and therefore their numbers 1..9 — and everything after them becomes a
    /// hidden project: still alive in `projects`, reachable from the shelf, and
    /// with no canonical leaf so invariant §14.3 keeps holding.
    private mutating func capVisibleProjects() {
        let visible = visibleProjectIDs
        guard visible.count > Self.maxVisibleProjects else { return }

        for id in visible.dropFirst(Self.maxVisibleProjects) {
            canonicalProjectTree = canonicalProjectTree.removing(.leaf(view: ProjectRef(id: id)))
            hiddenProjectIDs.insert(id)
        }
    }

    /// Re-attach projects that exist in `projects` but have no leaf in
    /// `canonicalProjectTree`, up to the `maxVisibleProjects` cap.
    ///
    /// Hiding removes a project's leaf from the canonical tree (`SPEC.md` §11.7)
    /// and `hiddenProjectIDs` is never persisted (§12.2), so quitting with hidden
    /// projects would otherwise leave them orphaned in `projects`: alive, restored,
    /// but unreachable. Each one splits the trailing leaf in creation order,
    /// matching where `show_project` puts them (§11.8).
    ///
    /// Only as many orphans as fit under the visible cap are re-attached; the
    /// rest stay hidden and reachable from the shelf, exactly as if the user
    /// had hit the cap interactively.
    private mutating func reconcileOrphanedProjects() {
        let placed = Set(visibleProjectIDs)
        let orphans = projects
            .filter { !placed.contains($0.key) }
            .sorted { ($0.value.createdAt, $0.key.rawValue.uuidString) <
                      ($1.value.createdAt, $1.key.rawValue.uuidString) }

        var visibleCount = placed.count
        for (id, _) in orphans {
            guard visibleCount < Self.maxVisibleProjects else {
                hiddenProjectIDs.insert(id)
                continue
            }

            canonicalProjectTree = canonicalProjectTree.appendingAtTrailingLeaf(ProjectRef(id: id))
            visibleCount += 1
        }
    }

    /// The structural half of a restore, shared by `restoring(_:)` and the
    /// `Codable` init so both paths land on the same shape: runtime state is
    /// zeroed, at most `maxVisibleProjects` projects are visible, and every project
    /// is either a canonical leaf or on the hidden shelf.
    ///
    /// It is deterministic (traversal order, then creation order), so running it
    /// twice — decode then `restoring(_:)` — produces the same result.
    private mutating func applyRestoreLayout() {
        clearRuntimeState()
        capVisibleProjects()
        reconcileOrphanedProjects()
    }

    /// Apply restore semantics to a decoded/saved workspace (`SPEC.md` §12.3).
    ///
    /// Nothing comes back zoomed, and up to `maxVisibleProjects` projects come back
    /// visible: projects that were hidden when the state was saved are re-attached
    /// by splitting the trailing leaf while there is room under the cap, and any
    /// beyond it stay on the hidden shelf (see `applyRestoreLayout`).
    /// `focusedProject` is validated against the surviving projects and the canonical
    /// tree; if it no longer points at a *visible* project — including when the cap
    /// pushed it onto the shelf — it falls back to the canonical tree's first leaf.
    static func restoring(_ saved: Self) -> Self {
        var restored = saved
        restored.applyRestoreLayout()

        let focusValid = restored.focusedProject.map { id in
            restored.projects[id] != nil && restored.canonicalProjectTree.find(id: id) != nil
        } ?? false
        if !focusValid {
            restored.focusedProject = restored.canonicalProjectTree.firstLeaf?.id
        }

        return restored
    }
}

// MARK: Codable

/// The runtime specialization: pane elements are live surface views.
typealias WorkspaceState = WorkspaceStateOf<XGhostty.SurfaceView>

extension WorkspaceStateOf: Codable {
    enum CodingKeys: String, CodingKey {
        // Runtime-only fields (`hiddenProjectIDs`, `zoomedProject`) are intentionally
        // omitted; `focusedProject` is persisted per `SPEC.md` §12.1.
        case version
        case canonicalProjectTree
        case projects
        case focusedProject
        case lastPriorityResetWorkday
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
        self.canonicalProjectTree = try c.decodeIfPresent(SplitTree<ProjectRef>.self, forKey: .canonicalProjectTree)
            ?? legacy.decode(SplitTree<ProjectRef>.self, forKey: .canonicalProjectTree)

        // Dictionaries with non-String/Int keys encode as JSON arrays by
        // default; we persist `projects` as a keyed object using uuid strings so
        // the JSON stays a readable object (see `encode(to:)`).
        let keyed = try c.decodeIfPresent([String: ProjectStateOf<Pane>].self, forKey: .projects)
            ?? legacy.decode([String: ProjectStateOf<Pane>].self, forKey: .projects)
        self.projects = Dictionary(uniqueKeysWithValues: keyed.compactMap { key, value in
            UUID(uuidString: key).map { (ProjectID(rawValue: $0), value) }
        })

        self.focusedProject = try c.decodeIfPresent(ProjectID.self, forKey: .focusedProject)
            ?? legacy.decodeIfPresent(ProjectID.self, forKey: .focusedProject)

        // A save written before the reset existed has no key, and a corrupt one
        // decodes as `nil`: both mean "never reset", so the reset runs once at
        // the next check (`SPEC.md` §28.2).
        self.lastPriorityResetWorkday =
            (try? c.decodeIfPresent(Workday.self, forKey: .lastPriorityResetWorkday)) ?? nil

        // Runtime-only state is always reset on decode (`SPEC.md` §12.2), and
        // projects that were hidden when this was encoded (so absent from the
        // persisted tree) are re-attached — up to the visible cap — so nothing
        // is orphaned. `hiddenProjectIDs` is re-derived here rather than decoded:
        // it stays runtime-only, it is just recomputed from the cap.
        self.applyRestoreLayout()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(canonicalProjectTree, forKey: .canonicalProjectTree)

        let keyed = Dictionary(
            uniqueKeysWithValues: projects.map { ($0.key.rawValue.uuidString, $0.value) }
        )
        try c.encode(keyed, forKey: .projects)

        try c.encodeIfPresent(focusedProject, forKey: .focusedProject)
        try c.encodeIfPresent(lastPriorityResetWorkday, forKey: .lastPriorityResetWorkday)
    }
}
