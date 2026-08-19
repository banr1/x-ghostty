import Foundation

/// Drives the project layer for a single terminal window/tab.
///
/// `surfaceTree` on `BaseTerminalController` remains the source of truth for the
/// *focused* project's panes; this model mirrors it (via `replaceFocusedPaneTree`
/// from `surfaceTreeDidChange`) and owns the project structure around it. As of
/// Phase 2 it is an `ObservableObject` so the project-aware render path
/// (`TerminalWorkspaceView`) re-renders on project-structure changes that do not
/// flow through a `surfaceTree` change (e.g. switching the focused project, and —
/// later — rename). See `SPEC.md` §6.2.
///
/// Generic over the pane element for the same reason as `ProjectStateOf`:
/// `WorkspaceModel` is the runtime specialization, and `XGhosttyTests`
/// exercises the same code with value-type panes.
final class WorkspaceModelOf<Pane: Codable & Identifiable & Equatable>: ObservableObject where Pane.ID == UUID {
    // The error and outcome enums live outside the class (below) so their
    // Sendable conformance does not pick up a `Pane: Sendable` requirement
    // from the generic context; these aliases keep the established
    // `WorkspaceModel.WorkspaceError` / `.CloseProjectOutcome` spelling working.
    typealias WorkspaceError = WorkspaceModelError
    typealias CloseProjectOutcome = WorkspaceCloseProjectOutcome
    typealias ChildExitOutcome = WorkspaceChildExitOutcome

    @Published private(set) var state: WorkspaceStateOf<Pane>

    /// The project currently in inline-rename mode, or `nil`. Transient UI state:
    /// it lives on the model (not in `WorkspaceState`) so it is never persisted.
    /// Both the double-click gesture and the `rename_project` action set this, so
    /// they share one editing path (`SPEC.md` §7.1).
    @Published var renamingProject: ProjectID?

    /// The project whose note editor overlay is open, or `nil`. Transient UI
    /// state like `renamingProject`: it lives on the model (not in
    /// `WorkspaceState`) so it is never persisted. Set by the
    /// `edit_project_note` action (`SPEC.md` §21.2).
    @Published var noteEditingProject: ProjectID?

    /// Whether the read-only note overview is active (`toggle_note_overview`,
    /// `SPEC.md` §21.3). Transient UI state like `renamingProject`; never
    /// persisted. While active, note editing and focus moves are no-ops —
    /// the mode is viewing-only.
    @Published private(set) var noteOverviewActive = false

    /// Whether the layout-selection overlay (`choose_project_layout`, Cmd+L,
    /// `SPEC.md` §26) is up. Transient UI state like `noteOverviewActive`;
    /// never persisted.
    @Published private(set) var layoutSelectionActive = false

    /// Whether the project-list overlay (`list_projects`, Cmd+L, `SPEC.md`
    /// §27) is up. Transient UI state like `noteOverviewActive`; never
    /// persisted.
    @Published private(set) var projectListActive = false

    /// Whether the list is showing every note in full instead of first lines
    /// only (`toggle_note_overview` inside the list, `SPEC.md` §27.2).
    /// Viewing-only and transient: never persisted, and every list session
    /// starts back at first-lines-only.
    @Published private(set) var projectListFullNotes = false

    /// The just-created project whose title cell the list should open in
    /// edit mode (`Cmd+N`, `SPEC.md` §27.4), or `nil`. Transient UI state
    /// like `renamingProject`: set by `insertProjectFromList`, consumed by
    /// the overlay once it has seated the cursor, never persisted.
    @Published private(set) var projectListPendingTitleEdit: ProjectID?

    /// Whether any workspace-modal overlay session (note overview, layout
    /// selection, project list) currently owns the interaction: while one is
    /// up, focus moves and note editing are no-ops, and no other
    /// overlay may open. The note *editor* is not in this set — it locks less
    /// (see the individual guards).
    private var overlaySessionActive: Bool {
        noteOverviewActive
            || layoutSelectionActive
            || projectListActive
    }

    /// An empty workspace with no projects. Used as the controller's initial
    /// value before `init(wrapping:)` wraps the real pane tree.
    init() {
        state = WorkspaceStateOf<Pane>(canonicalProjectTree: .init(), projects: [:])
    }

    /// Construct a model around an existing `WorkspaceState`. Used to rehydrate a
    /// decoded state on restore (`SPEC.md` §12.3) and by tests that need to set
    /// up multi-project / zoomed / hidden states directly.
    init(_ state: WorkspaceStateOf<Pane>) {
        self.state = state
    }

    /// Wrap an existing single pane tree into one default project (Phase 0).
    ///
    /// The first project also gets a random `adjective-noun` name from
    /// `ProjectNameGenerator` (there are no existing names to avoid). Names are
    /// generated only at creation; restore reuses the stored name and never
    /// regenerates (`SPEC.md` §8). `name` is injectable so tests stay
    /// deterministic; production passes `nil` to draw a random name.
    init(
        wrapping paneTree: SplitTree<Pane>,
        now: Date = Date(),
        name: String? = nil
    ) {
        let projectID = ProjectID()
        let focused = paneTree.firstLeaf.map { SurfaceID(rawValue: $0.id) }

        let project = ProjectStateOf<Pane>(
            id: projectID,
            name: name ?? ProjectNameGenerator.make(existing: []),
            paneTree: paneTree,
            focusedSurface: focused,
            createdAt: now,
            lastFocusedAt: focused == nil ? nil : now
        )

        state = WorkspaceStateOf<Pane>(
            canonicalProjectTree: .init(view: ProjectRef(id: projectID)),
            projects: [projectID: project],
            focusedProject: projectID
        )
    }

    // MARK: Focused project access

    var focusedProjectState: ProjectStateOf<Pane>? {
        guard let id = state.focusedProject else { return nil }
        return state.projects[id]
    }

    var focusedPaneTree: SplitTree<Pane> {
        get { focusedProjectState?.paneTree ?? .init() }
        set { replaceFocusedPaneTree(newValue) }
    }

    /// Mirror a new pane tree into the focused project, keeping `focusedSurface`
    /// consistent: an explicit focus wins; otherwise a still-present stored
    /// focus is kept; otherwise it falls back to the first leaf.
    func replaceFocusedPaneTree(
        _ paneTree: SplitTree<Pane>,
        focusedSurface: Pane? = nil,
        now: Date = Date()
    ) {
        guard let id = state.focusedProject, var project = state.projects[id] else { return }

        project.paneTree = paneTree

        if let focusedSurface, paneTree.find(id: focusedSurface.id) != nil {
            project.focusedSurface = SurfaceID(rawValue: focusedSurface.id)
            project.lastFocusedAt = now
        } else if let stored = project.focusedSurface,
                  paneTree.find(id: stored.rawValue) != nil {
            // Keep the existing stored focus; it is still present in the tree.
        } else {
            project.focusedSurface = paneTree.firstLeaf.map { SurfaceID(rawValue: $0.id) }
            if project.focusedSurface != nil { project.lastFocusedAt = now }
        }

        state.projects[id] = project
        // In the overall view the only rendered — and therefore focusable —
        // pane is the primary, so the mirrored focus follows it (SPEC §22.4).
        // This is what moves focus onto the promoted primary when the old one
        // left the tree (shell exit / Cmd+W / process death) outside zoom.
        state.snapFocusToPrimaryInOverallView()
    }

    /// Record the focused surface for the focused project. Ignored when the
    /// surface is not part of the focused project's pane tree. In the overall
    /// (non-zoomed) view focus always lands on the primary pane (SPEC §22.4):
    /// an attempt to record any other pane snaps back to the primary.
    func setFocusedSurface(_ surfaceID: SurfaceID?, now: Date = Date()) {
        guard let projectID = state.focusedProject, var project = state.projects[projectID] else { return }
        if let surfaceID, project.paneTree.find(id: surfaceID.rawValue) == nil { return }

        project.focusedSurface = surfaceID
        if surfaceID != nil { project.lastFocusedAt = now }
        state.projects[projectID] = project
        state.snapFocusToPrimaryInOverallView()
    }

    // MARK: Project numbering & the visible-project cap (SPEC §4.1)

