import Foundation
import Testing
@testable import XGhostty

/// Phase 0 tests for `WorkspaceModel`, the mirror that wraps the focused
/// project's pane tree. Pane trees are kept empty because constructing
/// `XGhostty.SurfaceView` leaves requires a live XGhostty app; richer pane
/// operations are covered by the existing `SplitTreeTests` and manual
/// integration checks.
struct WorkspaceModelTests {
    @Test func wrappingCreatesSingleDefaultFocusedProject() {
        // Inject a fixed name so the assertion is deterministic; production draws
        // a random `adjective-noun` name from `ProjectNameGenerator`.
        let model = WorkspaceModel(wrapping: .init(), name: "amber-owl")

        #expect(model.state.projects.count == 1)
        let focused = model.state.focusedProject
        #expect(focused != nil)
        #expect(model.state.canonicalProjectTree.find(id: focused!) != nil)
        #expect(model.focusedProjectState != nil)
        #expect(model.focusedProjectState?.name == "amber-owl")
    }

    @Test func wrappingWithoutNameDrawsARandomProjectName() {
        // No injected name: a random `adjective-noun` (or `project-N` fallback) is
        // generated, so the project is always named (never empty).
        let model = WorkspaceModel(wrapping: .init())
        let name = model.focusedProjectState?.name
        #expect(name?.isEmpty == false)
    }

    @Test func wrappingEmptyPaneTreeHasNoFocusedSurface() {
        let model = WorkspaceModel(wrapping: .init())
        #expect(model.focusedProjectState?.focusedSurface == nil)
        #expect(model.focusedPaneTree.isEmpty)
    }

    @Test func emptyModelHasNoFocusedProject() {
        let model = WorkspaceModel()
        #expect(model.state.focusedProject == nil)
        #expect(model.focusedProjectState == nil)
        #expect(model.focusedPaneTree.isEmpty)
    }

    @Test func replaceFocusedPaneTreeUpdatesFocusedProjectOnly() {
        let model = WorkspaceModel(wrapping: .init())
        let focused = model.state.focusedProject

        model.replaceFocusedPaneTree(.init())

        // Still a single focused project; only its pane tree was touched.
        #expect(model.state.projects.count == 1)
        #expect(model.state.focusedProject == focused)
        #expect(model.focusedProjectState?.paneTree.isEmpty == true)
        #expect(model.focusedProjectState?.focusedSurface == nil)
    }

    @Test func setFocusedSurfaceIgnoresSurfaceNotInPaneTree() {
        let model = WorkspaceModel(wrapping: .init())
        // The surface id is not present in the (empty) pane tree, so this is a
        // no-op rather than recording a dangling focus.
        model.setFocusedSurface(SurfaceID(rawValue: UUID()))
        #expect(model.focusedProjectState?.focusedSurface == nil)
    }

    @Test func setFocusedSurfaceOnEmptyModelIsNoOp() {
        let model = WorkspaceModel()
        model.setFocusedSurface(SurfaceID(rawValue: UUID()))
        #expect(model.focusedProjectState == nil)
    }

    // MARK: openNewProject (SPEC §11.1, invariants §14.10–11)

    /// Builds a project with an empty pane tree. Pane trees stay empty because
    /// constructing real `SurfaceView` leaves requires a live XGhostty app; the
    /// project-structure transition is independent of pane contents.
    private static func makeEmptyProject(name: String) -> ProjectState {
        ProjectState(id: ProjectID(), name: name, paneTree: .init(), createdAt: Date())
    }

    @Test func openNewProjectInsertsSiblingAndSwitchesFocus() throws {
        let model = WorkspaceModel(wrapping: .init())
        let anchor = try #require(model.state.focusedProject)
        let newProject = Self.makeEmptyProject(name: "amber-owl")

        try model.openNewProject(newProject, direction: .right, savingOutgoingPaneTree: .init())

        // §14.10: the canonical tree gained the new project.
        #expect(model.state.projects.count == 2)
        let leafIDs = Set(model.state.canonicalProjectTree.map(\.id))
        #expect(leafIDs == Set([anchor, newProject.id]))
        // §14.11: focus moved to the new project.
        #expect(model.state.focusedProject == newProject.id)
        #expect(model.focusedProjectState?.id == newProject.id)
        #expect(model.focusedProjectState?.name == "amber-owl")
    }

    @Test func openNewProjectKeepsCanonicalAndProjectsConsistent() throws {
        let model = WorkspaceModel(wrapping: .init())
        let anchor = try #require(model.state.focusedProject)
        let newProject = Self.makeEmptyProject(name: "brave-river")

        try model.openNewProject(newProject, direction: .down, savingOutgoingPaneTree: .init())

        // §14.1–2: canonical leaves and projects keys stay in bijection.
        let leafIDs = Set(model.state.canonicalProjectTree.map(\.id))
        let projectKeys = Set(model.state.projects.keys)
        #expect(leafIDs == projectKeys)
        // The original anchor project is still present and reachable.
        #expect(model.state.canonicalProjectTree.find(id: anchor) != nil)
        #expect(model.state.projects[anchor] != nil)
    }

