import Foundation
import Testing
@testable import XGhostty

/// A value-type pane element standing in for `XGhostty.SurfaceView`, which
/// cannot be constructed without a live XGhostty app. The generic model layer
/// runs the exact same code for both element types, so these tests exercise
/// the real deletion-protection judgment logic (SPEC §23) with real leaves in
/// the trees.
private struct TestPane: Codable, Identifiable, Equatable {
    let id: UUID
    init(id: UUID = UUID()) { self.id = id }
}

private typealias TestProjectState = ProjectStateOf<TestPane>
private typealias TestWorkspaceState = WorkspaceStateOf<TestPane>
private typealias TestWorkspaceModel = WorkspaceModelOf<TestPane>

/// Tests for the deletion-protection model layer (SPEC §23): the
/// always-confirm project close, the per-pane terminated state (a command exit
/// never closes a pane, siblings or not), its persistence semantics, and the
/// project-wide Enter-restart transition.
struct ProjectTerminatedTests {
    /// A single-project model around `tree`, with a deterministic name.
    private static func makeModel(_ tree: SplitTree<TestPane>) -> TestWorkspaceModel {
        TestWorkspaceModel(wrapping: tree, name: "amber-owl")
    }

    private static func paneID(_ pane: TestPane) -> SurfaceID {
        SurfaceID(rawValue: pane.id)
    }

    // MARK: Always-confirm project close (SPEC §23.1)

    @Test func closeProjectRequiresConfirmationRegardlessOfRunningProcesses() {
        let model = Self.makeModel(.init(view: TestPane()))

        // The confirmation requirement never depends on whether a process is
        // alive: the dialog is the single sanctioned loss path for a project.
        #expect(model.closeProjectRequiresConfirmation(anyLiveProcess: true))
        #expect(model.closeProjectRequiresConfirmation(anyLiveProcess: false))
    }

    // MARK: Command exit (SPEC §23.2, must 29 / 143)

    @Test func lastPaneExitKeepsTheProjectWithNoteAndPane() throws {
        let pane = TestPane()
        let model = Self.makeModel(.init(view: pane))
        let projectID = try #require(model.state.focusedProject)
        model.setProjectNote(projectID, to: "deploy at five\ncheck the logs")

        // Normal exit, abnormal exit, and process death all reach the model
        // the same way: the pane is marked terminated.
        let marked = model.markPaneTerminated(Self.paneID(pane))

        #expect(marked)
        let project = try #require(model.state.projects[projectID])
        #expect(project.isTerminated)
        #expect(model.isProjectTerminated(projectID))
        #expect(model.isPaneTerminated(Self.paneID(pane)))
        #expect(project.terminatedPanes == [Self.paneID(pane)])
        #expect(project.paneTree.find(id: pane.id) != nil)
        #expect(project.note == "deploy at five\ncheck the logs")
    }

    @Test func siblingPaneExitKeepsThePaneWithTreeOtherPanesAndPrimaryUnchanged() throws {
        // [A | B | C] with A primary: B's command exits (normal or abnormal —
        // the same path). B stays in the tree terminated; the tree, A and C,
        // and the primary flag do not change.
        let a = TestPane()
        let b = TestPane()
        let c = TestPane()
        let tree = try SplitTree<TestPane>(view: a)
            .inserting(view: b, at: a, direction: .right)
            .inserting(view: c, at: b, direction: .down)
        let model = Self.makeModel(tree)
        let projectID = try #require(model.state.focusedProject)
        let before = try #require(model.state.projects[projectID])

        #expect(model.markPaneTerminated(Self.paneID(b)))

        let project = try #require(model.state.projects[projectID])
        #expect(project.paneTree.root == before.paneTree.root)
        #expect(project.terminatedPanes == [Self.paneID(b)])
        #expect(!project.isPaneTerminated(Self.paneID(a)))
        #expect(!project.isPaneTerminated(Self.paneID(c)))
        #expect(project.primaryPane == Self.paneID(a))
    }