    /// The 1-based display number of `id`, or `nil` when it is not visible.
    /// Convenience over `WorkspaceState.ordinal(of:)` for call sites that only
    /// hold the model.
    func ordinal(of id: ProjectID) -> Int? {
        state.ordinal(of: id)
    }

    /// Whether another project can become visible, i.e. whether fewer than
    /// `WorkspaceState.maxVisibleProjects` are visible right now. Gates
    /// `show_project` and the visible entry of project creation; at the cap
    /// a new row comes in hidden and a show is a silent no-op.
    var canAddVisibleProject: Bool {
        state.visibleProjectCount < WorkspaceStateOf<Pane>.maxVisibleProjects
    }

    // MARK: Project structure

    /// Open `newProject` as a sibling of the currently focused project and switch
    /// focus to it (`SPEC.md` §11.1). This is the single place project switching
    /// happens, so ordering is handled here once:
    ///
    /// 1. Clear any zoom (`SPEC.md` §18.4: zoomed projects un-zoom first).
    /// 2. Persist the outgoing focused project's live pane tree, captured by the
    ///    caller from `surfaceTree` *before* the switch.
    /// 3. Insert `newProject`'s row right below the focused project's in the
    ///    ledger; the arrangement re-derives from the ledger (`SPEC.md` §26.3),
    ///    so `direction` no longer chooses a position.
    /// 4. Switch `focusedProject` to `newProject`.
    ///
    /// The caller is then responsible for swapping `surfaceTree` to
    /// `newProject.paneTree` and moving keyboard focus into its initial pane.
    ///
    /// - Throws: `WorkspaceError.noFocusedProject` if nothing is focused, or
    ///   `WorkspaceError.visibleProjectLimitReached` when
    ///   `WorkspaceState.maxVisibleProjects` are already visible. The model is
    ///   left unchanged on throw.
    func openNewProject(
        _ newProject: ProjectStateOf<Pane>,
        direction: SplitTree<ProjectRef>.NewDirection,
        savingOutgoingPaneTree outgoing: SplitTree<Pane>
    ) throws {
        guard let anchorID = state.focusedProject else {
            throw WorkspaceError.noFocusedProject
        }
        // At the cap the new project would have no number, so refuse. Callers
        // gate on `canAddVisibleProject` first; this is the backstop.
        guard canAddVisibleProject else {
            throw WorkspaceError.visibleProjectLimitReached
        }

        var next = state

        // §18.4: a new project split un-zooms first.
        next.zoomedProject = nil

        // Persist the outgoing focused project's panes before switching away.
        next.saveOutgoingPaneTree(outgoing)

        // The new row lands right below the focused one; `canAddVisibleProject`
        // above guarantees it comes in visible.
        next.insertProject(newProject, after: anchorID)
        next.focusedProject = newProject.id

        state = next
    }

    /// Switch the focused project to `id`, persisting the outgoing focused project's
    /// live pane tree first (captured by the caller from `surfaceTree`). This is
    /// the click-to-focus counterpart of `openNewProject` and the machinery
    /// `goto_project` (Phase 4) builds on.
    ///
    /// - Returns: the target project's stored last-focused surface so the caller
    ///   can move keyboard focus into it (`SPEC.md` §14.12), or `nil` when the
    ///   switch is a no-op (already focused, or `id` is not a known project).
    @discardableResult
    func switchFocusedProject(
        to id: ProjectID,
        savingOutgoingPaneTree outgoing: SplitTree<Pane>
    ) -> SurfaceID? {
        // No focus moves while an overlay session (note overview,
        // hide-selection, layout screens) owns the interaction.
        guard !overlaySessionActive else { return nil }
        guard id != state.focusedProject else { return nil }
        guard state.projects[id] != nil else { return nil }

        var next = state
        next.saveOutgoingPaneTree(outgoing)
        next.focusedProject = id
        // Outside zoom, focus entering a project lands on its primary pane
        // (SPEC §22.4) rather than the stored last-focused pane.
        next.snapFocusToPrimaryInOverallView()
        state = next

        return state.projects[id]?.focusedSurface
    }

    // MARK: Project navigation & layout (Phase 4)

    /// Resolve the project that `goto_project` in `direction` should focus, using the
    /// visible project tree (`SPEC.md` §11.3). Hidden projects are excluded because
    /// the tree is already pruned to visible leaves.
    ///
    /// - Returns: the target project, or `nil` when the move is a no-op: a project is
    ///   zoomed (§11.3 says no-op while zoomed), there is no focused project, there
    ///   is no neighbor in that direction, or the resolved target is the focused
    ///   project itself (e.g. `next`/`previous` wrapping with a single project).
    func gotoProjectTarget(_ direction: SplitTree<ProjectRef>.FocusDirection) -> ProjectID? {
        // No focus moves while an overlay session (note overview,
        // hide-selection, layout screens) owns the interaction.
        guard !overlaySessionActive else { return nil }
        guard state.zoomedProject == nil else { return nil }
        guard let focusedID = state.focusedProject else { return nil }
        guard let visibleTree = state.effectiveVisibleProjectTree,
              let node = visibleTree.find(id: focusedID) else { return nil }

        guard let target = visibleTree.focusTarget(for: direction, from: node),
              target.id != focusedID else { return nil }
        return target.id
    }

    /// Resolve the project that `goto_project:<N>` should focus: the `index`-th
    /// visible project in canonical traversal order (1-based), or `nil` when the
    /// jump would do nothing.
    ///
    /// Unlike the directional `goto_project`, an index jump is *not* a no-op while
    /// zoomed (`SPEC.md` §11.3 only pins the directional form): jumping to a
    /// different project clears the zoom and lands there, so Cmd+1..9 always gets
    /// you to the project you asked for. Jumping to the zoomed project itself keeps
    /// the zoom.
    ///
    /// - Returns: `nil` when there is no `index`-th visible project, when it is
    ///   already the zoomed project, or — when nothing is zoomed — when it is
    ///   already the focused project. Callers use this both to perform the jump
    ///   and to answer the keybind's performability check, so the two always
    ///   agree on what counts as a no-op.
    func gotoProjectIndexTarget(_ index: Int) -> ProjectID? {
        // No focus moves while an overlay session (note overview,
        // hide-selection, layout screens) owns the interaction.
        guard !overlaySessionActive else { return nil }
        guard let target = state.visibleProjectID(ordinal: index) else { return nil }

        if let zoomedProject = state.zoomedProject {
            return target == zoomedProject ? nil : target
        }
        return target == state.focusedProject ? nil : target
    }

    /// Jump to the `index`-th visible project (`goto_project:<N>`, 1-based).
    ///
    /// Un-zoom and switch are applied together in one state write so the
    /// un-zoomed multi-project layout and the new focused project land in the same
    /// render pass. The outgoing focused project's live panes are persisted first,
    /// exactly like `switchFocusedProject`.
    ///
    /// - Returns: the target project and its stored last-focused surface so the
    ///   caller can swap `surfaceTree` and move keyboard focus, or `nil` when the
    ///   jump is a no-op (see `gotoProjectIndexTarget`).
    @discardableResult
    func gotoProject(
        index: Int,
        savingOutgoingPaneTree outgoing: SplitTree<Pane>
    ) -> (target: ProjectID, focus: SurfaceID?)? {
        guard let target = gotoProjectIndexTarget(index) else { return nil }

        var next = state
        // Any zoom is cleared: the target is (usually) a different project, and a
        // zoomed project is the only one rendered.
        next.zoomedProject = nil
        if target != next.focusedProject {
            next.saveOutgoingPaneTree(outgoing)
            next.focusedProject = target
        }
        // The jump lands in the overall view, where focus goes to the primary
        // pane (SPEC §22.4).
        next.snapFocusToPrimaryInOverallView()
        state = next

        return (target, state.projects[target]?.focusedSurface)
    }

    /// Whether `move_project` in `direction` would swap anything. Shares
    /// `gotoProjectTarget`'s resolution, so the two actions always agree on what
    /// counts as a neighbor.
    func canMoveFocusedProject(_ direction: SplitTree<ProjectRef>.FocusDirection) -> Bool {
        gotoProjectTarget(direction) != nil
    }

