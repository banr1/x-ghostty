import Foundation
import Testing
@testable import XGhostty

/// A value-type pane element standing in for `XGhostty.SurfaceView`, which
/// cannot be constructed without a live XGhostty app. The generic model layer
/// (`ProjectStateOf` / `WorkspaceStateOf` / `WorkspaceModelOf`) runs the exact
/// same code for both element types, so these tests exercise the real
/// primary-pane judgment logic (SPEC §22) with real leaves in the trees.
private struct TestPane: Codable, Identifiable, Equatable {
    let id: UUID
    init(id: UUID = UUID()) { self.id = id }
}

private typealias TestProjectState = ProjectStateOf<TestPane>
private typealias TestWorkspaceState = WorkspaceStateOf<TestPane>
private typealias TestWorkspaceModel = WorkspaceModelOf<TestPane>

/// Tests for the primary-pane model layer (SPEC §22): default assignment,
/// per-project uniqueness, nearest-leaf promotion when the primary closes,
/// persistence with restore normalization, and the overall-view display
/// target.
struct ProjectPrimaryPaneTests {
    /// A project around a single-leaf tree, primary unassigned (defaulted).
    private static func makeProject(
        _ tree: SplitTree<TestPane>,
        name: String = "project",
        primaryPane: SurfaceID? = nil
    ) -> TestProjectState {
        TestProjectState(
            id: ProjectID(),
            name: name,
            paneTree: tree,
            primaryPane: primaryPane,
            createdAt: Date()
        )
    }

    // MARK: Default assignment & uniqueness (SPEC §22.1)

    @Test func initialPaneOfNewProjectIsPrimary() {
        let pane = TestPane()
        let project = Self.makeProject(.init(view: pane))

        #expect(project.primaryPane == SurfaceID(rawValue: pane.id))
        #expect(project.isPrimary(SurfaceID(rawValue: pane.id)))
    }

    @Test func emptyPaneTreeHasNoPrimary() {
        let project = Self.makeProject(.init())
        #expect(project.primaryPane == nil)
    }

    @Test func wrappingModelAssignsPrimaryToFirstPane() {
        let pane = TestPane()
        let model = TestWorkspaceModel(wrapping: .init(view: pane), name: "amber-owl")

        #expect(model.focusedProjectState?.primaryPane == SurfaceID(rawValue: pane.id))
    }

    @Test func laterSplitPanesAreNotPrimary() throws {
        let first = TestPane()
        var project = Self.makeProject(.init(view: first))

        // Grow the tree the way the mirror does: replace `paneTree` with the
        // post-split tree. The primary must stay on the first pane.
        let second = TestPane()
        let third = TestPane()
        var tree = try project.paneTree.inserting(view: second, at: first, direction: .right)
        tree = try tree.inserting(view: third, at: second, direction: .down)
        project.paneTree = tree

        #expect(project.primaryPane == SurfaceID(rawValue: first.id))
        #expect(!project.isPrimary(SurfaceID(rawValue: second.id)))
        #expect(!project.isPrimary(SurfaceID(rawValue: third.id)))
    }

    @Test func setPrimaryPaneMovesFlagAndDemotesFormerPrimary() throws {
        let first = TestPane()
        let second = TestPane()
        var project = Self.makeProject(.init(view: first))
        project.paneTree = try project.paneTree.inserting(view: second, at: first, direction: .right)

        let moved = project.setPrimaryPane(SurfaceID(rawValue: second.id))

        #expect(moved)
        #expect(project.primaryPane == SurfaceID(rawValue: second.id))
        #expect(!project.isPrimary(SurfaceID(rawValue: first.id)))
    }

    @Test func setPrimaryPaneRejectsPaneOutsideTheTree() {
        let pane = TestPane()
        var project = Self.makeProject(.init(view: pane))

        let moved = project.setPrimaryPane(SurfaceID(rawValue: UUID()))

        #expect(!moved)
        #expect(project.primaryPane == SurfaceID(rawValue: pane.id))
    }

    // MARK: Promotion on close (SPEC §22.2)

