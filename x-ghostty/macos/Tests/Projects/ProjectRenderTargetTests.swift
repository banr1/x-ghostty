import Foundation
import Testing
@testable import XGhostty

/// A value-type pane element standing in for `XGhostty.SurfaceView`, which
/// cannot be constructed without a live XGhostty app. The generic model layer
/// runs the exact same code for both element types, so these tests exercise the
/// real render-target judgment (SPEC §31) with real leaves in the trees.
private struct TestPane: Codable, Identifiable, Equatable {
    let id: UUID
    init(id: UUID = UUID()) { self.id = id }
}

private typealias TestProjectState = ProjectStateOf<TestPane>
private typealias TestWorkspaceState = WorkspaceStateOf<TestPane>
private typealias TestWorkspaceModel = WorkspaceModelOf<TestPane>

private func sid(_ pane: TestPane) -> SurfaceID { SurfaceID(rawValue: pane.id) }

/// Tests for the render-target model layer (SPEC §31): which surfaces are drawn
/// in the overall view and while zoomed, which surfaces a transition stops and
/// resumes, and which ones leave the retained set outright.
struct ProjectRenderTargetTests {
    private static func makeProject(
        _ tree: SplitTree<TestPane>,
        name: String
    ) -> TestProjectState {
        TestProjectState(id: ProjectID(), name: name, paneTree: tree, createdAt: Date())
    }

    /// The fixture below, named so each test can read the pane it means.
    private struct Workspace {
        let model: TestWorkspaceModel
        let a: TestProjectState, a1: TestPane, a2: TestPane
        let b: TestProjectState, b1: TestPane
        let c: TestProjectState, c1: TestPane, c2: TestPane
    }

    /// Three projects: A = [a1 | a2] (primary a1), B = [b1] and C = [c1 | c2],
    /// with C hidden. A holds focus. This is the shape success criterion 29
    /// describes: a multi-pane visible project, a single-pane visible project,
    /// and a hidden multi-pane project.
    private static func makeWorkspace() throws -> Workspace {
        let a1 = TestPane(); let a2 = TestPane()
        var projectA = makeProject(.init(view: a1), name: "a")
        projectA.paneTree = try projectA.paneTree.inserting(view: a2, at: a1, direction: .right)
        projectA.focusedSurface = sid(a1)

        let b1 = TestPane()
        let projectB = makeProject(.init(view: b1), name: "b")

        let c1 = TestPane(); let c2 = TestPane()
        var projectC = makeProject(.init(view: c1), name: "c")
        projectC.paneTree = try projectC.paneTree.inserting(view: c2, at: c1, direction: .right)

        // Hidden projects have no canonical leaf (SPEC §11.7).
        let tree = try SplitTree<ProjectRef>(view: ProjectRef(id: projectA.id))
            .inserting(view: ProjectRef(id: projectB.id), at: ProjectRef(id: projectA.id), direction: .right)
        let model = TestWorkspaceModel(TestWorkspaceState(
            canonicalProjectTree: tree,
            projects: [projectA.id: projectA, projectB.id: projectB, projectC.id: projectC],
            projectOrder: [projectA.id, projectB.id, projectC.id],
            hiddenProjectIDs: [projectC.id],
            focusedProject: projectA.id
        ))

        return Workspace(
            model: model,
            a: projectA, a1: a1, a2: a2,
            b: projectB, b1: b1,
            c: projectC, c1: c1, c2: c2)
    }

    // MARK: Render target in the overall view (ESSENCE 必須 84 / success criterion 29)

    @Test func overallViewDrawsOnlyVisibleProjectsPrimaryPanes() throws {
        let w = try Self.makeWorkspace()

        #expect(w.model.state.renderTargetSurfaceIDs == [sid(w.a1), sid(w.b1)])
    }