    /// Swap the focused project with its neighbor in `direction` (`move_project`).
    ///
    /// The neighbor is resolved exactly like `goto_project` (spatial for
    /// up/down/left/right, in-order traversal for previous/next), then the two
    /// projects' *ledger rows* trade places: the arrangement is a projection of
    /// the row order (`SPEC.md` §26.3), and a swap of two visible rows swaps
    /// exactly their slots, so the layout does not reflow — the two projects
    /// simply trade places (and ordinals). Focus follows the moved project to
    /// its new slot, so `focusedProject` is unchanged.
    ///
    /// - Returns: `true` if the projects were swapped, `false` when the move is a
    ///   no-op (zoomed, no focused project, or no neighbor in that direction), so
    ///   the caller can leave the keybind unconsumed.
    @discardableResult
    func moveFocusedProject(_ direction: SplitTree<ProjectRef>.FocusDirection) -> Bool {
        guard let focusedID = state.focusedProject else { return false }
        guard let targetID = gotoProjectTarget(direction) else { return false }
        var order = state.projectOrder
        guard let a = order.firstIndex(of: focusedID),
              let b = order.firstIndex(of: targetID) else { return false }

        order.swapAt(a, b)
        return state.applyProjectOrder(order)
    }

    // MARK: Zoom / hide / show (Phase 5)

    /// Whether `toggle_project_zoom` would change anything (`SPEC.md` §11.6).
    /// Any focused project can be zoomed: since the overall view renders only
    /// each project's primary pane and disables pane operations (SPEC §22.3,
    /// §22.5), zoom is the gateway to a project's full pane layout — meaningful
    /// even when it is the only visible project. (Before the primary-pane layer
    /// this declined for a single visible project, whose zoom changed nothing.)
    var canToggleProjectZoom: Bool {
        state.focusedProject != nil
    }

    /// Toggle project-level zoom for the focused project (`SPEC.md` §11.6). Zoom is
    /// a derived display state: it only flips `zoomedProject`, and rendering reacts
    /// via `effectiveVisibleProjectTree`. Project zoom and inner split zoom compose
    /// (outer→inner, §14.15) because the inner pane tree keeps its own
    /// `zoomed` node. The focused project is always visible, so the §14.5 "zoom is
    /// visible-only" invariant holds.
    ///
    /// Releasing the zoom lands in the overall view, so focus snaps to the
    /// primary pane if it was on any other pane (SPEC §22.4).
    func toggleProjectZoom() {
        guard let focusedID = state.focusedProject else { return }
        state.zoomedProject = (state.zoomedProject == focusedID) ? nil : focusedID
        state.snapFocusToPrimaryInOverallView()
    }

    /// The project that would receive focus if `id` were hidden: the nearest other
    /// leaf in the canonical tree, or `nil` when `id` is the last visible project
    /// (`SPEC.md` §18.2). Computed on the canonical tree (ignoring zoom) because
    /// a hide un-zooms first (§18.3), and *before* the hide removes `id`'s leaf
    /// so "nearest" is still measured from where `id` actually sits.
    ///
    /// Every canonical leaf is a visible project (hidden ones have no leaf), so no
    /// extra visibility filter is needed; `nearestLeaf` already excludes `id`.
    private func neighborAfterHiding(_ id: ProjectID) -> ProjectRef? {
        state.canonicalProjectTree.nearestLeaf(
            to: ProjectRef(id: id),
            matching: { !state.hiddenProjectIDs.contains($0.id) })
    }

    /// Whether `hide_project` would succeed for the focused project (`SPEC.md`
    /// §18.2, §25): at least one other project must remain visible afterwards,
    /// and neither the note editor nor an overlay session may be up (each
    /// overlay owns the keyboard alone). Callers use this both to hide and to
    /// answer the keybind's performability check, so the two always agree.
    var canHideFocusedProject: Bool {
        guard noteEditingProject == nil, !overlaySessionActive else { return false }
        guard let id = state.focusedProject else { return false }
        return neighborAfterHiding(id) != nil
    }

    /// Hide the focused project immediately (`hide_project`, Cmd+Opt+H,
    /// `SPEC.md` §11.7, §18.2–3, §25 — no selection screen). Its ledger row's
    /// visibility flips, the arrangement re-derives without it so the remaining
    /// projects reclaim its space, and focus moves to the nearest remaining
    /// project. Its `ProjectState` — including its pane tree and live surfaces —
    /// stays in `projects`, so the processes stay alive (invariant §14.7), and
    /// its row keeps its position: showing it later brings it back in place.
    ///
    /// The caller passes the outgoing focused project's live panes; they are
    /// persisted into `projects` (the hidden project keeps its layout) before focus
    /// moves away. A hidden project cannot stay zoomed, so any zoom is cleared
    /// (§18.3).
    ///
    /// - Returns: the neighbor project to focus next and its last-focused surface
    ///   so the caller can swap `surfaceTree` and move keyboard focus, or `nil`
    ///   when the hide is rejected (no focused project, it is the last visible
    ///   project (§18.2), or an overlay owns the keyboard).
    @discardableResult
    func hideFocusedProject(
        savingOutgoingPaneTree outgoing: SplitTree<Pane>
    ) -> (target: ProjectID, focus: SurfaceID?)? {
        guard canHideFocusedProject, let hideID = state.focusedProject else { return nil }
        guard let neighbor = neighborAfterHiding(hideID) else { return nil }

        var next = state

        // The hidden project keeps its current layout alive in `projects`.
        next.saveOutgoingPaneTree(outgoing)

        // The row keeps its ledger position; only its visibility flips, and the
        // arrangement re-derives without it (a zoom on it is released by the
        // relayout, §18.3).
        next.setProjectHidden(hideID, true)
        next.focusedProject = neighbor.id
        // Outside zoom the neighbor's focus lands on its primary (SPEC §22.4).
        next.snapFocusToPrimaryInOverallView()
        state = next

        return (neighbor.id, state.projects[neighbor.id]?.focusedSurface)
    }

    /// The id of a hidden project named `name`, if any. Resolves the
    /// `show_project:<name>` action's argument to a concrete project; the shelf
    /// shows projects by id directly (`SPEC.md` §7.2, §11.8).
    func hiddenProjectID(named name: String) -> ProjectID? {
        state.projects.first { id, project in
            state.hiddenProjectIDs.contains(id) && project.name == name
        }?.key
    }

    /// Whether `show_project` would actually reveal `id`: it must be a live hidden
    /// project, and there must be room under the `WorkspaceState.maxVisibleProjects`
    /// cap. At the cap the reveal is rejected silently and the pill stays on the
    /// shelf, so callers check this before touching `surfaceTree` or registering
    /// an undo.
    func canShowProject(_ id: ProjectID) -> Bool {
        guard state.hiddenProjectIDs.contains(id), state.projects[id] != nil else { return false }
        return canAddVisibleProject
    }

    /// Show the hidden project `id` (`SPEC.md` §11.8): flip its visibility,
    /// clear any zoom, and focus it.
    ///
    /// The project returns to its *own ledger row* — the row never moved while
    /// hidden — so the arrangement re-derives with it back in place and every
    /// ordinal follows the row order (`SPEC.md` §27.1).
    ///
    /// Like `switchFocusedProject`, the caller passes the outgoing focused project's
    /// live panes so they are persisted before focus moves away.
    ///
    /// - Returns: the shown project's last-focused surface so the caller can move
    ///   keyboard focus into it, or `nil` when the reveal is rejected — `id` is
    ///   not currently hidden, or the visible-project cap is already reached.
    @discardableResult
    func showProject(
        _ id: ProjectID,
        savingOutgoingPaneTree outgoing: SplitTree<Pane>
    ) -> SurfaceID? {
        guard canShowProject(id) else { return nil }

        var next = state
        next.saveOutgoingPaneTree(outgoing)
        next.setProjectHidden(id, false)
        next.zoomedProject = nil
        next.focusedProject = id
        // The reveal lands in the overall view, so the shown project's focus
        // goes to its primary pane (SPEC §22.4).
        next.snapFocusToPrimaryInOverallView()
        state = next

        return state.projects[id]?.focusedSurface
    }

    // MARK: Project list (SPEC §27)

