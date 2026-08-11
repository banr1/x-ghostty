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

    /// The in-progress hide-selection session (`hide_project`, Cmd+Opt+H,
    /// `SPEC.md` §25): the set of projects currently toggled for hiding, or
    /// `nil` while no selection screen is up. Transient UI state like
    /// `noteEditingProject`; never persisted. While a session is up, focus
    /// moves and note editing are no-ops — the screen owns the interaction
    /// until it confirms or cancels.
    @Published private(set) var hideSelection: Set<ProjectID>?

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
    /// `WorkspaceState.maxVisibleProjects` are visible right now. Gates both
    /// `new_project_split` and `show_project`; at the cap both are silent no-ops.
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
    /// 3. Register `newProject` and insert its ref next to the focused project in
    ///    the canonical tree.
    /// 4. Switch `focusedProject` to `newProject`.
    ///
    /// The caller is then responsible for swapping `surfaceTree` to
    /// `newProject.paneTree` and moving keyboard focus into its initial pane.
    ///
    /// - Throws: `WorkspaceError.noFocusedProject` if nothing is focused,
    ///   `WorkspaceError.visibleProjectLimitReached` when
    ///   `WorkspaceState.maxVisibleProjects` are already visible, or a
    ///   `SplitTree.SplitError` if the canonical insert fails. The model is left
    ///   unchanged on throw.
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

        // Build the next state in a local copy so a failed insert leaves the
        // model untouched.
        var next = state

        // §18.4: a new project split un-zooms first.
        next.zoomedProject = nil

        // Persist the outgoing focused project's panes before switching away.
        next.saveOutgoingPaneTree(outgoing)

        // Insert the new project next to the focused one. Done before mutating
        // `projects`/`focusedProject` for real so a throw here is a no-op.
        let newTree = try next.canonicalProjectTree.inserting(
            view: ProjectRef(id: newProject.id),
            at: ProjectRef(id: anchorID),
            direction: direction)

        next.canonicalProjectTree = newTree
        next.projects[newProject.id] = newProject
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
        // The note overview is viewing-only, and the hide-selection screen
        // owns the interaction: no focus moves while either is up.
        guard !noteOverviewActive, !hideSelectionActive else { return nil }
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
        // The note overview is viewing-only, and the hide-selection screen
        // owns the interaction: no focus moves while either is up.
        guard !noteOverviewActive, !hideSelectionActive else { return nil }
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
        // The note overview is viewing-only, and the hide-selection screen
        // owns the interaction: no focus moves while either is up.
        guard !noteOverviewActive, !hideSelectionActive else { return nil }
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

    /// Resize the canonical split nearest to the focused project along the axis
    /// matching `direction`, by `ratioDelta` (`SPEC.md` §11.4).
    ///
    /// Mirrors `SplitTree.resizing(node:by:in:with:)`: walks up the canonical
    /// tree from the focused project's leaf and finds the nearest ancestor split
    /// whose axis matches the resize direction (horizontal for left/right,
    /// vertical for up/down), then adjusts its ratio. This works regardless of
    /// whether the focused project has a spatial neighbor in `direction`, fixing
    /// the bug where pressing the "shrink" direction was a no-op because the
    /// outermost project has no neighbor on the wall side.
    ///
    /// No-op when zoomed, when there is no focused project, when there is only one
    /// visible project, or when no ancestor split matches the axis.
    func resizeFocusedProject(
        _ direction: SplitTree<ProjectRef>.Spatial.Direction,
        ratioDelta: Double
    ) {
        guard state.zoomedProject == nil else { return }
        guard let focusedID = state.focusedProject else { return }
        guard state.effectiveVisibleProjectTree?.isSplit ?? false else { return }

        let targetAxis: SplitTree<ProjectRef>.Direction = switch direction {
        case .left, .right: .horizontal
        case .up, .down: .vertical
        }

        guard let splitPath = state.canonicalProjectTree.nearestAncestorSplitPath(
            from: ProjectRef(id: focusedID),
            matchingAxis: targetAxis) else { return }

        state.canonicalProjectTree = state.canonicalProjectTree.adjustRatio(
            at: splitPath,
            direction: direction,
            amount: ratioDelta)
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
    /// leaves exchange payloads in the canonical tree. The tree's shape and every
    /// split ratio stay put, so the layout does not reflow — the two projects
    /// simply trade slots. Focus follows the moved project to its new slot, so
    /// `focusedProject` is unchanged.
    ///
    /// - Returns: `true` if the projects were swapped, `false` when the move is a
    ///   no-op (zoomed, no focused project, or no neighbor in that direction), so
    ///   the caller can leave the keybind unconsumed.
    @discardableResult
    func moveFocusedProject(_ direction: SplitTree<ProjectRef>.FocusDirection) -> Bool {
        guard let focusedID = state.focusedProject else { return false }
        guard let targetID = gotoProjectTarget(direction) else { return false }
        guard let swapped = state.canonicalProjectTree.swappingLeaves(
            ProjectRef(id: focusedID),
            ProjectRef(id: targetID)) else { return false }

        state.canonicalProjectTree = swapped
        return true
    }

    /// Equalize the project layout (`SPEC.md` §11.5).
    ///
    /// Hidden projects are not in `canonicalProjectTree` at all — hiding removes the
    /// leaf (§11.7) — so equalizing the canonical tree only ever rebalances
    /// splits between visible projects. Zoom is a pure display state and does not
    /// affect the canonical ratios being equalized.
    ///
    /// - Returns: `true` if the layout was equalized, `false` when there is
    ///   nothing to equalize (a single project, or no projects at all).
    @discardableResult
    func equalizeProjects() -> Bool {
        guard state.canonicalProjectTree.isSplit else {
            XGhostty.logger.debug("equalize_projects skipped: no project split to equalize")
            return false
        }

        state.canonicalProjectTree = state.canonicalProjectTree.equalized()
        return true
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
    /// §18.2): at least one other project must remain visible afterwards.
    var canHideFocusedProject: Bool {
        guard let id = state.focusedProject else { return false }
        return neighborAfterHiding(id) != nil
    }

    /// Hide the focused project (`SPEC.md` §11.7, §18.2–3). The project's leaf is
    /// removed from `canonicalProjectTree` so the remaining projects reclaim its
    /// space, its id joins `hiddenProjectIDs` (the shelf's source of truth), and
    /// focus moves to the nearest remaining project. Its `ProjectState` — including
    /// its pane tree and live surfaces — stays in `projects`, so the processes stay
    /// alive (invariant §14.7).
    ///
    /// Hiding is therefore not positional: `show_project` re-attaches the project
    /// next to the trailing project rather than where it used to be.
    ///
    /// The caller passes the outgoing focused project's live panes; they are
    /// persisted into `projects` (the hidden project keeps its layout) before focus
    /// moves away. A hidden project cannot stay zoomed, so any zoom is cleared
    /// (§18.3).
    ///
    /// - Returns: the neighbor project to focus next and its last-focused surface
    ///   so the caller can swap `surfaceTree` and move keyboard focus, or `nil`
    ///   when the hide is rejected (no focused project, or it is the last visible
    ///   project, §18.2).
    @discardableResult
    func hideFocusedProject(
        savingOutgoingPaneTree outgoing: SplitTree<Pane>
    ) -> (target: ProjectID, focus: SurfaceID?)? {
        guard let hideID = state.focusedProject else { return nil }
        guard let neighbor = neighborAfterHiding(hideID) else { return nil }

        var next = state

        // The hidden project keeps its current layout alive in `projects`.
        next.saveOutgoingPaneTree(outgoing)

        // Drop the leaf so the visible projects reclaim its space; `projects` keeps
        // the state (and the running panes) behind the shelf entry.
        next.canonicalProjectTree = next.canonicalProjectTree.removing(.leaf(view: ProjectRef(id: hideID)))
        next.hiddenProjectIDs.insert(hideID)
        // §18.3: a hidden project cannot remain zoomed.
        if next.zoomedProject == hideID { next.zoomedProject = nil }
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

    /// Show the hidden project `id` (`SPEC.md` §11.8): re-attach its leaf, remove
    /// it from the hidden set, clear any zoom, and focus it.
    ///
    /// The project does *not* return to where it was before it was hidden — hiding
    /// removed its leaf entirely. The trailing project (the last leaf in traversal
    /// order) is split in half horizontally and the shown project takes the right
    /// half, so every other visible project keeps its current size.
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
        next.hiddenProjectIDs.remove(id)
        next.canonicalProjectTree = next.canonicalProjectTree
            .appendingAtTrailingLeaf(ProjectRef(id: id))
        next.zoomedProject = nil
        next.focusedProject = id
        // The reveal lands in the overall view, so the shown project's focus
        // goes to its primary pane (SPEC §22.4).
        next.snapFocusToPrimaryInOverallView()
        state = next

        return state.projects[id]?.focusedSurface
    }

    // MARK: Hide selection (SPEC §25)

    /// Whether the hide-selection screen is up.
    var hideSelectionActive: Bool { hideSelection != nil }

    /// Whether `hide_project` can open the selection screen (`SPEC.md` §25):
    /// at least two visible projects (with one, nothing could ever be hidden —
    /// at least one project always stays visible), and neither the note
    /// editor nor the note overview is up (each overlay owns the keyboard
    /// alone). Callers use this both to open the screen and to answer the
    /// keybind's performability check, so the two always agree.
    var canBeginHideSelection: Bool {
        noteEditingProject == nil
            && !noteOverviewActive
            && state.visibleProjectCount >= 2
    }

    /// Open the hide-selection screen with an empty selection (`SPEC.md`
    /// §25). Any project zoom is released first so the screen sits over the
    /// overall view it operates on (the Essence leaves the zoomed-invocation
    /// behavior to the implementation). No-op while a session is already up
    /// or `canBeginHideSelection` is false.
    func beginHideSelection() {
        guard hideSelection == nil, canBeginHideSelection else { return }
        state.zoomedProject = nil
        hideSelection = []
    }

    /// The projects the hide-selection screen lists: every visible project in
    /// canonical (ordinal) order. Empty while no session is up. Hidden
    /// projects are never listed — they are already hidden, and their return
    /// path stays the shelf (`SPEC.md` §25).
    var hideSelectionProjectIDs: [ProjectID] {
        guard hideSelectionActive else { return [] }
        return state.visibleProjectIDs
    }

    /// Toggle project `id` in the hide selection. No-op while no session is
    /// up, and for anything but a visible project (hidden projects are not
    /// listed and can never join the selection).
    func toggleHideSelection(_ id: ProjectID) {
        guard var selection = hideSelection else { return }
        guard state.visibleProjectIDs.contains(id) else { return }
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
        hideSelection = selection
    }

    /// Whether the current selection can be confirmed (`SPEC.md` §25): a
    /// select-all is rejected — at least one project must stay visible. An
    /// empty selection is confirmable; it just closes the screen hiding
    /// nothing.
    var canConfirmHideSelection: Bool {
        guard let selection = hideSelection else { return false }
        return selection.count < state.visibleProjectCount
    }

    /// Confirm the hide selection (`SPEC.md` §25): every selected project is
    /// hidden in one batch — each leaf leaves the canonical tree so the
    /// remaining projects reclaim the space, and each id joins
    /// `hiddenProjectIDs`, the shelf's source of truth (the return path is
    /// the shelf, unchanged) — and the screen closes. A select-all is
    /// rejected and the screen stays up; an empty selection closes the
    /// screen hiding nothing.
    ///
    /// When the focused project is among the hidden, focus moves to the
    /// nearest surviving project, measured on the pre-removal tree exactly
    /// like `hideFocusedProject`'s neighbor resolution.
    ///
    /// The caller passes the outgoing focused project's live panes so they
    /// are persisted before any structural change (the hidden projects keep
    /// their layouts and processes alive in `projects`, invariant §14.7).
    ///
    /// - Returns: the project to focus next and its stored focused surface so
    ///   the caller can swap `surfaceTree` and move keyboard focus, or `nil`
    ///   when nothing was hidden (a rejected confirm, or an empty selection).
    @discardableResult
    func confirmHideSelection(
        savingOutgoingPaneTree outgoing: SplitTree<Pane>
    ) -> (target: ProjectID, focus: SurfaceID?)? {
        guard let selection = hideSelection, canConfirmHideSelection else { return nil }
        hideSelection = nil
        guard !selection.isEmpty else { return nil }

        // Resolve the next focus on the pre-removal tree: a still-visible
        // focused project keeps focus; a selected one hands it to the nearest
        // surviving leaf (`canConfirmHideSelection` guarantees one exists).
        let target: ProjectID?
        if let focusedID = state.focusedProject {
            target = selection.contains(focusedID)
                ? state.canonicalProjectTree.nearestLeaf(
                    to: ProjectRef(id: focusedID),
                    matching: { !selection.contains($0.id) })?.id
                : focusedID
        } else {
            target = nil
        }

        var next = state
        next.saveOutgoingPaneTree(outgoing)
        for id in selection {
            next.canonicalProjectTree = next.canonicalProjectTree
                .removing(.leaf(view: ProjectRef(id: id)))
            next.hiddenProjectIDs.insert(id)
        }
        // §18.3 backstop: a hidden project cannot remain zoomed. Begin already
        // released the zoom; this covers a zoom re-entered mid-session (e.g.
        // via the menu bar, which the overlay cannot block).
        if let zoomed = next.zoomedProject, selection.contains(zoomed) {
            next.zoomedProject = nil
        }
        if let target { next.focusedProject = target }
        next.snapFocusToPrimaryInOverallView()
        state = next

        guard let target else { return nil }
        return (target, state.projects[target]?.focusedSurface)
    }

    /// Close the hide-selection screen hiding nothing (the Escape path,
    /// `SPEC.md` §25).
    func cancelHideSelection() {
        hideSelection = nil
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
        next.canonicalProjectTree = state.canonicalProjectTree.removing(.leaf(view: closeRef))
        next.projects.removeValue(forKey: closeID)
        next.hiddenProjectIDs.remove(closeID)
        if next.zoomedProject == closeID { next.zoomedProject = nil }
        // Reveal the target if it was hidden (no visible project remained). It has
        // no leaf while hidden, so it is re-attached like `show_project` does.
        if next.hiddenProjectIDs.remove(targetID) != nil {
            next.canonicalProjectTree = next.canonicalProjectTree
                .appendingAtTrailingLeaf(ProjectRef(id: targetID))
        }
        next.focusedProject = targetID
        // Outside zoom the surviving project's focus lands on its primary
        // (SPEC §22.4).
        next.snapFocusToPrimaryInOverallView()
        state = next

        return .switched(target: targetID, focus: state.projects[targetID]?.focusedSurface)
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

    /// Rename `id` to `newName` and leave rename mode. Whitespace is trimmed and
    /// an empty result is rejected (the existing name is kept). Shared by the
    /// inline editor's commit and the `set_project_title` action (`SPEC.md` §9.1).
    func renameProject(_ id: ProjectID, to newName: String) {
        defer { if renamingProject == id { renamingProject = nil } }

        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var project = state.projects[id], project.name != trimmed else { return }

        project.name = trimmed
        state.projects[id] = project
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
    /// while the read-only note overview or the hide-selection screen is up
    /// (each overlay owns the keyboard alone).
    func beginNoteEditing(_ id: ProjectID) {
        guard !noteOverviewActive, !hideSelectionActive else { return }
        guard state.projects[id] != nil else { return }
        noteEditingProject = id
    }

    /// Open the note editor for the focused project (`edit_project_note`).
    func beginNoteEditingFocusedProject() {
        guard let id = state.focusedProject else { return }
        beginNoteEditing(id)
    }

    /// Close the note editor, saving `text` (normalized to the 10-line cap by
    /// `setProjectNote`) to the project being edited. This is the Cmd+Enter
    /// (and backdrop-click) path; Escape goes through `cancelNoteEditing`.
    func endNoteEditing(saving text: String) {
        defer { noteEditingProject = nil }
        guard let id = noteEditingProject else { return }
        setProjectNote(id, to: text)
    }

    /// Close the note editor, saving the full draft set — note, priority, and
    /// the deadline text input — to the project being edited (SPEC §24.1). The
    /// overlay's single commit point (Cmd+Enter / backdrop click), so the
    /// three values save and persist together through the note path;
    /// `deadlineInput` goes through the `setProjectDeadline(parsing:)` boundary,
    /// where empty clears and invalid input is rejected to unset. Escape goes
    /// through `cancelNoteEditing`, which drops all three drafts at once.
    func endNoteEditing(
        saving text: String, priority: ProjectPriority?, deadlineInput: String
    ) {
        defer { noteEditingProject = nil }
        guard let id = noteEditingProject else { return }
        setProjectNote(id, to: text)
        setProjectPriority(id, to: priority)
        setProjectDeadline(id, parsing: deadlineInput)
    }

    /// Close the note editor, discarding the draft so the project keeps the
    /// text it had when the editor opened. This is the Escape path; no
    /// confirmation is asked before the draft is dropped (SPEC.md §21.2).
    func cancelNoteEditing() {
        noteEditingProject = nil
    }

    // MARK: Priority & deadline (SPEC §24)

    /// Set (or unset, with `nil`) the priority of project `id` (SPEC §24.1).
    /// No-op when the project is unknown or the value is unchanged.
    func setProjectPriority(_ id: ProjectID, to priority: ProjectPriority?) {
        guard var project = state.projects[id], project.priority != priority else { return }
        project.priority = priority
        state.projects[id] = project
    }

    /// Set (or unset, with `nil`) the deadline of project `id` (SPEC §24.1).
    /// No-op when the project is unknown or the value is unchanged.
    func setProjectDeadline(_ id: ProjectID, to deadline: ProjectDeadline?) {
        guard var project = state.projects[id], project.deadline != deadline else { return }
        project.deadline = deadline
        state.projects[id] = project
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

    /// The priority of project `id`, or `nil` for unset / an unknown project.
    func projectPriority(of id: ProjectID) -> ProjectPriority? {
        state.projects[id]?.priority
    }

    /// The deadline of project `id`, or `nil` for unset / an unknown project.
    func projectDeadline(of id: ProjectID) -> ProjectDeadline? {
        state.projects[id]?.deadline
    }

    /// The visible projects in priority order (SPEC §24.3). Forwarded from the
    /// state so the sort actions, render paths, and tests share one judgment.
    func priorityOrderedVisibleProjectIDs() -> [ProjectID] {
        state.priorityOrderedVisibleProjectIDs()
    }

    /// The visible projects in deadline order (SPEC §24.3). Forwarded from the
    /// state so the sort actions, render paths, and tests share one judgment.
    func deadlineOrderedVisibleProjectIDs() -> [ProjectID] {
        state.deadlineOrderedVisibleProjectIDs()
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

    // MARK: Sort actions (SPEC §24.4)

    /// Whether a sort action (`sort_projects_by_priority` /
    /// `sort_projects_by_deadline`) can reorder anything: at least two visible
    /// projects, and not while the note overview or the hide-selection screen
    /// is up (the overview is viewing-only; the selection screen must not
    /// have its listed order reshuffled under it). Callers use this both to
    /// perform the action and to answer the keybind's performability check,
    /// so the two always agree.
    var canSortVisibleProjects: Bool {
        !noteOverviewActive && !hideSelectionActive && state.visibleProjectIDs.count >= 2
    }

    /// Reorder the visible projects' layout by priority (`sort_projects_by_priority`,
    /// SPEC §24.4): high → medium → low → unset, equal priorities keeping
    /// their current relative order. The ordering judgment and the stable-tie
    /// rule live in `priorityOrderedVisibleProjectIDs`; this applies it to the
    /// real layout. Hidden projects are unaffected, and the order persists
    /// until the next sort — priority changes never reorder by themselves.
    ///
    /// - Returns: whether the layout was reordered.
    @discardableResult
    func sortVisibleProjectsByPriority() -> Bool {
        guard canSortVisibleProjects else { return false }
        return state.applyVisibleProjectOrder(state.priorityOrderedVisibleProjectIDs())
    }

    /// Reorder the visible projects' layout by deadline (`sort_projects_by_deadline`,
    /// SPEC §24.4): nearest date first, unset last, same-date projects keeping
    /// their current relative order. Same contract as
    /// `sortVisibleProjectsByPriority`, consuming `deadlineOrderedVisibleProjectIDs`.
    ///
    /// - Returns: whether the layout was reordered.
    @discardableResult
    func sortVisibleProjectsByDeadline() -> Bool {
        guard canSortVisibleProjects else { return false }
        return state.applyVisibleProjectOrder(state.deadlineOrderedVisibleProjectIDs())
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
        // silently dropped; the hide-selection screen owns the interaction
        // until it confirms or cancels.
        guard noteEditingProject == nil, hideSelection == nil else { return noteOverviewActive }

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
    /// taken before a structural project mutation (`new_project_split` / `hide` /
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
        // invariant. The hide-selection session ends for the same reason:
        // its candidate list belongs to the replaced layout.
        noteOverviewActive = false
        hideSelection = nil
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
        hideSelection = nil
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