    @Test func primaryCloseProotesNearestLeaf() throws {
        // Layout: [A | B] with A primary. Closing A promotes B, the nearest
        // remaining leaf in the split tree.
        let a = TestPane()
        let b = TestPane()
        var project = Self.makeProject(.init(view: a))
        project.paneTree = try project.paneTree.inserting(view: b, at: a, direction: .right)
        #expect(project.primaryPane == SurfaceID(rawValue: a.id))

        let removed = project.paneTree.removing(.leaf(view: a))
        project.paneTree = removed

        #expect(project.primaryPane == SurfaceID(rawValue: b.id))
    }

    @Test func primaryClosePromotionPicksNearestLeafInDeepTree() throws {
        // Layout: [A | [B | C]] (a row, A at the left). Closing the primary A
        // promotes B — the nearest remaining leaf — not the farther C.
        let a = TestPane()
        let b = TestPane()
        let c = TestPane()
        var project = Self.makeProject(.init(view: a))
        var tree = try project.paneTree.inserting(view: b, at: a, direction: .right)
        tree = try tree.inserting(view: c, at: b, direction: .right)
        project.paneTree = tree
        #expect(project.primaryPane == SurfaceID(rawValue: a.id))

        project.paneTree = project.paneTree.removing(.leaf(view: a))

        #expect(project.primaryPane == SurfaceID(rawValue: b.id))
    }

    @Test func nonPrimaryCloseKeepsPrimary() throws {
        let a = TestPane()
        let b = TestPane()
        var project = Self.makeProject(.init(view: a))
        project.paneTree = try project.paneTree.inserting(view: b, at: a, direction: .right)

        project.paneTree = project.paneTree.removing(.leaf(view: b))

        #expect(project.primaryPane == SurfaceID(rawValue: a.id))
    }

    @Test func closingLastPaneClearsPrimary() {
        let a = TestPane()
        var project = Self.makeProject(.init(view: a))

        project.paneTree = project.paneTree.removing(.leaf(view: a))

        #expect(project.paneTree.isEmpty)
        #expect(project.primaryPane == nil)
    }

    // MARK: Persistence & restore normalization (SPEC §22.1)

    @Test func saveRestoreRoundTripKeepsPrimaryOnSamePane() throws {
        let a = TestPane()
        let b = TestPane()
        var project = Self.makeProject(.init(view: a))
        project.paneTree = try project.paneTree.inserting(view: b, at: a, direction: .right)
        project.setPrimaryPane(SurfaceID(rawValue: b.id))

        let data = try JSONEncoder().encode(project)
        let decoded = try JSONDecoder().decode(TestProjectState.self, from: data)

        // The non-default primary survives the round trip on the same pane.
        #expect(decoded.primaryPane == SurfaceID(rawValue: b.id))
    }

    @Test func decodeNormalizesZeroPrimariesToFirstLeaf() throws {
        let a = TestPane()
        let b = TestPane()
        var project = Self.makeProject(.init(view: a))
        project.paneTree = try project.paneTree.inserting(view: b, at: a, direction: .right)
        project.setPrimaryPane(SurfaceID(rawValue: b.id))

        // Tamper the save into the invalid zero-primaries shape.
        var json = try #require(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(project)) as? [String: Any])
        json["primaryPanes"] = []
        let tampered = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(TestProjectState.self, from: tampered)

        // Exactly one primary comes back: the tree's first leaf.
        #expect(decoded.primaryPane == SurfaceID(rawValue: decoded.paneTree.firstLeaf!.id))
    }

    @Test func decodeWithoutPrimaryKeyDefaultsToFirstLeaf() throws {
        // A save written before primary panes existed has no `primaryPanes`
        // key at all; it restores like the zero case.
        let a = TestPane()
        let project = Self.makeProject(.init(view: a))

        var json = try #require(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(project)) as? [String: Any])
        json.removeValue(forKey: "primaryPanes")
        let legacy = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(TestProjectState.self, from: legacy)

        #expect(decoded.primaryPane == SurfaceID(rawValue: a.id))
    }