    /// Whether `list_projects` can open the project list (`SPEC.md` §27): at
    /// least one project to list, and neither the note editor nor another
    /// overlay session is up (each overlay owns the keyboard alone). Callers
    /// use this both to open the list and to answer the keybind's
    /// performability check, so the two always agree.
    var canBeginProjectList: Bool {
        noteEditingProject == nil
            && !overlaySessionActive
            && !state.projects.isEmpty
    }

    /// Open the project list (`SPEC.md` §27). A project zoom is deliberately
    /// kept: opened while zoomed, the list overlays the zoom without
    /// releasing it, and closing returns to that zoom untouched (§27.3) —
    /// the Cmd+N-opened session included. No-op while it is already up or
    /// `canBeginProjectList` is false.
    func beginProjectList() {
        guard !projectListActive, canBeginProjectList else { return }
        projectListActive = true
        // A fresh session always opens at first-lines-only (SPEC §27.2).
        projectListFullNotes = false
        projectListPendingTitleEdit = nil
    }

    /// Close the project list (the Escape path, `SPEC.md` §27.3). Visibility
    /// toggles made during the session are real mutations and therefore stay.
    func endProjectList() {
        projectListActive = false
        projectListFullNotes = false
        projectListPendingTitleEdit = nil
    }

    /// Insert a newly created project into the ledger right below `anchor`
    /// (`Cmd+N`, `SPEC.md` §27.4), only while the list session is up. The row
    /// comes in visible while fewer than `WorkspaceState.maxVisibleProjects`
    /// rows are visible and hidden otherwise, the arrangement re-derives, and
    /// — unlike `openNewProject` — focus does not move: the list stays open
    /// with the new row awaiting its title (`projectListPendingTitleEdit`).
    ///
    /// The caller builds the project (with its live initial pane) exactly as
    /// normal creation does; this is the ledger insertion plus the pending
    /// title-edit handoff to the overlay.
    @discardableResult
    func insertProjectFromList(
        _ project: ProjectStateOf<Pane>, after anchor: ProjectID?
    ) -> Bool {
        guard projectListActive, state.projects[project.id] == nil else { return false }
        state.insertProject(project, after: anchor)
        projectListPendingTitleEdit = project.id
        return true
    }

    /// The overlay has seated the cursor on the pending row's title cell;
    /// clear the handoff so a later re-render does not re-open the edit.
    func clearProjectListPendingTitleEdit() {
        projectListPendingTitleEdit = nil
    }

    /// Toggle the list between first-lines-only and full notes (`SPEC.md`
    /// §27.2). Viewing-only, whole-list, transient; a no-op while no session
    /// is up.
    ///
    /// - Returns: whether full notes are showing after the call.
    @discardableResult
    func toggleProjectListFullNotes() -> Bool {
        guard projectListActive else { return false }
        projectListFullNotes.toggle()
        return projectListFullNotes
    }

    /// Commit an in-place text-cell edit (`SPEC.md` §27.2), only while the
    /// list session is up. The value rules live on the state
    /// (`commitListCellEdit`); Escape's cancel never reaches the model — the
    /// view just discards the edit session.
    @discardableResult
    func commitProjectListCellEdit(
        _ text: String, column: ProjectListColumn, for id: ProjectID
    ) -> Bool {
        guard projectListActive else { return false }
        var next = state
        guard next.commitListCellEdit(text, column: column, for: id) else { return false }
        state = next
        return true
    }

    /// Commit a candidate-menu selection (`SPEC.md` §27.6), only while the
    /// list session is up: the selected value lands through the same setters
    /// as any other entry point, so a change re-sorts immediately while a
    /// key sort state is active (SPEC §24.4). Escape's close never reaches
    /// the model — the view just discards the menu session.
    ///
    /// - Returns: whether the commit was accepted (an unknown project is
    ///   the setters' no-op, reported as accepted like an unchanged value).
    @discardableResult
    func commitProjectListCandidate(
        _ value: ProjectListCandidateValue, for id: ProjectID
    ) -> Bool {
        guard projectListActive else { return false }
        switch value {
        case .priority(let priority):
            setProjectPriority(id, to: priority)
        case .nextTrigger(let trigger):
            setProjectNextTrigger(id, to: trigger)
        case .deadline(let deadline):
            setProjectDeadline(id, to: deadline)
        }
        return true
    }

    /// Apply a Delete on a cell (`SPEC.md` §27.2), only while the list
    /// session is up. The per-column value rule lives on the state
    /// (`deleteListCellValue`); the note's confirmation is the view's
    /// (`ProjectListColumn.deleteAction`) — this is what an approved
    /// deletion applies.
    @discardableResult
    func deleteProjectListCellValue(
        _ column: ProjectListColumn, for id: ProjectID
    ) -> Bool {
        guard projectListActive else { return false }
        var next = state
        guard next.deleteListCellValue(column, for: id) else { return false }
        state = next
        return true
    }

    /// Move row `id` one-or-more places up (negative `delta`) or down in the
    /// ledger order (`Opt+↑`/`Opt+↓`, `SPEC.md` §27.1), clamped to the ends;
    /// only while the list session is up. The arrangement re-derives and the
    /// new order persists with the ledger.
    ///
    /// - Returns: the moved row's new ledger index — the cell cursor follows
    ///   it, so consecutive moves keep acting on the same row — or `nil`
    ///   when nothing moved (no session, unknown id, or a clamped end).
    @discardableResult
    func moveProjectListRow(_ id: ProjectID, by delta: Int) -> Int? {
        guard projectListActive,
              let from = state.projectOrder.firstIndex(of: id) else { return nil }
        let target = min(max(from + delta, 0), state.projectOrder.count - 1)
        guard target != from else { return nil }
        state.moveProjectRow(id, to: target)
        return target
    }

    /// The approved row move under an active sort (`SPEC.md` §24.5, §27.1):
    /// the confirmation's OK inherits the current display order as the
    /// manual order — `setSortState(.manual)` stops the re-sorts, which is
    /// the whole inheritance — and then performs the move, in one call so
    /// the approval cannot half-apply. Refused in the manual state (manual
    /// moves are confirmation-free and go through `moveProjectListRow`
    /// directly).
    ///
    /// - Returns: the moved row's new ledger index, or `nil` when nothing
    ///   moved. A clamped edge move still keeps the approved switch to
    ///   manual — the user approved leaving the sort, and the order they
    ///   see is the order they keep.
    @discardableResult
    func approveSortedRowMove(_ id: ProjectID, by delta: Int) -> Int? {
        guard projectListActive, state.sortState != .manual else { return nil }
        setProjectSortState(.manual)
        return moveProjectListRow(id, by: delta)
    }

    /// Move `column` one-or-more places left (negative `delta`) or right in
    /// the persisted column order (`Opt+←`/`Opt+→`, `SPEC.md` §27.1), clamped
    /// to the ends; only while the list session is up.
    ///
    /// - Returns: the moved column's new index — the cell cursor follows it,
    ///   so consecutive moves keep acting on the same column — or `nil` when
    ///   nothing moved.
    @discardableResult
    func moveProjectListColumn(_ column: ProjectListColumn, by delta: Int) -> Int? {
        guard projectListActive else { return nil }
        var next = state
        guard next.moveListColumn(column, by: delta) else { return nil }
        state = next
        return state.listColumnOrder.firstIndex(of: column)
    }

    /// The rows the project list shows: every project, hidden ones included,
    /// visible first in ordinal order (`SPEC.md` §27.1). Empty while no
    /// session is up, mirroring `noteOverviewProjectIDs`.
    var projectListRows: [ProjectListRow] {
        guard projectListActive else { return [] }
        return state.projectListRows
    }

    /// Whether Space would change anything for row `id` (`SPEC.md` §27.2).
    ///
    /// Hiding is refused when `id` is the last visible project — the
    /// at-least-one-visible rule of the hide-selection screen applies here too
    /// — and showing is refused at the visible-project cap, where the project
    /// would have no number to occupy.
    func canToggleProjectListVisibility(_ id: ProjectID) -> Bool {
        guard projectListActive, state.projects[id] != nil else { return false }
        return state.isProjectHidden(id)
            ? canAddVisibleProject
            : state.visibleProjectCount >= 2
    }