    @Test func primaryPaneExitDoesNotPromoteAnotherPane() throws {
        // must 23: a primary whose command ends stays primary, terminated.
        let a = TestPane()
        let b = TestPane()
        let model = Self.makeModel(try .init(view: a).inserting(view: b, at: a, direction: .right))
        let projectID = try #require(model.state.focusedProject)
        #expect(model.state.projects[projectID]?.primaryPane == Self.paneID(a))

        #expect(model.markPaneTerminated(Self.paneID(a)))

        let project = try #require(model.state.projects[projectID])
        #expect(project.primaryPane == Self.paneID(a))
        #expect(project.paneTree.find(id: a.id) != nil)
        #expect(project.paneTree.find(id: b.id) != nil)
    }

    @Test func everyPaneOfASplitProjectCanBeTerminatedAtOnce() throws {
        // The ssh to a remote terminal drops: every pane's command ends. All
        // of them stay, none closes, and the project keeps its layout.
        let a = TestPane()
        let b = TestPane()
        let c = TestPane()
        let tree = try SplitTree<TestPane>(view: a)
            .inserting(view: b, at: a, direction: .right)
            .inserting(view: c, at: b, direction: .down)
        let model = Self.makeModel(tree)
        let projectID = try #require(model.state.focusedProject)

        for pane in [b, a, c] {
            #expect(model.markPaneTerminated(Self.paneID(pane)))
        }

        let project = try #require(model.state.projects[projectID])
        #expect(project.paneTree.root == tree.root)
        #expect(project.terminatedPanesInTreeOrder == [a, b, c].map(Self.paneID))
        #expect(project.primaryPane == Self.paneID(a))
    }

    @Test func anUnknownPaneCannotBeMarked() {
        let model = Self.makeModel(.init(view: TestPane()))
        #expect(!model.markPaneTerminated(SurfaceID(rawValue: UUID())))
        #expect(!model.isPaneTerminated(SurfaceID(rawValue: UUID())))
    }

    @Test func aPaneOfAHiddenProjectIsKeptTerminated() throws {
        let visible = TestPane()
        let hiddenA = TestPane()
        let hiddenB = TestPane()

        let visibleProject = TestProjectState(
            id: ProjectID(), name: "visible", paneTree: .init(view: visible), createdAt: Date())
        let hiddenProject = TestProjectState(
            id: ProjectID(), name: "hidden",
            paneTree: try .init(view: hiddenA).inserting(view: hiddenB, at: hiddenA, direction: .right),
            createdAt: Date())

        let model = TestWorkspaceModel(TestWorkspaceState(
            canonicalProjectTree: .init(view: ProjectRef(id: visibleProject.id)),
            projects: [visibleProject.id: visibleProject, hiddenProject.id: hiddenProject],
            hiddenProjectIDs: [hiddenProject.id],
            focusedProject: visibleProject.id))

        #expect(model.markPaneTerminated(Self.paneID(hiddenB)))
        let project = try #require(model.state.projects[hiddenProject.id])
        #expect(project.paneTree.find(id: hiddenB.id) != nil)
        #expect(project.paneTree.find(id: hiddenA.id) != nil)
        #expect(project.terminatedPanes == [Self.paneID(hiddenB)])
    }

    @Test func terminatedPrimaryLastPaneKeepsItsPrimaryFlag() throws {
        let pane = TestPane()
        let model = Self.makeModel(.init(view: pane))
        let projectID = try #require(model.state.focusedProject)

        #expect(model.markPaneTerminated(Self.paneID(pane)))
        #expect(model.state.projects[projectID]?.primaryPane == Self.paneID(pane))
    }