    @Test func openNewProjectThrowsWithoutFocusedProject() {
        let model = WorkspaceModel()
        let newProject = Self.makeEmptyProject(name: "calm-moon")

        #expect(throws: WorkspaceModel.WorkspaceError.noFocusedProject) {
            try model.openNewProject(newProject, direction: .right, savingOutgoingPaneTree: .init())
        }
        // The model is untouched on throw.
        #expect(model.state.projects.isEmpty)
        #expect(model.state.focusedProject == nil)
    }

    // MARK: switchFocusedProject (SPEC §7.1, invariant §14.12)

    @Test func switchFocusedProjectFlipsFocusToTarget() throws {
        let model = WorkspaceModel(wrapping: .init())
        let anchor = try #require(model.state.focusedProject)
        let other = Self.makeEmptyProject(name: "amber-owl")
        try model.openNewProject(other, direction: .right, savingOutgoingPaneTree: .init())
        #expect(model.state.focusedProject == other.id)

        // Switching back to the original anchor flips focus without changing
        // the project set or canonical tree.
        model.switchFocusedProject(to: anchor, savingOutgoingPaneTree: .init())

        #expect(model.state.focusedProject == anchor)
        #expect(Set(model.state.projects.keys) == Set([anchor, other.id]))
        let leafIDs = Set(model.state.canonicalProjectTree.map(\.id))
        #expect(leafIDs == Set([anchor, other.id]))
    }

    @Test func switchFocusedProjectIsNoOpWhenAlreadyFocused() {
        let model = WorkspaceModel(wrapping: .init())
        let focused = model.state.focusedProject

        let result = model.switchFocusedProject(to: focused!, savingOutgoingPaneTree: .init())

        #expect(result == nil)
        #expect(model.state.focusedProject == focused)
    }

    @Test func switchFocusedProjectIsNoOpForUnknownProject() {
        let model = WorkspaceModel(wrapping: .init())
        let focused = model.state.focusedProject

        let result = model.switchFocusedProject(to: ProjectID(), savingOutgoingPaneTree: .init())

        #expect(result == nil)
        #expect(model.state.focusedProject == focused)
    }

    // MARK: gotoProjectTarget (SPEC §11.3)

    /// Build a focused model with two projects split horizontally: the original
    /// anchor on the left and a new project on the right (which becomes focused).
    private static func makeTwoProjectHorizontal() throws -> (model: WorkspaceModel, left: ProjectID, right: ProjectID) {
        let model = WorkspaceModel(wrapping: .init())
        let left = try #require(model.state.focusedProject)
        let right = makeEmptyProject(name: "amber-owl")
        try model.openNewProject(right, direction: .right, savingOutgoingPaneTree: .init())
        return (model, left, right.id)
    }

    /// The ratio of the canonical tree's root split, if it is a split.
    private static func rootSplitRatio(_ model: WorkspaceModel) -> Double? {
        guard case .split(let split) = model.state.canonicalProjectTree.root else { return nil }
        return split.ratio
    }

    @Test func gotoProjectTargetMovesToVisibleNeighbor() throws {
        let (model, left, right) = try Self.makeTwoProjectHorizontal()
        #expect(model.state.focusedProject == right)

        // From the right project, the left neighbor exists; the right/up do not.
        #expect(model.gotoProjectTarget(.spatial(.left)) == left)
        #expect(model.gotoProjectTarget(.spatial(.right)) == nil)
        #expect(model.gotoProjectTarget(.spatial(.up)) == nil)
    }

    @Test func gotoProjectTargetIsNilForSingleProject() {
        let model = WorkspaceModel(wrapping: .init())
        // A single project has no neighbor, and next/previous would wrap to itself.
        #expect(model.gotoProjectTarget(.spatial(.left)) == nil)
        #expect(model.gotoProjectTarget(.next) == nil)
        #expect(model.gotoProjectTarget(.previous) == nil)
    }

    @Test func gotoProjectTargetIsNilWithoutFocusedProject() {
        let model = WorkspaceModel()
        #expect(model.gotoProjectTarget(.spatial(.left)) == nil)
    }

    @Test func gotoProjectTargetIsNilWhenZoomed() throws {
        let (model, _, right) = try Self.makeTwoProjectHorizontal()

        // Zoom is Phase 5; construct the zoomed state directly to exercise the
        // §11.3 "no-op while zoomed" guard.
        var zoomed = model.state
        zoomed.zoomedProject = right
        let zoomedModel = WorkspaceModel(zoomed)

        #expect(zoomedModel.gotoProjectTarget(.spatial(.left)) == nil)
    }

    // MARK: resizeFocusedProject — abolished (SPEC §26.3)

    @Test func resizeFocusedProjectIsAlwaysANoOp() throws {
        // The arrangement is a projection of the ledger: project-boundary
        // resize is abolished, so the canonical ratios never move.
        let (model, _, _) = try Self.makeTwoProjectHorizontal()
        let before = try #require(Self.rootSplitRatio(model))

        model.resizeFocusedProject(.left, ratioDelta: 0.1)
        model.resizeFocusedProject(.right, ratioDelta: 0.1)
        model.resizeFocusedProject(.up, ratioDelta: 0.1)

        #expect(Self.rootSplitRatio(model) == before)
        // A single project (no split) does not crash either.
        let single = WorkspaceModel(wrapping: .init())
        single.resizeFocusedProject(.left, ratioDelta: 0.1)
        #expect(single.state.canonicalProjectTree.root != nil)
    }

    // MARK: moveFocusedProject (move_project)

    /// Builds a horizontal row of three projects `[left, middle, right]` with
    /// `middle` focused.
    private static func makeThreeProjectRow() throws
        -> (model: WorkspaceModel, ids: (left: ProjectID, middle: ProjectID, right: ProjectID)) {
        let model = WorkspaceModel(wrapping: .init())
        let left = try #require(model.state.focusedProject)
        let middle = makeEmptyProject(name: "amber-owl")
        try model.openNewProject(middle, direction: .right, savingOutgoingPaneTree: .init())
        let right = makeEmptyProject(name: "coral-fox")
        try model.openNewProject(right, direction: .right, savingOutgoingPaneTree: .init())
        model.switchFocusedProject(to: middle.id, savingOutgoingPaneTree: .init())
        return (model, (left, middle.id, right.id))
    }

    /// Every split ratio in the canonical project tree, depth-first.
    private static func canonicalRatios(_ model: WorkspaceModel) -> [Double] {
        func walk(_ node: SplitTree<ProjectRef>.Node) -> [Double] {
            guard case .split(let split) = node else { return [] }
            return [split.ratio] + walk(split.left) + walk(split.right)
        }
        guard let root = model.state.canonicalProjectTree.root else { return [] }
        return walk(root)
    }

    @Test func moveFocusedProjectSwapsWithSpatialNeighbor() throws {
        let (model, left, right) = try Self.makeTwoProjectHorizontal()
        let ratios = Self.canonicalRatios(model)
        #expect(model.state.canonicalProjectTree.map(\.id) == [left, right])

        #expect(model.moveFocusedProject(.spatial(.left)) == true)

        // The two ledger rows traded places, so the two projects traded slots;
        // the projected layout's shape (and ratios) are identical and focus
        // followed the moved project to its new slot.
        #expect(model.state.projectOrder == [right, left])
        #expect(model.state.canonicalProjectTree.map(\.id) == [right, left])
        #expect(Self.canonicalRatios(model) == ratios)
        #expect(model.state.focusedProject == right)
    }

    @Test func moveFocusedProjectIsNotPerformableAtTheEdge() throws {
        let (model, left, right) = try Self.makeTwoProjectHorizontal()
        // The focused project is the rightmost, so right/up/down have no neighbor.
        #expect(model.canMoveFocusedProject(.spatial(.right)) == false)
        #expect(model.canMoveFocusedProject(.spatial(.up)) == false)
        #expect(model.moveFocusedProject(.spatial(.right)) == false)

        #expect(model.state.canonicalProjectTree.map(\.id) == [left, right])
        #expect(model.state.focusedProject == right)
    }

    @Test func moveFocusedProjectPreviousSwapsInOrderNeighbor() throws {
        let (model, ids) = try Self.makeThreeProjectRow()

        #expect(model.moveFocusedProject(.previous) == true)

        #expect(model.state.canonicalProjectTree.map(\.id) == [ids.middle, ids.left, ids.right])
        #expect(model.state.focusedProject == ids.middle)
    }

    @Test func moveFocusedProjectNextSwapsInOrderNeighbor() throws {
        let (model, ids) = try Self.makeThreeProjectRow()

        #expect(model.moveFocusedProject(.next) == true)

        #expect(model.state.canonicalProjectTree.map(\.id) == [ids.left, ids.right, ids.middle])
        #expect(model.state.focusedProject == ids.middle)
    }

    @Test func moveFocusedProjectSingleProjectIsNoOp() {
        let model = WorkspaceModel(wrapping: .init())
        #expect(model.moveFocusedProject(.next) == false)
        #expect(model.moveFocusedProject(.previous) == false)
        #expect(model.moveFocusedProject(.spatial(.left)) == false)
    }

    @Test func moveFocusedProjectIsNoOpWhenZoomed() throws {
        let (model, left, right) = try Self.makeTwoProjectHorizontal()
        var zoomed = model.state
        zoomed.zoomedProject = right
        let zoomedModel = WorkspaceModel(zoomed)

        #expect(zoomedModel.canMoveFocusedProject(.spatial(.left)) == false)
        #expect(zoomedModel.moveFocusedProject(.spatial(.left)) == false)
        #expect(zoomedModel.state.canonicalProjectTree.map(\.id) == [left, right])
    }

    @Test func moveFocusedProjectWithoutFocusedProjectIsNoOp() {
        let model = WorkspaceModel()
        #expect(model.moveFocusedProject(.next) == false)
    }

    // MARK: equalizeProjects — abolished (SPEC §26.3)

    @Test func equalizeProjectsIsAlwaysANoOp() throws {
        // The layout-type rules deal equal shares by construction, so there is
        // never anything to rebalance: the action always declines and the
        // projection is untouched.
        let (model, left, right) = try Self.makeTwoProjectHorizontal()
        let ratios = Self.canonicalRatios(model)

        #expect(model.equalizeProjects() == false)

        #expect(Self.canonicalRatios(model) == ratios)
        #expect(model.state.canonicalProjectTree.map(\.id) == [left, right])
        #expect(WorkspaceModel(wrapping: .init()).equalizeProjects() == false)
        #expect(WorkspaceModel().equalizeProjects() == false)
    }

    // MARK: Rename (SPEC §7.1, §9.1)

    @Test func renameProjectTrimsAndSetsName() {
        let model = WorkspaceModel(wrapping: .init())
        let id = model.state.focusedProject!

        model.renameProject(id, to: "  calm-river  ")

        #expect(model.state.projects[id]?.name == "calm-river")
    }

    @Test func renameProjectRejectsEmpty() {
        let model = WorkspaceModel(wrapping: .init())
        let id = model.state.focusedProject!
        let original = model.state.projects[id]?.name

        model.renameProject(id, to: "   ")

        #expect(model.state.projects[id]?.name == original)
    }

    @Test func renameProjectUnknownIdIsNoOp() {
        let model = WorkspaceModel(wrapping: .init())
        let id = model.state.focusedProject!
        let original = model.state.projects[id]?.name

        model.renameProject(ProjectID(), to: "ghost")

        #expect(model.state.projects[id]?.name == original)
        #expect(model.state.projects.count == 1)
    }

    @Test func renameProjectClearsRenameModeForThatProject() {
        let model = WorkspaceModel(wrapping: .init())
        let id = model.state.focusedProject!
        model.beginRenaming(id)
        #expect(model.renamingProject == id)

        model.renameProject(id, to: "lucky-spark")

        #expect(model.renamingProject == nil)
    }

    @Test func beginRenamingFocusedProjectTargetsFocused() {
        let model = WorkspaceModel(wrapping: .init())
        let focused = model.state.focusedProject

        model.beginRenamingFocusedProject()

        #expect(model.renamingProject == focused)
    }

    @Test func beginRenamingUnknownProjectIsNoOp() {
        let model = WorkspaceModel(wrapping: .init())

        model.beginRenaming(ProjectID())

        #expect(model.renamingProject == nil)
    }

    @Test func cancelRenamingClearsRenameMode() {
        let model = WorkspaceModel(wrapping: .init())
        model.beginRenamingFocusedProject()
        #expect(model.renamingProject != nil)

        model.cancelRenaming()

        #expect(model.renamingProject == nil)
    }

    // MARK: toggle_project_zoom (SPEC §11.6, invariants §14.5, §14.15)

    @Test func toggleProjectZoomZoomsAndUnzoomsFocusedProject() throws {
        let (model, _, right) = try Self.makeTwoProjectHorizontal()
        #expect(model.state.zoomedProject == nil)

        // First toggle zooms the focused (right) project; second clears it.
        model.toggleProjectZoom()
        #expect(model.state.zoomedProject == right)

        model.toggleProjectZoom()
        #expect(model.state.zoomedProject == nil)
    }

    @Test func toggleProjectZoomIsNoOpWithoutFocusedProject() {
        let model = WorkspaceModel()
        model.toggleProjectZoom()
        #expect(model.state.zoomedProject == nil)
    }

    @Test func canToggleProjectZoomRequiresOnlyAFocusedProject() throws {
        // With no focused project there is nothing to zoom.
        #expect(WorkspaceModel().canToggleProjectZoom == false)

        // Since the overall view renders only each project's primary pane and
        // disables pane operations (SPEC §22.3, §22.5), zoom is the gateway
        // to a project's full pane layout — meaningful even for a single
        // visible project.
        let single = WorkspaceModel(wrapping: .init())
        #expect(single.canToggleProjectZoom == true)

        // More than one visible project → zoom is meaningful as before.
        let (model, _, right) = try Self.makeTwoProjectHorizontal()
        #expect(model.canToggleProjectZoom == true)

        // A zoom can always be cleared, even when the visible tree is a single
        // (zoomed) leaf.
        var zoomed = model.state
        zoomed.zoomedProject = right
        #expect(WorkspaceModel(zoomed).canToggleProjectZoom == true)
    }

    // MARK: hide_project (SPEC §11.7, §18.2–3, invariants §14.7, §14.16–17)

    @Test func hideFocusedProjectHidesAndMovesFocusToNeighbor() throws {
        let (model, left, right) = try Self.makeTwoProjectHorizontal()
        #expect(model.state.focusedProject == right)

        let result = try #require(model.hideFocusedProject(savingOutgoingPaneTree: .init()))

        // The hidden project joins `hiddenProjectIDs`; focus moves to the neighbor.
        #expect(result.target == left)
        #expect(model.state.hiddenProjectIDs == [right])
        #expect(model.state.focusedProject == left)
        // Its leaf leaves the canonical tree so the visible projects reclaim the
        // space, but §14.7: the project stays alive in `projects`, so its
        // processes/panes persist for `show_project`.
        #expect(model.state.projects.count == 2)
        #expect(model.state.projects[right] != nil)
        #expect(model.state.canonicalProjectTree.map(\.id) == [left])
        #expect(model.state.canonicalProjectTree.isSplit == false)
    }

    @Test func hideFocusedProjectRejectsLastVisibleProject() {
        // §18.2: the last visible project cannot be hidden.
        let model = WorkspaceModel(wrapping: .init())
        let focused = model.state.focusedProject

        let result = model.hideFocusedProject(savingOutgoingPaneTree: .init())

        #expect(result == nil)
        #expect(model.state.hiddenProjectIDs.isEmpty)
        #expect(model.state.focusedProject == focused)
    }

    @Test func hideFocusedProjectRejectsWhenOnlyOtherProjectAlreadyHidden() throws {
        // Two projects, the left already hidden, the right focused. Hiding the
        // right would leave nothing visible → rejected (§18.2).
        let (model, left, right) = try Self.makeTwoProjectHorizontal()
        model.switchFocusedProject(to: left, savingOutgoingPaneTree: .init())
        try #require(model.hideFocusedProject(savingOutgoingPaneTree: .init()))
        #expect(model.state.hiddenProjectIDs == [left])
        #expect(model.state.focusedProject == right)

        #expect(model.canHideFocusedProject == false)
        #expect(model.hideFocusedProject(savingOutgoingPaneTree: .init()) == nil)
        #expect(model.state.hiddenProjectIDs == [left])
        #expect(model.state.focusedProject == right)
        #expect(model.state.canonicalProjectTree.map(\.id) == [right])
    }

    @Test func hideFocusedProjectClearsZoom() throws {
        // §18.3: a zoomed project un-zooms before being hidden.
        let (model, left, right) = try Self.makeTwoProjectHorizontal()
        var state = model.state
        state.zoomedProject = right
        let zoomedModel = WorkspaceModel(state)

        let result = try #require(zoomedModel.hideFocusedProject(savingOutgoingPaneTree: .init()))

        #expect(result.target == left)
        #expect(zoomedModel.state.zoomedProject == nil)
        #expect(zoomedModel.state.hiddenProjectIDs == [right])
        #expect(zoomedModel.state.focusedProject == left)
    }

    @Test func canHideFocusedProjectReflectsVisibleProjectCount() throws {
        let single = WorkspaceModel(wrapping: .init())
        #expect(single.canHideFocusedProject == false)

        let (model, _, _) = try Self.makeTwoProjectHorizontal()
        #expect(model.canHideFocusedProject == true)
    }

    // MARK: show_project (SPEC §11.8, §7.2)

    @Test func showProjectUnhidesAndFocuses() throws {
        let (model, left, right) = try Self.makeTwoProjectHorizontal()
        // Hide the focused (right) project; focus falls back to the left.
        try #require(model.hideFocusedProject(savingOutgoingPaneTree: .init()))
        #expect(model.state.focusedProject == left)

        // Showing it again un-hides and focuses it, re-attaching its leaf.
        model.showProject(right, savingOutgoingPaneTree: .init())

        #expect(model.state.hiddenProjectIDs.isEmpty)
        #expect(model.state.focusedProject == right)
        #expect(Set(model.state.canonicalProjectTree.map(\.id)) == Set([left, right]))
    }

    @Test func showProjectReturnsToItsOwnLedgerRow() throws {
        // Hide the *leftmost* of three projects: its ledger row never moves, so
        // showing it again puts it back exactly where it was — leftmost — and
        // the ordinals follow the row order (SPEC §27.1).
        let (model, ids) = try Self.makeThreeProjectRow()
        model.switchFocusedProject(to: ids.left, savingOutgoingPaneTree: .init())
        try #require(model.hideFocusedProject(savingOutgoingPaneTree: .init()))
        #expect(model.state.canonicalProjectTree.map(\.id) == [ids.middle, ids.right])

        model.showProject(ids.left, savingOutgoingPaneTree: .init())

        #expect(model.state.projectOrder == [ids.left, ids.middle, ids.right])
        #expect(model.state.canonicalProjectTree.map(\.id) == [ids.left, ids.middle, ids.right])
        #expect(model.state.focusedProject == ids.left)
        #expect(model.state.hiddenProjectIDs.isEmpty)
    }

    @Test func showProjectClearsZoom() throws {
        // A project hidden while another is zoomed: showing it clears the zoom.
        let (model, left, right) = try Self.makeTwoProjectHorizontal()
        try #require(model.hideFocusedProject(savingOutgoingPaneTree: .init()))
        #expect(model.state.focusedProject == left)

        var state = model.state
        state.zoomedProject = left
        let staged = WorkspaceModel(state)

        staged.showProject(right, savingOutgoingPaneTree: .init())

        #expect(staged.state.zoomedProject == nil)
        #expect(staged.state.hiddenProjectIDs.isEmpty)
        #expect(staged.state.focusedProject == right)
    }

    @Test func showProjectIsNoOpForUnknownProject() throws {
        // A stale hidden id with no `ProjectState` must not add a dangling leaf.
        let (model, left, _) = try Self.makeTwoProjectHorizontal()
        var state = model.state
        let ghost = ProjectID()
        state.hiddenProjectIDs = [ghost]
        let staged = WorkspaceModel(state)

        #expect(staged.showProject(ghost, savingOutgoingPaneTree: .init()) == nil)
        #expect(staged.state.canonicalProjectTree.find(id: ghost) == nil)
        #expect(staged.state.canonicalProjectTree.find(id: left) != nil)
    }

    @Test func showProjectIsNoOpForNonHiddenProject() throws {
        let (model, _, right) = try Self.makeTwoProjectHorizontal()
        // `right` is focused and visible; showing it is a no-op.
        let result = model.showProject(right, savingOutgoingPaneTree: .init())

        #expect(result == nil)
        #expect(model.state.focusedProject == right)
        #expect(model.state.hiddenProjectIDs.isEmpty)
    }

    @Test func hiddenProjectIDNamedResolvesOnlyHiddenProjects() throws {
        let (model, _, right) = try Self.makeTwoProjectHorizontal()
        let rightName = try #require(model.state.projects[right]?.name)

        // While visible, the name does not resolve to a hidden project.
        #expect(model.hiddenProjectID(named: rightName) == nil)

        try #require(model.hideFocusedProject(savingOutgoingPaneTree: .init()))

        // Once hidden, the name resolves; unknown names still do not.
        #expect(model.hiddenProjectID(named: rightName) == right)
        #expect(model.hiddenProjectID(named: "no-such-project") == nil)
    }

    // MARK: close_project (SPEC §11.9, §18.5)

    @Test func closeFocusedProjectSwitchesToNeighborAndPrunes() throws {
        let (model, left, right) = try Self.makeTwoProjectHorizontal()
        #expect(model.state.focusedProject == right)

        // Closing the focused (right) project moves focus to the left neighbor and
        // removes the closed project from the canonical tree and `projects`.
        let outcome = model.closeFocusedProject()

        #expect(outcome == .switched(target: left, focus: nil))
        #expect(model.state.focusedProject == left)
        #expect(model.state.projects.count == 1)
        #expect(model.state.projects[left] != nil)
        #expect(model.state.projects[right] == nil)
        #expect(Set(model.state.canonicalProjectTree.map(\.id)) == Set([left]))
    }

    @Test func closeFocusedProjectReturnsClosedLastForOnlyProject() {
        // §18.5: the only project's close is delegated to tab/window close, and the
        // model is left untouched so the close can be undone.
        let model = WorkspaceModel(wrapping: .init())
        let focused = model.state.focusedProject

        let outcome = model.closeFocusedProject()

        #expect(outcome == .closedLast)
        #expect(model.state.focusedProject == focused)
        #expect(model.state.projects.count == 1)
        #expect(model.state.canonicalProjectTree.map(\.id) == [focused].compactMap { $0 })
    }

    @Test func closeFocusedProjectReturnsNilWithoutFocusedProject() {
        let model = WorkspaceModel()
        #expect(model.closeFocusedProject() == nil)
    }

    @Test func closeFocusedProjectClearsZoomOnClosedProject() throws {
        // The focused (right) project is also zoomed; closing it clears the zoom.
        let (model, left, right) = try Self.makeTwoProjectHorizontal()
        var state = model.state
        state.zoomedProject = right
        let zoomedModel = WorkspaceModel(state)

        let outcome = zoomedModel.closeFocusedProject()

        #expect(outcome == .switched(target: left, focus: nil))
        #expect(zoomedModel.state.zoomedProject == nil)
        #expect(zoomedModel.state.focusedProject == left)
    }

    @Test func closeFocusedProjectRevealsHiddenProjectWhenNoVisibleNeighbor() throws {
        // The left project is hidden and the right is focused. Closing the right
        // leaves no visible neighbor, so the hidden left is revealed (re-attached
        // to the tree) and focused — the focused project must always be visible
        // (invariant §14.6).
        let (model, left, right) = try Self.makeTwoProjectHorizontal()
        model.switchFocusedProject(to: left, savingOutgoingPaneTree: .init())
        try #require(model.hideFocusedProject(savingOutgoingPaneTree: .init()))
        #expect(model.state.focusedProject == right)

        let outcome = model.closeFocusedProject()

        #expect(outcome == .switched(target: left, focus: nil))
        #expect(model.state.focusedProject == left)
        #expect(model.state.hiddenProjectIDs.isEmpty)
        #expect(model.state.projects[right] == nil)
        #expect(model.state.canonicalProjectTree.map(\.id) == [left])
    }

    @Test func closeFocusedProjectKeepsOtherHiddenProjectHidden() throws {
        // Three projects, the middle hidden, the rightmost focused. Closing the
        // focused project moves focus to the remaining visible project (the left),
        // never to the hidden middle, which stays hidden.
        let (model, ids) = try Self.makeThreeProjectRow()
        try #require(model.hideFocusedProject(savingOutgoingPaneTree: .init()))
        #expect(model.state.hiddenProjectIDs == [ids.middle])
        model.switchFocusedProject(to: ids.right, savingOutgoingPaneTree: .init())

        let outcome = model.closeFocusedProject()

        #expect(outcome == .switched(target: ids.left, focus: nil))
        #expect(model.state.focusedProject == ids.left)
        #expect(model.state.hiddenProjectIDs == [ids.middle])
        #expect(model.state.projects[ids.right] == nil)
        #expect(model.state.canonicalProjectTree.map(\.id) == [ids.left])
        // The hidden project is still alive in `projects`, just not in the tree.
        #expect(model.state.projects[ids.middle] != nil)
    }

    // MARK: restoreState (project-aware undo)

    @Test func restoreStateSwapsEntireState() throws {
        // A snapshot captured from one model fully replaces another model's
        // state — focusedProject, canonical tree, projects, hidden, and zoom.
        let (source, left, right) = try Self.makeTwoProjectHorizontal()
        var snapshot = source.state
        snapshot.focusedProject = left
        snapshot.hiddenProjectIDs = [right]
        snapshot.zoomedProject = left

        let model = WorkspaceModel(wrapping: .init())
        model.restoreState(snapshot)

        #expect(model.state.focusedProject == left)
        #expect(model.state.hiddenProjectIDs == [right])
        #expect(model.state.zoomedProject == left)
        #expect(Set(model.state.projects.keys) == Set([left, right]))
        #expect(Set(model.state.canonicalProjectTree.map(\.id)) == Set([left, right]))
    }

    @Test func restoreStateRoundTripsAfterHide() throws {
        // Capture, hide the focused project (which switches focus + flips hidden),
        // then restore the snapshot — the pre-hide state comes back intact. This
        // is exactly the undo path the controller wraps.
        let (model, left, right) = try Self.makeTwoProjectHorizontal()
        let before = model.state
        #expect(before.focusedProject == right)

        let hidden = model.hideFocusedProject(savingOutgoingPaneTree: .init())
        #expect(hidden?.target == left)
        #expect(model.state.hiddenProjectIDs == [right])
        #expect(model.state.focusedProject == left)
        #expect(model.state.canonicalProjectTree.map(\.id) == [left])

        model.restoreState(before)

        #expect(model.state.focusedProject == right)
        #expect(model.state.hiddenProjectIDs.isEmpty)
        #expect(Set(model.state.projects.keys) == Set([left, right]))
        // The snapshot carries the pre-hide tree, so the leaf comes back exactly
        // where it was rather than at the right edge.
        #expect(model.state.canonicalProjectTree.map(\.id) == [left, right])
    }

    @Test func restoreStateCancelsRenameForMissingProject() throws {
        // Restoring to a state that no longer contains the project being renamed
        // clears the transient rename mode so it can't outlive its project.
        let (model, _, right) = try Self.makeTwoProjectHorizontal()
        let snapshotWithoutRight = WorkspaceModel(wrapping: .init()).state

        model.beginRenaming(right)
        #expect(model.renamingProject == right)

        model.restoreState(snapshotWithoutRight)
        #expect(model.renamingProject == nil)
    }

    @Test func restoreStateKeepsRenameForSurvivingProject() throws {
        // Restoring to a state that still contains the renamed project keeps the
        // rename mode active.
        let (model, _, right) = try Self.makeTwoProjectHorizontal()
        let snapshot = model.state

        model.beginRenaming(right)
        #expect(model.renamingProject == right)

        model.restoreState(snapshot)
        #expect(model.renamingProject == right)
    }

    // MARK: Teardown

    @Test func removeAllProjectsDropsEveryProject() throws {
        // A window close must release *every* project's surfaces, not just the
        // focused one's, so no unfocused/hidden project's shell outlives the window.
        let (model, _, _) = try Self.makeTwoProjectHorizontal()
        #expect(model.state.projects.count == 2)

        model.removeAllProjects()

        #expect(model.state.projects.isEmpty)
        #expect(model.state.canonicalProjectTree.isEmpty)
        #expect(model.state.focusedProject == nil)
        #expect(model.focusedPaneTree.isEmpty)
    }

    @Test func removeAllProjectsClearsRename() throws {
        let (model, _, right) = try Self.makeTwoProjectHorizontal()
        model.beginRenaming(right)

        model.removeAllProjects()

        #expect(model.renamingProject == nil)
    }

    @Test func removeAllProjectsAlsoDropsHiddenProjects() throws {
        // Hidden projects are the ones most at risk: they're invisible, still
        // running, and only reachable through `projects`.
        let (model, left, right) = try Self.makeTwoProjectHorizontal()
        model.hideFocusedProject(savingOutgoingPaneTree: .init())
        #expect(model.state.hiddenProjectIDs == [right])
        #expect(model.state.focusedProject == left)

        model.removeAllProjects()

        #expect(model.state.projects.isEmpty)
        #expect(model.state.hiddenProjectIDs.isEmpty)
        #expect(model.state.zoomedProject == nil)
    }

    // MARK: Project numbering (SPEC §4.1)

    /// Builds a horizontal row of `count` projects (1 ≤ count ≤ 9) in traversal
    /// order, with the *first* one focused so the tests can hide/close from a
    /// known slot. Returns the ids in traversal order.
    private static func makeRow(_ count: Int) throws -> (model: WorkspaceModel, ids: [ProjectID]) {
        let model = WorkspaceModel(wrapping: .init(), name: "project-1")
        var ids = [try #require(model.state.focusedProject)]

        for index in 1..<count {
            let project = makeEmptyProject(name: "project-\(index + 1)")
            try model.openNewProject(project, direction: .right, savingOutgoingPaneTree: .init())
            ids.append(project.id)
        }

        model.switchFocusedProject(to: ids[0], savingOutgoingPaneTree: .init())
        #expect(model.state.canonicalProjectTree.map(\.id) == ids)
        return (model, ids)
    }

    @Test func ordinalsFollowCanonicalTraversalOrder() throws {
        let (model, ids) = try Self.makeRow(3)

        #expect(ids.map { model.ordinal(of: $0) } == [1, 2, 3])
        #expect(model.state.visibleProjectIDs == ids)
        #expect(model.state.visibleProjectCount == 3)
        #expect(model.state.projectOrdinals == [ids[0]: 1, ids[1]: 2, ids[2]: 3])
        // The inverse lookup agrees, and stops at the end of the row.
        #expect(model.state.visibleProjectID(ordinal: 2) == ids[1])
        #expect(model.state.visibleProjectID(ordinal: 4) == nil)
        #expect(model.state.visibleProjectID(ordinal: 0) == nil)
    }

    @Test func ordinalsFollowInOrderTraversalUsedByNextFocus() throws {
        // The numbering must match what `previous`/`next` walk, so the numbers
        // read in the same order as project-to-project navigation.
        let (model, ids) = try Self.makeRow(3)
        var walked = [ids[0]]
        for _ in 1..<3 {
            let next = try #require(model.gotoProjectTarget(.next))
            model.switchFocusedProject(to: next, savingOutgoingPaneTree: .init())
            walked.append(next)
        }

        #expect(walked == ids)
        #expect(walked.map { model.ordinal(of: $0) } == [1, 2, 3])
    }

    @Test func ordinalsRepackAfterHide() throws {
        let (model, ids) = try Self.makeRow(3)
        // Hide the middle project: the trailing project moves up to number 2.
        model.switchFocusedProject(to: ids[1], savingOutgoingPaneTree: .init())
        try #require(model.hideFocusedProject(savingOutgoingPaneTree: .init()))

        #expect(model.ordinal(of: ids[0]) == 1)
        #expect(model.ordinal(of: ids[2]) == 2)
        // A hidden project has no number at all (the shelf shows bare names).
        #expect(model.ordinal(of: ids[1]) == nil)
        #expect(model.state.visibleProjectCount == 2)
    }

    @Test func ordinalsRepackAfterClose() throws {
        let (model, ids) = try Self.makeRow(3)
        model.switchFocusedProject(to: ids[0], savingOutgoingPaneTree: .init())
        #expect(model.closeFocusedProject() != nil)

        // The survivors slide down to 1 and 2.
        #expect(model.ordinal(of: ids[1]) == 1)
        #expect(model.ordinal(of: ids[2]) == 2)
        #expect(model.ordinal(of: ids[0]) == nil)
    }

    @Test func ordinalsRepackAfterMoveProject() throws {
        let (model, ids) = try Self.makeRow(3)
        model.switchFocusedProject(to: ids[0], savingOutgoingPaneTree: .init())

        #expect(model.moveFocusedProject(.next) == true)

        // The two leaves traded slots, so their numbers traded too.
        #expect(model.ordinal(of: ids[1]) == 1)
        #expect(model.ordinal(of: ids[0]) == 2)
        #expect(model.ordinal(of: ids[2]) == 3)
    }

    @Test func ordinalsRepackAfterShowProject() throws {
        let (model, ids) = try Self.makeRow(3)
        model.switchFocusedProject(to: ids[0], savingOutgoingPaneTree: .init())
        try #require(model.hideFocusedProject(savingOutgoingPaneTree: .init()))
        #expect(model.ordinal(of: ids[1]) == 1)

        // `show_project` brings the row back at its own ledger position, so it
        // reclaims its old number (SPEC §27.1).
        model.showProject(ids[0], savingOutgoingPaneTree: .init())

        #expect(model.ordinal(of: ids[0]) == 1)
        #expect(model.ordinal(of: ids[1]) == 2)
        #expect(model.ordinal(of: ids[2]) == 3)
    }

    @Test func zoomedProjectKeepsItsCanonicalOrdinal() throws {
        // Zoom is a display state over the canonical tree, so the zoomed project
        // keeps the number it has in the full layout instead of showing `1`.
        let (model, ids) = try Self.makeRow(3)
        var state = model.state
        state.focusedProject = ids[2]
        state.zoomedProject = ids[2]
        let zoomed = WorkspaceModel(state)

        #expect(zoomed.ordinal(of: ids[2]) == 3)
        #expect(zoomed.state.projectOrdinals == [ids[0]: 1, ids[1]: 2, ids[2]: 3])
        // The effective (rendered) tree really is just the one project.
        #expect(zoomed.state.effectiveVisibleProjectTree?.map(\.id) == [ids[2]])
    }

    // MARK: Visible-project cap (max 9)

    @Test func openNewProjectSucceedsBelowTheVisibleCap() throws {
        let (model, ids) = try Self.makeRow(WorkspaceState.maxVisibleProjects - 1)
        #expect(model.canAddVisibleProject == true)

        let extra = Self.makeEmptyProject(name: "ninth")
        model.switchFocusedProject(to: ids.last!, savingOutgoingPaneTree: .init())
        try model.openNewProject(extra, direction: .right, savingOutgoingPaneTree: .init())

        #expect(model.state.visibleProjectCount == WorkspaceState.maxVisibleProjects)
        #expect(model.ordinal(of: extra.id) == WorkspaceState.maxVisibleProjects)
    }

    @Test func openNewProjectIsRejectedAtTheVisibleCap() throws {
        let (model, ids) = try Self.makeRow(WorkspaceState.maxVisibleProjects)
        #expect(model.canAddVisibleProject == false)
        let before = model.state

        #expect(throws: WorkspaceModel.WorkspaceError.visibleProjectLimitReached) {
            try model.openNewProject(
                Self.makeEmptyProject(name: "tenth"),
                direction: .right,
                savingOutgoingPaneTree: .init())
        }

        // Silently rejected: the state is byte-for-byte unchanged.
        #expect(model.state.visibleProjectCount == WorkspaceState.maxVisibleProjects)
        #expect(model.state.canonicalProjectTree.map(\.id) == ids)
        #expect(Set(model.state.projects.keys) == Set(before.projects.keys))
        #expect(model.state.focusedProject == before.focusedProject)
    }

    @Test func showProjectSucceedsBelowTheVisibleCap() throws {
        // 9 projects with one hidden → 8 visible, so the reveal fits.
        let (model, ids) = try Self.makeRow(WorkspaceState.maxVisibleProjects)
        model.switchFocusedProject(to: ids[0], savingOutgoingPaneTree: .init())
        try #require(model.hideFocusedProject(savingOutgoingPaneTree: .init()))
        #expect(model.state.visibleProjectCount == WorkspaceState.maxVisibleProjects - 1)
        #expect(model.canShowProject(ids[0]) == true)

        model.showProject(ids[0], savingOutgoingPaneTree: .init())

        #expect(model.state.hiddenProjectIDs.isEmpty)
        #expect(model.state.visibleProjectCount == WorkspaceState.maxVisibleProjects)
        #expect(model.state.focusedProject == ids[0])
    }

    @Test func showProjectIsRejectedAtTheVisibleCap() throws {
        // 9 visible projects plus a hidden 10th: the pill must stay on the shelf.
        let (model, ids) = try Self.makeRow(WorkspaceState.maxVisibleProjects)
        model.switchFocusedProject(to: ids[0], savingOutgoingPaneTree: .init())
        try #require(model.hideFocusedProject(savingOutgoingPaneTree: .init()))
        let extra = Self.makeEmptyProject(name: "tenth")
        try model.openNewProject(extra, direction: .right, savingOutgoingPaneTree: .init())
        #expect(model.state.visibleProjectCount == WorkspaceState.maxVisibleProjects)

        let before = model.state
        #expect(model.canShowProject(ids[0]) == false)
        #expect(model.showProject(ids[0], savingOutgoingPaneTree: .init()) == nil)

        #expect(model.state.hiddenProjectIDs == [ids[0]])
        #expect(model.state.canonicalProjectTree.map(\.id) == before.canonicalProjectTree.map(\.id))
        #expect(model.state.focusedProject == before.focusedProject)
    }

    @Test func closeProjectStillRevealsAHiddenProjectAtTheCap() throws {
        // §14.6 is unaffected by the cap: closing only ever frees a slot, so the
        // "no visible neighbor left" reveal can always run.
        let (model, left, right) = try Self.makeTwoProjectHorizontal()
        model.switchFocusedProject(to: left, savingOutgoingPaneTree: .init())
        try #require(model.hideFocusedProject(savingOutgoingPaneTree: .init()))

        #expect(model.closeFocusedProject() == .switched(target: left, focus: nil))
        #expect(model.state.hiddenProjectIDs.isEmpty)
        #expect(model.ordinal(of: left) == 1)
        #expect(model.state.projects[right] == nil)
    }

    // MARK: goto_project:<1-9> (index jump)

    @Test func gotoProjectIndexResolvesNthVisibleProject() throws {
        let (model, ids) = try Self.makeRow(3)
        // Focused is the first project, so 2 and 3 resolve.
        #expect(model.gotoProjectIndexTarget(2) == ids[1])
        #expect(model.gotoProjectIndexTarget(3) == ids[2])
    }

    @Test func gotoProjectIndexBeyondVisibleCountIsNil() throws {
        let (model, _) = try Self.makeRow(3)
        #expect(model.gotoProjectIndexTarget(4) == nil)
        #expect(model.gotoProjectIndexTarget(9) == nil)
        #expect(model.gotoProjectIndexTarget(0) == nil)
    }

    @Test func gotoProjectIndexToSelfIsNil() throws {
        let (model, ids) = try Self.makeRow(3)
        // The focused project is number 1; jumping to it changes nothing, so the
        // keybind stays unconsumed.
        #expect(model.state.focusedProject == ids[0])
        #expect(model.gotoProjectIndexTarget(1) == nil)
        #expect(model.gotoProject(index: 1, savingOutgoingPaneTree: .init()) == nil)
    }

    @Test func gotoProjectIndexSkipsHiddenProjects() throws {
        // Hidden projects have no number, so the numbering re-packs and index 2
        // lands on what used to be number 3.
        let (model, ids) = try Self.makeRow(3)
        model.switchFocusedProject(to: ids[1], savingOutgoingPaneTree: .init())
        try #require(model.hideFocusedProject(savingOutgoingPaneTree: .init()))
        model.switchFocusedProject(to: ids[0], savingOutgoingPaneTree: .init())

        #expect(model.gotoProjectIndexTarget(2) == ids[2])
        #expect(model.gotoProjectIndexTarget(3) == nil)
    }

    @Test func gotoProjectIndexSwitchesFocusToTarget() throws {
        let (model, ids) = try Self.makeRow(3)

        let result = try #require(model.gotoProject(index: 3, savingOutgoingPaneTree: .init()))

        #expect(result.target == ids[2])
        #expect(model.state.focusedProject == ids[2])
        // A pure focus change: the layout and the project set are untouched.
        #expect(model.state.canonicalProjectTree.map(\.id) == ids)
        #expect(model.state.zoomedProject == nil)
    }

    @Test func gotoProjectIndexClearsZoomAndJumps() throws {
        // Unlike the directional `goto_project`, an index jump works while zoomed:
        // it clears the zoom and lands on the target in one operation.
        let (model, ids) = try Self.makeRow(3)
        var state = model.state
        state.focusedProject = ids[0]
        state.zoomedProject = ids[0]
        let zoomed = WorkspaceModel(state)

        #expect(zoomed.gotoProjectIndexTarget(3) == ids[2])
        let result = try #require(zoomed.gotoProject(index: 3, savingOutgoingPaneTree: .init()))

        #expect(result.target == ids[2])
        #expect(zoomed.state.zoomedProject == nil)
        #expect(zoomed.state.focusedProject == ids[2])
        // The un-zoomed multi-project layout is what renders again.
        #expect(zoomed.state.effectiveVisibleProjectTree?.map(\.id) == ids)
    }

    @Test func gotoProjectIndexToZoomedProjectKeepsZoom() throws {
        // Asking for the project you are already zoomed into is a no-op — the zoom
        // survives, so Cmd+N doesn't accidentally un-zoom.
        let (model, ids) = try Self.makeRow(3)
        var state = model.state
        state.focusedProject = ids[1]
        state.zoomedProject = ids[1]
        let zoomed = WorkspaceModel(state)

        #expect(zoomed.gotoProjectIndexTarget(2) == nil)
        #expect(zoomed.gotoProject(index: 2, savingOutgoingPaneTree: .init()) == nil)
        #expect(zoomed.state.zoomedProject == ids[1])
        #expect(zoomed.state.focusedProject == ids[1])
    }

    @Test func gotoProjectIndexOnEmptyModelIsNil() {
        let model = WorkspaceModel()
        #expect(model.gotoProjectIndexTarget(1) == nil)
        #expect(model.gotoProject(index: 1, savingOutgoingPaneTree: .init()) == nil)
    }
}