    /// Toggle row `id`'s visibility from the project list (`SPEC.md` §27.2).
    /// The change applies immediately — the list has no confirm step, and
    /// closing it with Escape does not undo it.
    ///
    /// Showing never moves focus: Space is a visibility control, and Enter
    /// (`focusProjectListRow`) is the focus control. Hiding moves focus only
    /// when the hidden project *was* focused, in which case the nearest
    /// surviving project takes over exactly as in `hideFocusedProject`.
    ///
    /// The caller passes the outgoing focused project's live panes so they are
    /// persisted before any structural change (a hidden project keeps its
    /// layout and processes alive in `projects`, invariant §14.7).
    ///
    /// - Returns: the project to focus next and its stored focused surface when
    ///   the toggle moved focus, otherwise `nil` (including for a rejected
    ///   toggle).
    @discardableResult
    func toggleProjectListVisibility(
        _ id: ProjectID,
        savingOutgoingPaneTree outgoing: SplitTree<Pane>
    ) -> (target: ProjectID, focus: SurfaceID?)? {
        guard canToggleProjectListVisibility(id) else { return nil }
        return state.isProjectHidden(id)
            ? showFromProjectList(id, savingOutgoingPaneTree: outgoing)
            : hideFromProjectList(id, savingOutgoingPaneTree: outgoing)
    }

    /// Show `id` back at its own ledger row, exactly like `showProject`
    /// (`SPEC.md` §11.8), but without taking focus.
    private func showFromProjectList(
        _ id: ProjectID,
        savingOutgoingPaneTree outgoing: SplitTree<Pane>
    ) -> (target: ProjectID, focus: SurfaceID?)? {
        var next = state
        next.saveOutgoingPaneTree(outgoing)
        next.setProjectHidden(id, false)
        state = next
        return nil
    }

    /// Drop `id`'s leaf so the remaining projects reclaim its space, keeping
    /// its state and live panes in `projects` (`SPEC.md` §11.7).
    private func hideFromProjectList(
        _ id: ProjectID,
        savingOutgoingPaneTree outgoing: SplitTree<Pane>
    ) -> (target: ProjectID, focus: SurfaceID?)? {
        // Resolved on the pre-removal tree, so "nearest" is measured from where
        // `id` actually sits. Only needed when `id` holds focus.
        let target: ProjectID? = state.focusedProject == id
            ? state.canonicalProjectTree.nearestLeaf(
                to: ProjectRef(id: id),
                matching: { $0.id != id })?.id
            : nil

        var next = state
        next.saveOutgoingPaneTree(outgoing)
        // The row keeps its ledger position; the relayout releases any zoom
        // re-entered mid-session (§18.3 backstop).
        next.setProjectHidden(id, true)
        if let target { next.focusedProject = target }
        next.snapFocusToPrimaryInOverallView()
        state = next

        guard let target else { return nil }
        return (target, state.projects[target]?.focusedSurface)
    }

    /// Whether Cmd+Enter on row `id` would focus a project (`SPEC.md` §27.3):
    /// every existing row while the session is up — a hidden row resolves to
    /// a nearby visible project (`resolvedListFocusTarget`) instead of being
    /// inert.
    func canFocusProjectListRow(_ id: ProjectID) -> Bool {
        projectListActive && state.projects[id] != nil
    }

    /// Focus row `id`'s project and close the list (`SPEC.md` §27.3). A
    /// hidden row closes the list too and focuses a nearby *visible* project
    /// (the model's resolution, `resolvedListFocusTarget`). While a zoom is
    /// up, the zoom is not released — its target switches to the focused
    /// project (§27.3).
    ///
    /// - Returns: the target project's stored focused surface so the caller can
    ///   swap `surfaceTree` and move keyboard focus, or `nil` when the row is
    ///   not focusable.
    @discardableResult
    func focusProjectListRow(
        _ id: ProjectID,
        savingOutgoingPaneTree outgoing: SplitTree<Pane>
    ) -> SurfaceID? {
        guard projectListActive,
              let target = state.resolvedListFocusTarget(for: id) else { return nil }
        projectListActive = false

        var next = state
        next.saveOutgoingPaneTree(outgoing)
        next.focusedProject = target
        if next.zoomedProject != nil {
            // Zoomed: stay zoomed, the zoom target switches (§27.3). The
            // zoomed view shows every pane, so the stored focused surface
            // stands — no primary snap.
            next.zoomedProject = target
        } else {
            // Closing the list lands in the overall view, so focus goes to
            // the project's primary pane (SPEC §22.4).
            next.snapFocusToPrimaryInOverallView()
        }
        state = next

        return state.projects[target]?.focusedSurface
    }

    // MARK: Daily priority reset (SPEC §28)

    /// Run the daily priority reset if the local 06:00 boundary has been
    /// crossed since it last ran (`SPEC.md` §28.2). Called at app launch and
    /// whenever the app can have slept through a boundary (wake, reactivation);
    /// calling it more often is harmless because the stored workday makes it
    /// idempotent within a day.
    ///
    /// Silent by design: no notification, no marker, and no reordering — the
    /// arrangement is untouched (§28.3).
    ///
    /// - Returns: whether the reset actually ran.
    @discardableResult
    func applyDailyPriorityReset(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        var next = state
        guard next.resetPrioritiesIfNeeded(at: now, calendar: calendar) else { return false }
        state = next
        return true
    }

    // MARK: Layout-type selection (SPEC §26)

    /// Whether `choose_project_layout` can open the layout-type selector
    /// (`SPEC.md` §26): at least one visible project to arrange around, and
    /// neither the note editor nor another overlay session up (each overlay
    /// owns the keyboard alone). A single available choice does NOT decline:
    /// the selector opens and shows that there is nothing to choose
    /// (`SPEC.md` §26.2). Callers use this both to open the selector and to
    /// answer the keybind's performability check, so the two always agree.
    var canBeginLayoutSelection: Bool {
        noteEditingProject == nil
            && !overlaySessionActive
            && state.visibleProjectCount >= 1
    }

    /// Open the layout-selection overlay (`SPEC.md` §26.2). Any project zoom
    /// is released first so the selector sits over the overall view it
    /// arranges (the Essence leaves the zoomed-invocation behavior to the
    /// implementation). No-op while `canBeginLayoutSelection` is false.
    func beginLayoutSelection() {
        guard canBeginLayoutSelection else { return }
        state.zoomedProject = nil
        layoutSelectionActive = true
    }

    /// Close the layout selector changing nothing (the Escape path,
    /// `SPEC.md` §26.2).
    func cancelLayoutSelection() {
        layoutSelectionActive = false
    }

    /// The choices the open selector lists (`SPEC.md` §26.2): the
    /// exact-match-collapsed layout types for the current visible count, in
    /// canonical enumeration order. Empty while the selector is closed. A
    /// single entry means there is nothing to choose — the selector shows
    /// that instead of a list.
    var layoutTypeChoices: [ProjectLayoutType] {
        guard layoutSelectionActive else { return [] }
        return ProjectLayoutType.choices(forVisibleCount: state.visibleProjectCount)
    }

    /// The choice standing for the remembered type at the current visible
    /// count — what the selector highlights as current, even when the saved
    /// spelling collapsed into another representative.
    var currentLayoutTypeChoice: ProjectLayoutType {
        state.layoutType.representative(forVisibleCount: state.visibleProjectCount)
    }

    /// Choose `type` in the open selector (Enter, `SPEC.md` §26.2–26.4): the
    /// type is remembered (persisted with the ledger, and re-applied whenever
    /// the visible count changes), the arrangement re-derives as its
    /// projection over the visible rows in row order, and the selector
    /// closes. The project count never changes; a zoom re-entered mid-session
    /// is cleared, since applying arranges the overall view.
    ///
    /// - Returns: whether the choice was applied (`false` while the selector
    ///   is not up).
    @discardableResult
    func chooseLayoutType(_ type: ProjectLayoutType) -> Bool {
        guard layoutSelectionActive else { return false }
        layoutSelectionActive = false

        var next = state
        next.layoutType = type
        next.zoomedProject = nil
        next.relayout()
        next.snapFocusToPrimaryInOverallView()
        state = next
        return true
    }

    // MARK: Close (SPEC §11.9)