    @Test func splittingKeepsTheTerminatedPaneTerminated() throws {
        let pane = TestPane()
        let model = Self.makeModel(.init(view: pane))
        let projectID = try #require(model.state.focusedProject)
        #expect(model.markPaneTerminated(Self.paneID(pane)))

        // The state belongs to the pane: a new live sibling does not end it.
        let other = TestPane()
        model.replaceFocusedPaneTree(
            try model.focusedPaneTree.inserting(view: other, at: pane, direction: .right))

        let project = try #require(model.state.projects[projectID])
        #expect(project.terminatedPanes == [Self.paneID(pane)])
    }

    @Test func closingATerminatedPaneExplicitlyRemovesItAndItsState() throws {
        // Cmd+W is a loss path (must 143): the pane leaves the tree and takes
        // its terminated state with it; the primary is promoted as for any
        // explicit close.
        let a = TestPane()
        let b = TestPane()
        let model = Self.makeModel(try .init(view: a).inserting(view: b, at: a, direction: .right))
        let projectID = try #require(model.state.focusedProject)
        #expect(model.markPaneTerminated(Self.paneID(a)))

        model.replaceFocusedPaneTree(model.focusedPaneTree.removing(.leaf(view: a)))

        let project = try #require(model.state.projects[projectID])
        #expect(project.paneTree.find(id: a.id) == nil)
        #expect(!project.isTerminated)
        #expect(project.primaryPane == Self.paneID(b))
    }

    // MARK: Persistence (SPEC §23.4)

    @Test func terminatedProjectRoundTripKeepsNote() throws {
        let pane = TestPane()
        let model = Self.makeModel(.init(view: pane))
        let projectID = try #require(model.state.focusedProject)
        model.setProjectNote(projectID, to: "the note survives\nthe shell does not")
        #expect(model.markPaneTerminated(Self.paneID(pane)))

        let data = try JSONEncoder().encode(model.state)
        let decoded = try JSONDecoder().decode(TestWorkspaceState.self, from: data)

        let project = try #require(decoded.projects[projectID])
        #expect(project.note == "the note survives\nthe shell does not")
        // The terminated state itself is runtime-only: a restore re-attaches
        // every pane, so the project comes back live.
        #expect(!project.isTerminated)
    }

    @Test func aSplitProjectWithTerminatedPanesRoundTripsWithEveryPane() throws {
        let a = TestPane()
        let b = TestPane()
        let c = TestPane()
        let tree = try SplitTree<TestPane>(view: a)
            .inserting(view: b, at: a, direction: .right)
            .inserting(view: c, at: b, direction: .down)
        let model = Self.makeModel(tree)
        let projectID = try #require(model.state.focusedProject)
        #expect(model.markPaneTerminated(Self.paneID(a)))
        #expect(model.markPaneTerminated(Self.paneID(c)))

        let data = try JSONEncoder().encode(model.state)
        let decoded = try JSONDecoder().decode(TestWorkspaceState.self, from: data)

        let project = try #require(decoded.projects[projectID])
        #expect(project.paneTree.root == tree.root)
        #expect(project.primaryPane == Self.paneID(a))
        #expect(!project.isTerminated)
    }

    // MARK: Enter restart (SPEC §23.3, must 30)

    @Test func restartTerminatedPanesStartsFreshPaneInSameSlot() throws {
        let pane = TestPane()
        let model = Self.makeModel(.init(view: pane))
        let projectID = try #require(model.state.focusedProject)
        model.setProjectNote(projectID, to: "keep me")
        #expect(model.markPaneTerminated(Self.paneID(pane)))
        model.setFocusedSurface(Self.paneID(pane))

        let fresh = TestPane()
        let restarted = model.restartTerminatedPanes(
            in: projectID, with: [Self.paneID(pane): fresh])

        #expect(restarted)
        let project = try #require(model.state.projects[projectID])
        #expect(!project.isTerminated)
        #expect(project.paneTree.find(id: fresh.id) != nil)
        #expect(project.paneTree.find(id: pane.id) == nil)
        #expect(!project.paneTree.isSplit)
        #expect(project.primaryPane == Self.paneID(fresh))
        #expect(project.focusedSurface == Self.paneID(fresh))
        #expect(project.note == "keep me")
    }