    @Test func decodeNormalizesMultiplePrimariesToOne() throws {
        let a = TestPane()
        let b = TestPane()
        var project = Self.makeProject(.init(view: a))
        project.paneTree = try project.paneTree.inserting(view: b, at: a, direction: .right)

        // Tamper the save into the invalid several-primaries shape.
        var json = try #require(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(project)) as? [String: Any])
        json["primaryPanes"] = [
            ["rawValue": b.id.uuidString],
            ["rawValue": a.id.uuidString],
        ]
        let tampered = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(TestProjectState.self, from: tampered)

        // Exactly one primary comes back (the first stored valid flag), and
        // the other pane is not primary.
        #expect(decoded.primaryPane == SurfaceID(rawValue: b.id))
        #expect(!decoded.isPrimary(SurfaceID(rawValue: a.id)))
    }

    @Test func decodeNormalizesDanglingPrimaryToFirstLeaf() throws {
        let a = TestPane()
        let project = Self.makeProject(.init(view: a))

        // Tamper the save so the flag points at a pane not in the tree.
        var json = try #require(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(project)) as? [String: Any])
        json["primaryPanes"] = [["rawValue": UUID().uuidString]]
        let tampered = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(TestProjectState.self, from: tampered)

        #expect(decoded.primaryPane == SurfaceID(rawValue: a.id))
    }