    /// Close the focused project (`SPEC.md` §11.9, §18.1, §18.5). Removes it from
    /// the canonical tree, `projects`, and `hiddenProjectIDs`, clears any zoom on it,
    /// and moves focus to the nearest remaining project.
    ///
    /// Confirmation and terminating the project's surfaces are the caller's
    /// responsibility; this only mutates the project structure. The focus target is
    /// resolved on the pre-mutation canonical tree, which holds only the visible
    /// projects; if the closing project is the last visible one it falls back to a
    /// hidden project, which is then revealed via the same trailing-leaf re-attach
    /// as `show_project` so the focused project stays visible (invariant §14.6).
    ///
    /// - Returns: `.switched` after a successful close, `.closedLast` when the
    ///   focused project was the only project (the model is left unchanged so the
    ///   caller can delegate to tab/window close, §18.5), or `nil` if there is no
    ///   focused project.
    @discardableResult
    func closeFocusedProject() -> CloseProjectOutcome? {
        guard let closeID = state.focusedProject else { return nil }
        let closeRef = ProjectRef(id: closeID)

        // Resolve the next focus target before mutating. `nearestLeaf` already
        // excludes `closeRef` itself, and every canonical leaf is a visible
        // project; only when none remains do we fall back to a hidden one.
        let visibleTarget = state.canonicalProjectTree.nearestLeaf(
            to: closeRef,
            matching: { _ in true })
        let targetID = visibleTarget?.id ?? oldestHiddenProjectID()

        // §18.5: the only project's close is delegated to tab/window close.
        guard let targetID else { return .closedLast }

        var next = state
        // Drops the row from the ledger; the relayout releases a zoom on it.
        next.removeProject(closeID)
        // Reveal the target if it was hidden (no visible project remained); it
        // comes back at its own ledger row like `show_project`.
        if next.hiddenProjectIDs.contains(targetID) {
            next.setProjectHidden(targetID, false)
        }
        next.focusedProject = targetID
        // Outside zoom the surviving project's focus lands on its primary
        // (SPEC §22.4).
        next.snapFocusToPrimaryInOverallView()
        state = next

        return .switched(target: targetID, focus: state.projects[targetID]?.focusedSurface)
    }

    /// Close project `id` — any ledger row, visible or hidden (the list's
    /// row-selection Delete, `SPEC.md` §27.2, which is a close-equivalent
    /// deletion behind the same confirmation as `close_project`).
    ///
    /// The focused row delegates to `closeFocusedProject` and reports its
    /// outcome. An unfocused row (hidden ones included) simply leaves the
    /// ledger; focus does not move, reported as `.switched` to the unchanged
    /// focused project so the caller runs one outcome path.
    ///
    /// Confirmation and terminating the closed project's surfaces remain the
    /// caller's responsibility, exactly as with `closeFocusedProject`.
    ///
    /// - Returns: `nil` when `id` is unknown (or no project is focused, a
    ///   state the UI cannot reach).
    @discardableResult
    func closeProject(_ id: ProjectID) -> CloseProjectOutcome? {
        guard state.projects[id] != nil else { return nil }
        if state.focusedProject == id { return closeFocusedProject() }
        guard let focusedID = state.focusedProject else { return nil }

        var next = state
        next.removeProject(id)
        state = next
        return .switched(target: focusedID, focus: state.projects[focusedID]?.focusedSurface)
    }

    /// The hidden project to reveal when the last visible project is closed: the
    /// oldest one, matching the shelf's creation-time ordering.
    private func oldestHiddenProjectID() -> ProjectID? {
        state.hiddenProjectIDs
            .compactMap { state.projects[$0] }
            .min { ($0.createdAt, $0.id.rawValue.uuidString) <
                   ($1.createdAt, $1.id.rawValue.uuidString) }?
            .id
    }

    // MARK: Deletion protection (SPEC §23)

    /// Whether closing a project must confirm first (`SPEC.md` §23.1): always.
    /// The confirmed close_project dialog is the single sanctioned path that
    /// loses a project and its information (note, name, layout slot), so the
    /// confirmation appears regardless of whether any process is running —
    /// the parameter exists so the judgment (not the caller) owns that rule.
    func closeProjectRequiresConfirmation(anyLiveProcess: Bool) -> Bool {
        true
    }

    /// The project whose pane tree holds `paneID`, visible or hidden, or `nil`
    /// for an unknown pane.
    func projectID(containing paneID: SurfaceID) -> ProjectID? {
        state.projects.first { $0.value.paneTree.find(id: paneID.rawValue) != nil }?.key
    }

    /// Whether project `id` is in the terminated state (`SPEC.md` §23.2): its
    /// last pane's shell has exited and the pane is kept instead of closing.
    func isProjectTerminated(_ id: ProjectID) -> Bool {
        state.projects[id]?.isTerminated ?? false
    }

    /// The model-layer judgment of what a child-process exit (normal exit,
    /// abnormal exit, or process death alike) means for pane `paneID`
    /// (`SPEC.md` §23.2):
    ///
    /// - The project's last pane → `.terminated`: the project must not close; the
    ///   pane is kept in the terminated state with the note preserved.
    /// - One pane among several, normal exit → `.closePane`: the pane closes
    ///   as it always did.
    /// - One pane among several, abnormal exit → `.keepPaneAwaitingKey`: the
    ///   upstream contract is kept — the pane stays with its error message
    ///   until a key press closes it.
    ///
    /// Pure judgment: the caller applies the outcome via
    /// `markPaneTerminated` / `removeExitedPane` (or the controller's
    /// focused-tree close path).
    ///
    /// - Returns: `nil` when no project holds `paneID`.
    func childExitOutcome(for paneID: SurfaceID, abnormalExit: Bool) -> WorkspaceChildExitOutcome? {
        guard let projectID = projectID(containing: paneID),
              let project = state.projects[projectID] else { return nil }
        if !project.paneTree.isSplit { return .terminated(projectID) }
        return abnormalExit ? .keepPaneAwaitingKey(projectID) : .closePane(projectID)
    }

    /// Enter the terminated state for `paneID`'s project (`SPEC.md` §23.2).
    /// Rejected unless `paneID` is its project's sole pane (the state is
    /// defined only for a last pane).
    @discardableResult
    func markPaneTerminated(_ paneID: SurfaceID) -> Bool {
        guard let projectID = projectID(containing: paneID),
              var project = state.projects[projectID] else { return false }
        guard project.markPaneTerminated(paneID) else { return false }
        state.projects[projectID] = project
        return true
    }

    /// Remove the exited pane `paneID` from its project's tree — the model-side
    /// close for panes outside the focused project's mirrored `surfaceTree`
    /// (hidden or non-focused projects). Rejected when the pane is its project's
    /// last one: that case is `.terminated`, never a removal (`SPEC.md`
    /// §23.2). A dangling stored focus falls back to the first remaining
    /// leaf; the primary flag reconciles via the tree observer.
    @discardableResult
    func removeExitedPane(_ paneID: SurfaceID) -> Bool {
        guard let projectID = projectID(containing: paneID),
              var project = state.projects[projectID],
              project.paneTree.isSplit,
              let node = project.paneTree.find(id: paneID.rawValue) else { return false }

        project.paneTree = project.paneTree.removing(node)
        if let stored = project.focusedSurface,
           project.paneTree.find(id: stored.rawValue) == nil {
            project.focusedSurface = project.paneTree.firstLeaf.map { SurfaceID(rawValue: $0.id) }
        }
        state.projects[projectID] = project
        state.snapFocusToPrimaryInOverallView()
        return true
    }

    /// Leave the terminated state of project `projectID` by starting `newPane`
    /// (which carries a fresh shell) in the same pane slot (`SPEC.md` §23.3):
    /// the Enter-restart path. The new pane becomes the project's primary and
    /// its focused surface.
    ///
    /// - Returns: `false` when the project is unknown or not terminated (the
    ///   caller should then discard `newPane`).
    @discardableResult
    func restartTerminatedPane(
        in projectID: ProjectID,
        with newPane: Pane,
        now: Date = Date()
    ) -> Bool {
        guard var project = state.projects[projectID],
              project.restartTerminatedPane(with: newPane) else { return false }

        project.focusedSurface = SurfaceID(rawValue: newPane.id)
        project.lastFocusedAt = now
        state.projects[projectID] = project
        return true
    }