    @Test func restartReplacesEveryTerminatedPaneInItsSlotAndLeavesLivePanes() throws {
        // [A | (B / C)] with A primary; A and C terminated, B live. One
        // restart replaces A and C in place: the layout, the primary slot and
        // B are unchanged.
        let a = TestPane()
        let b = TestPane()
        let c = TestPane()
        let tree = try SplitTree<TestPane>(view: a)
            .inserting(view: b, at: a, direction: .right)
            .inserting(view: c, at: b, direction: .down)
        let model = Self.makeModel(tree)
        let projectID = try #require(model.state.focusedProject)
        #expect(model.markPaneTerminated(Self.paneID(a)))
        #expect(model.markPaneTerminated(Self.paneID(c)))
        #expect(model.terminatedPanes(in: projectID) == [a, c].map(Self.paneID))

        let freshA = TestPane()
        let freshC = TestPane()
        let restarted = model.restartTerminatedPanes(
            in: projectID, with: [Self.paneID(a): freshA, Self.paneID(c): freshC])

        #expect(restarted)
        let project = try #require(model.state.projects[projectID])
        let expected = try SplitTree<TestPane>(view: freshA)
            .inserting(view: b, at: freshA, direction: .right)
            .inserting(view: freshC, at: b, direction: .down)
        #expect(project.paneTree.root == expected.root)
        #expect(project.primaryPane == Self.paneID(freshA))
        #expect(!project.isTerminated)
    }

    @Test func restartIsRejectedUnlessItReplacesExactlyTheTerminatedPanes() throws {
        let a = TestPane()
        let b = TestPane()
        let tree = try SplitTree<TestPane>(view: a).inserting(view: b, at: a, direction: .right)
        let model = Self.makeModel(tree)
        let projectID = try #require(model.state.focusedProject)

        // Nothing terminated.
        #expect(!model.restartTerminatedPanes(in: projectID, with: [Self.paneID(a): TestPane()]))

        // A terminated, but the replacements name a live pane or miss A.
        #expect(model.markPaneTerminated(Self.paneID(a)))
        #expect(!model.restartTerminatedPanes(in: projectID, with: [Self.paneID(b): TestPane()]))
        #expect(!model.restartTerminatedPanes(in: projectID, with: [:]))
        #expect(!model.restartTerminatedPanes(
            in: projectID, with: [Self.paneID(a): TestPane(), Self.paneID(b): TestPane()]))

        let project = try #require(model.state.projects[projectID])
        #expect(project.paneTree.root == tree.root)
        #expect(project.terminatedPanes == [Self.paneID(a)])
    }

    // MARK: Keys on an exited pane (SPEC §23.3)

    @Test func keybindsOnAnExitedPaneGoToTheCore() {
        // Cmd+L, Cmd+Shift+, or Cmd+Opt+Enter keep working on an exited pane:
        // a keybind is never a restart or a close, even when it is Return.
        #expect(ExitedPaneKeyRoute.route(isBinding: true, isReturn: false, hasModifiers: true)
                == .binding)
        #expect(ExitedPaneKeyRoute.route(isBinding: true, isReturn: true, hasModifiers: true)
                == .binding)
    }

    @Test func onlyAPlainReturnRestartsATerminatedPane() {
        #expect(ExitedPaneKeyRoute.route(isBinding: false, isReturn: true, hasModifiers: false)
                == .project(isRestart: true))
        #expect(ExitedPaneKeyRoute.route(isBinding: false, isReturn: true, hasModifiers: true)
                == .project(isRestart: false))
        #expect(ExitedPaneKeyRoute.route(isBinding: false, isReturn: false, hasModifiers: false)
                == .project(isRestart: false))
    }
}