    @Test func workspaceRoundTripRestoresEveryProjectsPrimary() throws {
        // Two projects with multi-pane trees and non-default primaries; the
        // whole workspace save/restore path (the same one app restoration
        // rides) brings the flags back to the same panes.
        let a1 = TestPane(); let a2 = TestPane()
        var projectA = Self.makeProject(.init(view: a1), name: "a")
        projectA.paneTree = try projectA.paneTree.inserting(view: a2, at: a1, direction: .right)
        projectA.setPrimaryPane(SurfaceID(rawValue: a2.id))

        let b1 = TestPane()
        let projectB = Self.makeProject(.init(view: b1), name: "b")

        let tree = try SplitTree<ProjectRef>(view: ProjectRef(id: projectA.id))
            .inserting(view: ProjectRef(id: projectB.id), at: ProjectRef(id: projectA.id), direction: .right)
        let state = TestWorkspaceState(
            canonicalProjectTree: tree,
            projects: [projectA.id: projectA, projectB.id: projectB],
            focusedProject: projectA.id
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(TestWorkspaceState.self, from: data)

        #expect(decoded.projects[projectA.id]?.primaryPane == SurfaceID(rawValue: a2.id))
        #expect(decoded.projects[projectB.id]?.primaryPane == SurfaceID(rawValue: b1.id))
    }

    // MARK: Overall-view display target (SPEC §22.3)

    @Test func overallViewDisplaySetIsEachVisibleProjectsPrimaryOnly() throws {
        // Project A: [a1 | a2] with a2 primary. Project B: single pane. Project C:
        // hidden. The overall (non-zoomed) view draws exactly one pane per
        // visible project — the primary — and nothing for hidden projects.
        let a1 = TestPane(); let a2 = TestPane()
        var projectA = Self.makeProject(.init(view: a1), name: "a")
        projectA.paneTree = try projectA.paneTree.inserting(view: a2, at: a1, direction: .right)
        projectA.setPrimaryPane(SurfaceID(rawValue: a2.id))

        let b1 = TestPane()
        let projectB = Self.makeProject(.init(view: b1), name: "b")
        let c1 = TestPane()
        let projectC = Self.makeProject(.init(view: c1), name: "c")

        // Hidden projects have no canonical leaf (SPEC §11.7).
        let tree = try SplitTree<ProjectRef>(view: ProjectRef(id: projectA.id))
            .inserting(view: ProjectRef(id: projectB.id), at: ProjectRef(id: projectA.id), direction: .right)
        let model = TestWorkspaceModel(TestWorkspaceState(
            canonicalProjectTree: tree,
            projects: [projectA.id: projectA, projectB.id: projectB, projectC.id: projectC],
            hiddenProjectIDs: [projectC.id],
            focusedProject: projectA.id
        ))

        let displaySet = model.overallViewPaneIDs
        #expect(displaySet == [
            projectA.id: SurfaceID(rawValue: a2.id),
            projectB.id: SurfaceID(rawValue: b1.id),
        ])
        #expect(displaySet[projectC.id] == nil)
        #expect(model.primaryPaneID(of: projectA.id) == SurfaceID(rawValue: a2.id))
    }

    // MARK: Overall-view pane-count badge (SPEC §22.7)

    @Test func paneCountBadgeShowsOnlyForMultiPaneVisibleProjects() throws {
        // Project A: [a1 | a2] (badge "2"). Project B: single pane (no badge —
        // nothing hidden behind the primary). Project C: hidden (never shown).
        let a1 = TestPane(); let a2 = TestPane()
        var projectA = Self.makeProject(.init(view: a1), name: "a")
        projectA.paneTree = try projectA.paneTree.inserting(view: a2, at: a1, direction: .right)

        let b1 = TestPane()
        let projectB = Self.makeProject(.init(view: b1), name: "b")
        let c1 = TestPane(); let c2 = TestPane()
        var projectC = Self.makeProject(.init(view: c1), name: "c")
        projectC.paneTree = try projectC.paneTree.inserting(view: c2, at: c1, direction: .right)

        let tree = try SplitTree<ProjectRef>(view: ProjectRef(id: projectA.id))
            .inserting(view: ProjectRef(id: projectB.id), at: ProjectRef(id: projectA.id), direction: .right)
        let model = TestWorkspaceModel(TestWorkspaceState(
            canonicalProjectTree: tree,
            projects: [projectA.id: projectA, projectB.id: projectB, projectC.id: projectC],
            hiddenProjectIDs: [projectC.id],
            focusedProject: projectA.id
        ))

        #expect(model.overallViewPaneCountBadges == [projectA.id: 2])
    }

    @Test func paneCountBadgeCountsEveryPane() throws {
        let (model, projectID, a, _) = try Self.makeTwoPaneModel()

        // Grow to three panes: the badge shows the total pane count.
        let c = TestPane()
        let grown = try model.focusedPaneTree.inserting(view: c, at: a, direction: .down)
        model.replaceFocusedPaneTree(grown)

        #expect(model.overallViewPaneCountBadges == [projectID: 3])
    }

    @Test func paneCountBadgeIsHiddenWhileZoomed() throws {
        let (model, projectID, _, _) = try Self.makeTwoPaneModel()
        #expect(model.overallViewPaneCountBadges == [projectID: 2])

        // The zoomed local view shows the real layout — no badge.
        model.toggleProjectZoom()
        #expect(model.overallViewPaneCountBadges.isEmpty)

        // Released: the badge returns with the overall view.
        model.toggleProjectZoom()
        #expect(model.overallViewPaneCountBadges == [projectID: 2])
    }

    @Test func paneCountBadgeDisappearsWhenProjectDropsToOnePane() throws {
        let (model, _, _, b) = try Self.makeTwoPaneModel()

        // The non-primary pane closes: nothing is hidden behind the primary
        // anymore, so the badge goes away.
        model.replaceFocusedPaneTree(.init(view: b))
        #expect(model.overallViewPaneCountBadges.isEmpty)
    }

    // MARK: Overall-view behavior (SPEC §22.3–22.5)

    /// A focused model around one project holding the row [a | b] with `a` the
    /// (default) primary — the smallest layout where primary and non-primary
    /// panes differ.
    private static func makeTwoPaneModel() throws -> (
        model: TestWorkspaceModel, projectID: ProjectID, a: TestPane, b: TestPane
    ) {
        let a = TestPane()
        let b = TestPane()
        let model = TestWorkspaceModel(wrapping: .init(view: a), name: "amber-owl")
        let split = try model.focusedPaneTree.inserting(view: b, at: a, direction: .right)
        model.replaceFocusedPaneTree(split)
        return (model, model.state.focusedProject!, a, b)
    }

    @Test func overallViewPaneTreeContainsExactlyThePrimaryLeaf() throws {
        let a1 = TestPane(); let a2 = TestPane()
        var project = Self.makeProject(.init(view: a1))
        project.paneTree = try project.paneTree.inserting(view: a2, at: a1, direction: .right)
        project.setPrimaryPane(SurfaceID(rawValue: a2.id))

        // The overall view renders a single-leaf tree: the primary, nothing else.
        let display = project.overallViewPaneTree
        #expect(display.map(\.id) == [a2.id])

        // An empty project renders nothing.
        #expect(Self.makeProject(.init()).overallViewPaneTree.isEmpty)
    }

    @Test func paneOperationsAreEnabledOnlyWhileTheFocusedProjectIsZoomed() throws {
        let (model, projectID, _, _) = try Self.makeTwoPaneModel()

        // The overall (non-zoomed) view: pane operations are no-ops.
        #expect(model.paneOperationsEnabled == false)

        // Zoomed into the focused project: pane operations are allowed.
        model.toggleProjectZoom()
        #expect(model.state.zoomedProject == projectID)
        #expect(model.paneOperationsEnabled == true)

        // Released again: back to no-ops.
        model.toggleProjectZoom()
        #expect(model.paneOperationsEnabled == false)
    }

    @Test func paneOperationsAreDisabledWhenTheZoomedProjectIsNotFocused() throws {
        // A zoom on a *different* project (transient divergence) must not allow
        // pane operations on the focused project's invisible tree.
        let (model, _, _, _) = try Self.makeTwoPaneModel()
        let other = TestProjectState(
            id: ProjectID(), name: "other", paneTree: .init(view: TestPane()), createdAt: Date())

        var state = model.state
        state.insertProject(other, after: nil)
        state.zoomedProject = other.id
        let diverged = TestWorkspaceModel(state)

        #expect(diverged.paneOperationsEnabled == false)
    }

    @Test func setFocusedSurfaceInOverallViewSnapsToPrimary() throws {
        let (model, projectID, a, b) = try Self.makeTwoPaneModel()

        // Outside zoom, focus can only rest on the primary (SPEC §22.4).
        model.setFocusedSurface(SurfaceID(rawValue: b.id))
        #expect(model.state.projects[projectID]?.focusedSurface == SurfaceID(rawValue: a.id))

        // While zoomed, any pane in the tree can hold focus.
        model.toggleProjectZoom()
        model.setFocusedSurface(SurfaceID(rawValue: b.id))
        #expect(model.state.projects[projectID]?.focusedSurface == SurfaceID(rawValue: b.id))
    }

    @Test func zoomReleaseSnapsFocusToPrimary() throws {
        let (model, projectID, a, b) = try Self.makeTwoPaneModel()

        // Zoom in and focus the non-primary pane.
        model.toggleProjectZoom()
        model.setFocusedSurface(SurfaceID(rawValue: b.id))
        #expect(model.state.projects[projectID]?.focusedSurface == SurfaceID(rawValue: b.id))

        // Releasing the zoom lands in the overall view: focus snaps to the
        // primary (SPEC §22.4).
        model.toggleProjectZoom()
        #expect(model.state.zoomedProject == nil)
        #expect(model.state.projects[projectID]?.focusedSurface == SurfaceID(rawValue: a.id))
    }

    @Test func switchFocusedProjectInOverallViewLandsOnPrimary() throws {
        // Project B stores a non-primary last-focused pane; switching to it in
        // the overall view focuses its primary instead.
        let (model, _, _, _) = try Self.makeTwoPaneModel()
        let b1 = TestPane(); let b2 = TestPane()
        var projectB = Self.makeProject(.init(view: b1), name: "b")
        projectB.paneTree = try projectB.paneTree.inserting(view: b2, at: b1, direction: .right)
        projectB.focusedSurface = SurfaceID(rawValue: b2.id)

        var state = model.state
        state.insertProject(projectB, after: nil)
        let workspace = TestWorkspaceModel(state)

        let focus = workspace.switchFocusedProject(
            to: projectB.id, savingOutgoingPaneTree: workspace.focusedPaneTree)

        #expect(focus == SurfaceID(rawValue: b1.id))
        #expect(workspace.state.projects[projectB.id]?.focusedSurface == SurfaceID(rawValue: b1.id))
    }

    @Test func primaryCloseInOverallViewMovesFocusToPromotedPrimary() throws {
        // The primary's pane leaves the tree outside zoom (shell exit, Cmd+W,
        // process death): the promoted primary also takes the focus.
        let (model, projectID, a, b) = try Self.makeTwoPaneModel()
        #expect(model.state.projects[projectID]?.focusedSurface == SurfaceID(rawValue: a.id))

        model.replaceFocusedPaneTree(model.focusedPaneTree.removing(.leaf(view: a)))

        #expect(model.primaryPaneID(of: projectID) == SurfaceID(rawValue: b.id))
        #expect(model.state.projects[projectID]?.focusedSurface == SurfaceID(rawValue: b.id))
    }

    // MARK: set_primary (SPEC §22.4)

    @Test func setPrimaryWhileZoomedMovesFlagToFocusedPane() throws {
        let (model, projectID, a, b) = try Self.makeTwoPaneModel()

        // Zoom in and focus the non-primary pane; reassignment is allowed.
        model.toggleProjectZoom()
        model.setFocusedSurface(SurfaceID(rawValue: b.id))
        #expect(model.canSetPrimaryToFocusedPane)

        #expect(model.setPrimaryToFocusedPane())

        // The focused pane took the flag and the former primary is demoted.
        #expect(model.primaryPaneID(of: projectID) == SurfaceID(rawValue: b.id))
        #expect(model.state.projects[projectID]?.isPrimary(SurfaceID(rawValue: a.id)) == false)
    }

    @Test func setPrimaryOutsideZoomIsNoOp() throws {
        let (model, projectID, a, _) = try Self.makeTwoPaneModel()

        // The overall view: assignment is zoom-only.
        #expect(!model.canSetPrimaryToFocusedPane)
        #expect(!model.setPrimaryToFocusedPane())
        #expect(model.primaryPaneID(of: projectID) == SurfaceID(rawValue: a.id))
    }

    @Test func setPrimaryOnAlreadyPrimaryPaneIsNoOp() throws {
        let (model, projectID, a, _) = try Self.makeTwoPaneModel()

        // Zoomed with the primary itself focused: nothing would change, so
        // the action declines (and the keybind falls through).
        model.toggleProjectZoom()
        model.setFocusedSurface(SurfaceID(rawValue: a.id))

        #expect(!model.canSetPrimaryToFocusedPane)
        #expect(!model.setPrimaryToFocusedPane())
        #expect(model.primaryPaneID(of: projectID) == SurfaceID(rawValue: a.id))
    }

    // MARK: Primary mark (SPEC §22.6)

    @Test func primaryMarkShowsOnlyWhileZoomedWithMultiplePanes() throws {
        let (model, projectID, a, _) = try Self.makeTwoPaneModel()

        // Overall view: no mark anywhere.
        #expect(model.primaryMarkPaneIDs.isEmpty)

        // Zoomed multi-pane project: exactly the primary is marked.
        model.toggleProjectZoom()
        #expect(model.primaryMarkPaneIDs == [projectID: SurfaceID(rawValue: a.id)])

        // Released again: the mark disappears with the zoom.
        model.toggleProjectZoom()
        #expect(model.primaryMarkPaneIDs.isEmpty)
    }

    @Test func primaryMarkHiddenForSinglePaneProject() {
        let a = TestPane()
        let model = TestWorkspaceModel(wrapping: .init(view: a), name: "amber-owl")

        // Zoomed, but the project has a single pane: the only pane is
        // trivially the primary, so no mark is shown.
        model.toggleProjectZoom()
        #expect(model.primaryMarkPaneIDs.isEmpty)
    }

    @Test func primaryMarkFollowsReassignment() throws {
        let (model, projectID, _, b) = try Self.makeTwoPaneModel()

        model.toggleProjectZoom()
        model.setFocusedSurface(SurfaceID(rawValue: b.id))
        model.setPrimaryToFocusedPane()

        #expect(model.primaryMarkPaneIDs == [projectID: SurfaceID(rawValue: b.id)])
    }

    @Test func paneTreeMirrorKeepsPrimaryThroughModelReplace() throws {
        // The controller mirrors every surface-tree change through
        // `replaceFocusedPaneTree`; the primary must survive the mirror and
        // promote when the primary pane disappeared from the mirrored tree.
        let a = TestPane()
        let b = TestPane()
        let model = TestWorkspaceModel(wrapping: .init(view: a), name: "amber-owl")
        let projectID = model.state.focusedProject!

        let split = try model.focusedPaneTree.inserting(view: b, at: a, direction: .right)
        model.replaceFocusedPaneTree(split)
        #expect(model.primaryPaneID(of: projectID) == SurfaceID(rawValue: a.id))

        model.replaceFocusedPaneTree(split.removing(.leaf(view: a)))
        #expect(model.primaryPaneID(of: projectID) == SurfaceID(rawValue: b.id))
    }
}