    // MARK: Rename (Phase 3)

    /// Enter inline-rename mode for `id`. No-op if the project is unknown.
    func beginRenaming(_ id: ProjectID) {
        guard state.projects[id] != nil else { return }
        renamingProject = id
    }

    /// Enter inline-rename mode for the focused project (`rename_project`, §7.1).
    func beginRenamingFocusedProject() {
        guard let id = state.focusedProject else { return }
        beginRenaming(id)
    }

    /// Leave inline-rename mode without changing any name.
    func cancelRenaming() {
        renamingProject = nil
    }

    /// Rename `id` to `newName` and leave rename mode. The trim-and-reject-
    /// empty rule lives on the state (`WorkspaceState.renameProject`), shared
    /// by the inline editor's commit, the `set_project_title` action, and the
    /// list's title cell (`SPEC.md` §9.1, §27.2).
    func renameProject(_ id: ProjectID, to newName: String) {
        defer { if renamingProject == id { renamingProject = nil } }
        // Copy-mutate-assign so a rejected or no-op rename emits no state
        // change (no spurious re-render / re-persist).
        var next = state
        guard next.renameProject(id, to: newName) else { return }
        state = next
    }

    // MARK: Notes

    /// Replace the note on project `id` with `text`, normalized through
    /// `ProjectState.setNote` so at most `ProjectState.maxNoteLines` lines are
    /// ever retained. No-op when the project is unknown or the normalized text
    /// is unchanged (so no spurious state emission / re-persist).
    func setProjectNote(_ id: ProjectID, to text: String) {
        guard var project = state.projects[id] else { return }
        let normalized = ProjectState.normalizedNote(text)
        guard project.note != normalized else { return }

        project.setNote(normalized)
        state.projects[id] = project
    }

    /// Open the note editor for `id`. No-op if the project is unknown, or
    /// while an overlay session (note overview, hide-selection, layout
    /// screens) is up — each overlay owns the keyboard alone.
    func beginNoteEditing(_ id: ProjectID) {
        guard !overlaySessionActive else { return }
        guard state.projects[id] != nil else { return }
        noteEditingProject = id
    }

    /// Open the note editor for the focused project (`edit_project_note`).
    func beginNoteEditingFocusedProject() {
        guard let id = state.focusedProject else { return }
        beginNoteEditing(id)
    }

    /// Close the note editor, saving `text` (normalized to the line cap by
    /// `setProjectNote`; the over-limit confirmation happens in the editor
    /// before this is called). This is the Cmd+Enter
    /// (and backdrop-click) path; Escape goes through `cancelNoteEditing`.
    func endNoteEditing(saving text: String) {
        defer { noteEditingProject = nil }
        guard let id = noteEditingProject else { return }
        setProjectNote(id, to: text)
    }

    /// Close the note editor, discarding the draft so the project keeps the
    /// text it had when the editor opened. This is the Escape path; no
    /// confirmation is asked before the draft is dropped (SPEC.md §21.2).
    func cancelNoteEditing() {
        noteEditingProject = nil
    }

    // MARK: Priority & deadline (SPEC §24)

    /// Set (or unset, with `nil`) the priority of project `id` (SPEC §24.1).
    /// No-op when the project is unknown or the value is unchanged. A change
    /// re-sorts immediately while a key sort state is active (SPEC §24.4).
    func setProjectPriority(_ id: ProjectID, to priority: ProjectPriority?) {
        guard var project = state.projects[id], project.priority != priority else { return }
        project.priority = priority
        state.projects[id] = project
        state.resortProjects()
    }

    /// Set (or unset, with `nil`) the deadline of project `id` (SPEC §24.1).
    /// No-op when the project is unknown or the value is unchanged. A change
    /// re-sorts immediately while a key sort state is active (SPEC §24.4).
    func setProjectDeadline(_ id: ProjectID, to deadline: ProjectDeadline?) {
        guard var project = state.projects[id], project.deadline != deadline else { return }
        project.deadline = deadline
        state.projects[id] = project
        state.resortProjects()
    }