    @Test func overallViewExcludesHiddenProjectPanesAndNonPrimaryPanes() throws {
        let w = try Self.makeWorkspace()
        let drawn = w.model.state.renderTargetSurfaceIDs

        // A's second pane is non-primary; C is hidden entirely.
        #expect(!drawn.contains(sid(w.a2)))
        #expect(!drawn.contains(sid(w.c1)))
        #expect(!drawn.contains(sid(w.c2)))
        // ...yet every one of them is still alive in the process.
        #expect(w.model.state.retainedSurfaceIDs
            == [sid(w.a1), sid(w.a2), sid(w.b1), sid(w.c1), sid(w.c2)])
    }

    @Test func overlaysDoNotChangeTheRenderTarget() throws {
        let w = try Self.makeWorkspace()
        let before = w.model.state.renderTargetSurfaceIDs

        // Every overlay only covers the terminal behind it (必須 84).
        w.model.beginProjectList()
        #expect(w.model.state.renderTargetSurfaceIDs == before)
        w.model.endProjectList()

        w.model.toggleShortcutList()
        #expect(w.model.state.renderTargetSurfaceIDs == before)
        w.model.endShortcutList()

        w.model.beginNoteEditing(w.a.id)
        #expect(w.model.state.renderTargetSurfaceIDs == before)
        w.model.cancelNoteEditing()

        w.model.beginLayoutSelection()
        #expect(w.model.state.renderTargetSurfaceIDs == before)
        w.model.cancelLayoutSelection()

        #expect(w.model.state.renderTargetSurfaceIDs == before)
    }

    // MARK: Render target while zoomed (ESSENCE 必須 84 / success criterion 29)

    @Test func zoomDrawsEveryPaneOfTheZoomedProjectAndNothingElse() throws {
        let w = try Self.makeWorkspace()

        w.model.toggleProjectZoom() // focus is on A

        #expect(w.model.state.renderTargetSurfaceIDs == [sid(w.a1), sid(w.a2)])
        // No other project's pane is drawn while zoomed.
        #expect(!w.model.state.renderTargetSurfaceIDs.contains(sid(w.b1)))
        #expect(!w.model.state.renderTargetSurfaceIDs.contains(sid(w.c1)))
    }

    @Test func aZoomOnAnUnrenderableProjectFallsBackToTheOverallView() throws {
        let w = try Self.makeWorkspace()

        // A hidden project cannot stay zoomed (SPEC §18.3): the state reads as
        // the overall view, matching `effectiveVisibleProjectTree`.
        var state = w.model.state
        state.zoomedProject = w.c.id
        let model = TestWorkspaceModel(state)

        #expect(model.state.renderTargetSurfaceIDs == [sid(w.a1), sid(w.b1)])
    }

    // MARK: Stop / resume sets per transition (success criterion 29)

    @Test func enteringAndLeavingZoomStopsAndResumesTheRightSurfaces() throws {
        let w = try Self.makeWorkspace()
        let overall = w.model.state.renderTargetSnapshot

        w.model.toggleProjectZoom()
        let zoomed = w.model.state.renderTargetSnapshot

        let entering = RenderTargetTransition(from: overall, to: zoomed)
        // B leaves the screen; A's second pane joins it. Nothing is released.
        #expect(entering.stop == [sid(w.b1)])
        #expect(entering.resume == [sid(w.a2)])
        #expect(entering.released.isEmpty)

        w.model.toggleProjectZoom()
        let leaving = RenderTargetTransition(from: zoomed, to: w.model.state.renderTargetSnapshot)
        #expect(leaving.stop == [sid(w.a2)])
        #expect(leaving.resume == [sid(w.b1)])
        #expect(leaving.released.isEmpty)
    }

    @Test func hidingAndShowingStopsAndResumesThePrimaryPane() throws {
        let w = try Self.makeWorkspace()
        let before = w.model.state.renderTargetSnapshot

        // Hide the focused project A (Cmd+Opt+H).
        w.model.hideFocusedProject(savingOutgoingPaneTree: w.model.focusedPaneTree)
        let hidden = w.model.state.renderTargetSnapshot

        let hiding = RenderTargetTransition(from: before, to: hidden)
        #expect(hiding.stop == [sid(w.a1)])
        #expect(hiding.resume.isEmpty)
        // Hiding never releases: A's panes stay alive (SPEC §14.7).
        #expect(hiding.released.isEmpty)
        #expect(hidden.retained.contains(sid(w.a1)))
        #expect(hidden.retained.contains(sid(w.a2)))

        // Show it again: its primary resumes, and only its primary.
        _ = w.model.showProject(w.a.id, savingOutgoingPaneTree: w.model.focusedPaneTree)
        let showing = RenderTargetTransition(from: hidden, to: w.model.state.renderTargetSnapshot)
        #expect(showing.resume == [sid(w.a1)])
        #expect(showing.stop.isEmpty)
        #expect(showing.released.isEmpty)
    }

    @Test func theListVisibilityToggleStopsAndResumesLikeHideAndShow() throws {
        let w = try Self.makeWorkspace()
        w.model.beginProjectList()
        let before = w.model.state.renderTargetSnapshot

        // Show the hidden project C from the list: its primary starts drawing.
        _ = w.model.toggleProjectListVisibility(w.c.id, savingOutgoingPaneTree: w.model.focusedPaneTree)
        let shown = w.model.state.renderTargetSnapshot
        let showing = RenderTargetTransition(from: before, to: shown)
        #expect(showing.resume == [sid(w.c1)])
        #expect(showing.stop.isEmpty)
        #expect(!shown.drawn.contains(sid(w.c2))) // still non-primary

        // Toggle it back off: its primary stops, and nothing is released.
        _ = w.model.toggleProjectListVisibility(w.c.id, savingOutgoingPaneTree: w.model.focusedPaneTree)
        let hiding = RenderTargetTransition(from: shown, to: w.model.state.renderTargetSnapshot)
        #expect(hiding.stop == [sid(w.c1)])
        #expect(hiding.resume.isEmpty)
        #expect(hiding.released.isEmpty)
    }

    @Test func reassigningThePrimaryStopsTheOldPaneAndResumesTheNew() throws {
        let w = try Self.makeWorkspace()

        // set_primary is a zoom-only operation (SPEC §22.4): zoom in, move the
        // focus onto a2, flag it, then leave zoom to see the overall view swap.
        w.model.toggleProjectZoom()
        w.model.setFocusedSurface(sid(w.a2))
        #expect(w.model.setPrimaryToFocusedPane())
        w.model.toggleProjectZoom()

        let after = w.model.state.renderTargetSnapshot
        #expect(after.drawn == [sid(w.a2), sid(w.b1)])

        // Measured over the whole zoom round trip, the net effect on the
        // overall view is exactly the primary swap.
        let overallBefore = RenderTargetSnapshot(
            drawn: [sid(w.a1), sid(w.b1)],
            retained: after.retained)
        let swap = RenderTargetTransition(from: overallBefore, to: after)
        #expect(swap.stop == [sid(w.a1)])
        #expect(swap.resume == [sid(w.a2)])
        #expect(swap.released.isEmpty)
    }

    // MARK: Release on close and on restart (success criterion 29)

    @Test func closingAProjectReleasesItsSurfaces() throws {
        let w = try Self.makeWorkspace()
        let before = w.model.state.renderTargetSnapshot

        #expect(w.model.closeProject(w.a.id) != nil)
        let closing = RenderTargetTransition(from: before, to: w.model.state.renderTargetSnapshot)

        // Both of A's panes leave the process — the drawn one included, which is
        // released rather than merely stopped.
        #expect(closing.released == [sid(w.a1), sid(w.a2)])
        #expect(closing.stop.isEmpty)
        #expect(!w.model.state.retainedSurfaceIDs.contains(sid(w.a1)))
        #expect(!w.model.state.retainedSurfaceIDs.contains(sid(w.a2)))
    }

    @Test func closingAHiddenProjectReleasesItsUndrawnSurfaces() throws {
        let w = try Self.makeWorkspace()
        let before = w.model.state.renderTargetSnapshot

        #expect(w.model.closeProject(w.c.id) != nil)
        let closing = RenderTargetTransition(from: before, to: w.model.state.renderTargetSnapshot)

        // C was never drawn, so nothing stops — but its surfaces must still go.
        #expect(closing.released == [sid(w.c1), sid(w.c2)])
        #expect(closing.stop.isEmpty)
        #expect(closing.resume.isEmpty)
    }

    @Test func restartingAnExitedPaneReleasesTheSurfaceItReplaced() throws {
        // A single-pane project whose shell exited: the pane stays in the
        // terminated state (SPEC §23.2) and its surface is still retained.
        let b1 = TestPane()
        let projectB = Self.makeProject(.init(view: b1), name: "b")
        let model = TestWorkspaceModel(TestWorkspaceState(
            canonicalProjectTree: .init(view: ProjectRef(id: projectB.id)),
            projects: [projectB.id: projectB],
            focusedProject: projectB.id))

        #expect(model.markPaneTerminated(sid(b1)))
        let before = model.state.renderTargetSnapshot
        #expect(before.retained.contains(sid(b1)))

        let replacement = TestPane()
        #expect(model.restartTerminatedPane(in: projectB.id, with: replacement))

        let restart = RenderTargetTransition(from: before, to: model.state.renderTargetSnapshot)
        #expect(restart.released == [sid(b1)])
        #expect(restart.resume == [sid(replacement)])
        #expect(restart.stop.isEmpty)
        #expect(!model.state.retainedSurfaceIDs.contains(sid(b1)))
    }

    // MARK: Transition algebra

    @Test func anUnchangedSnapshotImpliesNoWork() throws {
        let w = try Self.makeWorkspace()
        let snapshot = w.model.state.renderTargetSnapshot

        #expect(RenderTargetTransition(from: snapshot, to: snapshot).isEmpty)
    }
}