    /// Save-time boundary for deadline text input (SPEC §24.1): parse
    /// `input` as a date-only deadline and store it; empty input clears the
    /// deadline deliberately, and *invalid* input (wrong shape or an
    /// impossible date) is rejected to unset.
    ///
    /// - Returns: `false` only for the rejected-invalid case, so an editor
    ///   can distinguish "cleared" from "rejected"; the stored outcome is
    ///   unset either way.
    @discardableResult
    func setProjectDeadline(_ id: ProjectID, parsing input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            setProjectDeadline(id, to: nil)
            return true
        }
        let parsed = ProjectDeadline(parsing: trimmed)
        setProjectDeadline(id, to: parsed)
        return parsed != nil
    }

    /// Set (or unset, with `nil`) the next trigger of project `id`
    /// (SPEC §24.6). No-op when the project is unknown or the value is
    /// unchanged. A change re-sorts immediately while a key sort state is
    /// active (SPEC §24.4).
    func setProjectNextTrigger(_ id: ProjectID, to trigger: ProjectNextTrigger?) {
        guard var project = state.projects[id], project.nextTrigger != trigger else { return }
        project.nextTrigger = trigger
        state.projects[id] = project
        state.resortProjects()
    }

    /// The priority of project `id`, or `nil` for unset / an unknown project.
    func projectPriority(of id: ProjectID) -> ProjectPriority? {
        state.projects[id]?.priority
    }

    /// The deadline of project `id`, or `nil` for unset / an unknown project.
    func projectDeadline(of id: ProjectID) -> ProjectDeadline? {
        state.projects[id]?.deadline
    }

    /// The next trigger of project `id`, or `nil` for unset / an unknown
    /// project.
    func projectNextTrigger(of id: ProjectID) -> ProjectNextTrigger? {
        state.projects[id]?.nextTrigger
    }

    /// Every row — hidden ones included — in priority order (SPEC §24.3).
    /// Forwarded from the state so the sort actions, render paths, and tests
    /// share one judgment.
    func priorityOrderedProjectIDs() -> [ProjectID] {
        state.priorityOrderedProjectIDs()
    }

    /// Every row — hidden ones included — in deadline order (SPEC §24.3).
    /// Forwarded from the state so the sort actions, render paths, and tests
    /// share one judgment.
    func deadlineOrderedProjectIDs() -> [ProjectID] {
        state.deadlineOrderedProjectIDs()
    }

    /// Every project whose deadline is past `today` (SPEC §24.2). Forwarded
    /// from the state so the display layers and tests share one judgment.
    func overdueProjectIDs(today: ProjectDeadline) -> Set<ProjectID> {
        state.overdueProjectIDs(today: today)
    }

    /// Whether project `id` is overdue as of `today` (SPEC §24.2): unset
    /// deadlines never are, and the deadline's own day is not yet overdue.
    func isProjectOverdue(_ id: ProjectID, today: ProjectDeadline) -> Bool {
        state.projects[id]?.deadline?.isOverdue(today: today) ?? false
    }

    // MARK: Primary pane (SPEC §22)

    /// The overall (non-zoomed) view's display target per project: exactly each
    /// visible project's primary pane (SPEC §22.3). Forwarded from the state so
    /// the render path and tests share one judgment.
    var overallViewPaneIDs: [ProjectID: SurfaceID] {
        state.overallViewPaneIDs
    }

    /// The primary pane of project `id`, or `nil` for an unknown project or an
    /// empty pane tree (SPEC §22.1).
    func primaryPaneID(of id: ProjectID) -> SurfaceID? {
        state.projects[id]?.primaryPane
    }

    /// Whether pane-level operations (split, inter-pane focus movement, pane
    /// zoom, resize/equalize) are currently allowed: only while the focused
    /// project is zoomed (SPEC §22.5). Forwarded from the state so the action
    /// guards and tests share one judgment.
    var paneOperationsEnabled: Bool {
        state.paneOperationsEnabled
    }

    /// Whether `set_primary` would change anything (SPEC §22.4): only while
    /// zoomed into the focused project (assignment is a zoom-only operation),
    /// with a focused pane that is not already the primary. Callers use this
    /// both to perform the action and to answer the keybind's performability
    /// check, so the two always agree.
    var canSetPrimaryToFocusedPane: Bool {
        guard state.paneOperationsEnabled,
              let project = focusedProjectState,
              let focused = project.focusedSurface,
              project.paneTree.find(id: focused.rawValue) != nil,
              project.primaryPane != focused else { return false }
        return true
    }

    /// Make the focused pane the primary pane of its project (`set_primary`,
    /// SPEC §22.4). The former primary is demoted implicitly — the flag is
    /// single-valued. No-op outside zoom, with no focused pane, or when the
    /// focused pane already holds the flag.
    ///
    /// - Returns: whether the flag moved.
    @discardableResult
    func setPrimaryToFocusedPane() -> Bool {
        guard canSetPrimaryToFocusedPane else { return false }
        guard let projectID = state.focusedProject,
              var project = state.projects[projectID],
              let focused = project.focusedSurface else { return false }

        let moved = project.setPrimaryPane(focused)
        if moved { state.projects[projectID] = project }
        return moved
    }

    /// The marked pane per project — the primary, only while that project is
    /// zoomed and holds multiple panes (SPEC §22.6). Forwarded from the
    /// state so the render path and tests share one judgment.
    var primaryMarkPaneIDs: [ProjectID: SurfaceID] {
        state.primaryMarkPaneIDs
    }

    // MARK: Sort state (SPEC §24.4–24.5)

    /// The sort state governing the row order (SPEC §24.4): manual / next /
    /// show / deadline / priority, manual by default, persisted. Forwarded
    /// from the state so the sort bar, render paths, and tests share one
    /// judgment.
    var projectSortState: ProjectSortState {
        state.sortState
    }

    /// Select a sort state (the sort bar's Enter, SPEC §24.5). A key state
    /// applies its stable ordering immediately — over every row, hidden ones
    /// included — and keeps governing the order until the state changes:
    /// every later key-value change, creation, load, and priority reset
    /// re-sorts on its own. Selecting manual inherits the current display
    /// order as the manual order (the rows simply stop being re-sorted);
    /// this is also the model half of the sorted row-move approval
    /// (SPEC §27.3): approve by selecting manual, then move the row.
    ///
    /// - Returns: whether the row order changed (a state change that leaves
    ///   the order intact returns false).
    @discardableResult
    func setProjectSortState(_ newState: ProjectSortState) -> Bool {
        state.setSortState(newState)
    }

    /// The pane-count badge per project — the total pane count, only in the
    /// overall (non-zoomed) view and only for projects holding non-primary
    /// panes (SPEC §22.7). Forwarded from the state so the render path and
    /// tests share one judgment.
    var overallViewPaneCountBadges: [ProjectID: Int] {
        state.overallViewPaneCountBadges
    }

    // MARK: Note overview

    /// The display set of the note overview: every *visible* project, in
    /// canonical traversal order. Hidden projects are never shown — canonical
    /// leaves are exactly the visible projects (hiding removes the leaf), so
    /// this is `WorkspaceState.visibleProjectIDs`. Empty while the overview is
    /// inactive.
    var noteOverviewProjectIDs: [ProjectID] {
        guard noteOverviewActive else { return [] }
        return state.visibleProjectIDs
    }

    /// Toggle the read-only note overview (`toggle_note_overview`).
    ///
    /// Entering releases any project zoom *first*, so the overlays land on all
    /// visible projects rather than a single zoomed one. Entering never changes
    /// `focusedProject`. No-op while the note editor is open — the editor owns
    /// the keyboard, and its draft must not be silently dropped.
    ///
    /// - Returns: whether the overview is active after the toggle, so the
    ///   caller can hand keyboard focus over/back accordingly.
    @discardableResult
    func toggleNoteOverview() -> Bool {
        // The note editor owns the keyboard and its draft must not be
        // silently dropped; the layout screen owns the interaction until it
        // confirms or cancels.
        guard noteEditingProject == nil,
              !layoutSelectionActive else { return noteOverviewActive }

        if noteOverviewActive {
            noteOverviewActive = false
        } else {
            state.zoomedProject = nil
            noteOverviewActive = true
        }
        return noteOverviewActive
    }

    /// Leave the note overview (the Escape path). No-op when inactive.
    func endNoteOverview() {
        noteOverviewActive = false
    }

    // MARK: Undo (project-aware undo cross-cutting task)

    /// Restore an entire captured `WorkspaceState` wholesale. Used by the
    /// controller's project-aware undo/redo to atomically reinstate a snapshot
    /// taken before a structural project mutation (project creation / `hide` /
    /// `show` / `close`).
    ///
    /// Unlike `replaceFocusedPaneTree` (which only updates the *focused* project's
    /// panes), this swaps `focusedProject`, `canonicalProjectTree`, `projects`, and the
    /// runtime visibility/zoom fields together, so the restore stays correct even
    /// across a focused-project switch. The caller is responsible for re-syncing
    /// `surfaceTree` to `focusedPaneTree` and moving keyboard focus afterwards.
    ///
    /// Any in-progress inline rename whose target no longer exists in the
    /// restored state is cancelled, so the transient editing UI can't outlive its
    /// project.
    func restoreState(_ snapshot: WorkspaceStateOf<Pane>) {
        state = snapshot
        if let renamingProject, state.projects[renamingProject] == nil {
            self.renamingProject = nil
        }
        if let noteEditingProject, state.projects[noteEditingProject] == nil {
            self.noteEditingProject = nil
        }
        // The overview is a transient viewing session over the *current*
        // layout; a wholesale state swap (undo/redo) ends it rather than
        // letting a restored zoom contradict the mode's zoom-released
        // invariant. The layout session ends for the same reason: its
        // candidate list belongs to the replaced layout.
        noteOverviewActive = false
        layoutSelectionActive = false
    }

    // MARK: Teardown

    /// Drop every project, leaving an empty workspace.
    ///
    /// Used when a tab/window is closed for good and the controller must stop
    /// owning any surface: clearing only `surfaceTree` would empty the focused
    /// project but leave the other projects' `SurfaceView`s retained here, which both
    /// keeps their processes alive past the close and lets a stale `undoState` be
    /// registered for a window that is already gone.
    func removeAllProjects() {
        state = WorkspaceStateOf<Pane>(canonicalProjectTree: .init(), projects: [:])
        renamingProject = nil
        noteEditingProject = nil
        noteOverviewActive = false
        layoutSelectionActive = false
    }
}

/// The runtime specialization: pane elements are live surface views.
typealias WorkspaceModel = WorkspaceModelOf<XGhostty.SurfaceView>

/// Errors thrown by `WorkspaceModelOf` project-structure transitions.
enum WorkspaceModelError: Error {
    /// There is no focused project to anchor a new project split against.
    case noFocusedProject

    /// `WorkspaceState.maxVisibleProjects` projects are already visible, so
    /// there is no number left to give a new one. Rejected silently (no
    /// toast, no beep): the caller simply does nothing.
    case visibleProjectLimitReached
}

/// The model-layer judgment of what a child-process exit means for its pane
/// (`SPEC.md` §23.2): deletion protection keeps the project when the exited
/// pane is its last one; otherwise the pane closes as it always did.
enum WorkspaceChildExitOutcome: Equatable {
    /// The exited pane is its project's only pane: the project stays — with its
    /// note — holding the pane in the terminated state (Enter restarts,
    /// `SPEC.md` §23.3).
    case terminated(ProjectID)

    /// One pane among several exited normally: it closes as before.
    case closePane(ProjectID)

    /// One pane among several exited abnormally: the upstream contract is
    /// kept — the pane stays with its error message until a key press
    /// closes it.
    case keepPaneAwaitingKey(ProjectID)
}

/// The result of closing the focused project (`SPEC.md` §11.9).
enum WorkspaceCloseProjectOutcome: Equatable {
    /// Focus moved to `target` (its stored last-focused surface in `focus`).
    case switched(target: ProjectID, focus: SurfaceID?)
    /// The focused project was the only project; the caller delegates to
    /// tab/window close (`SPEC.md` §18.5). The model is left unchanged so the
    /// close can be undone via the existing tab/window-close path.
    case closedLast
}
