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
/// always-confirm project close, the child-exit judgment (terminated last pane
/// vs. closing sibling pane), the terminated state's persistence semantics,
/// and the Enter-restart transition.
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

    // MARK: Child-exit judgment (SPEC §23.2)

    @Test func lastPaneExitIsJudgedTerminatedForEveryExitKind() throws {
        let pane = TestPane()
        let model = Self.makeModel(.init(view: pane))
        let projectID = try #require(model.state.focusedProject)

        // Normal exit, abnormal exit, and process death all reach the model
        // the same way; a last pane is always `.terminated`.
        #expect(model.childExitOutcome(for: Self.paneID(pane), abnormalExit: false)
                == .terminated(projectID))
        #expect(model.childExitOutcome(for: Self.paneID(pane), abnormalExit: true)
                == .terminated(projectID))
    }

    @Test func siblingPaneNormalExitIsJudgedClosePane() throws {
        let a = TestPane()
        let b = TestPane()
        let model = Self.makeModel(try .init(view: a).inserting(view: b, at: a, direction: .right))
        let projectID = try #require(model.state.focusedProject)

        #expect(model.childExitOutcome(for: Self.paneID(b), abnormalExit: false)
                == .closePane(projectID))
    }

    @Test func siblingPaneAbnormalExitAwaitsKeyClose() throws {
        let a = TestPane()
        let b = TestPane()
        let model = Self.makeModel(try .init(view: a).inserting(view: b, at: a, direction: .right))
        let projectID = try #require(model.state.focusedProject)

        #expect(model.childExitOutcome(for: Self.paneID(b), abnormalExit: true)
                == .keepPaneAwaitingKey(projectID))
    }

    @Test func unknownPaneExitHasNoOutcome() {
        let model = Self.makeModel(.init(view: TestPane()))
        #expect(model.childExitOutcome(for: SurfaceID(rawValue: UUID()), abnormalExit: false) == nil)
    }

    @Test func exitOutcomeIsRejudgedAfterSiblingsClosed() throws {
        // [A | B] where A exited abnormally and awaits a key. If B closes
        // first, A becomes the project's last pane — a later judgment must be
        // `.terminated`, not a close (deletion protection).
        let a = TestPane()
        let b = TestPane()
        let model = Self.makeModel(try .init(view: a).inserting(view: b, at: a, direction: .right))
        let projectID = try #require(model.state.focusedProject)
        #expect(model.childExitOutcome(for: Self.paneID(a), abnormalExit: true)
                == .keepPaneAwaitingKey(projectID))

        model.replaceFocusedPaneTree(model.focusedPaneTree.removing(.leaf(view: b)))

        #expect(model.childExitOutcome(for: Self.paneID(a), abnormalExit: true)
                == .terminated(projectID))
    }

    // MARK: Terminated state (SPEC §23.2)

    @Test func markPaneTerminatedKeepsProjectWithNoteAndPane() throws {
        let pane = TestPane()
        let model = Self.makeModel(.init(view: pane))
        let projectID = try #require(model.state.focusedProject)
        model.setProjectNote(projectID, to: "deploy at five\ncheck the logs")

        let marked = model.markPaneTerminated(Self.paneID(pane))

        #expect(marked)
        let project = try #require(model.state.projects[projectID])
        #expect(project.isTerminated)
        #expect(model.isProjectTerminated(projectID))
        #expect(project.terminatedPane == Self.paneID(pane))
        #expect(project.paneTree.find(id: pane.id) != nil)
        #expect(project.note == "deploy at five\ncheck the logs")
    }

    @Test func markPaneTerminatedRejectsPaneAmongSeveral() throws {
        let a = TestPane()
        let b = TestPane()
        let model = Self.makeModel(try .init(view: a).inserting(view: b, at: a, direction: .right))
        let projectID = try #require(model.state.focusedProject)

        #expect(!model.markPaneTerminated(Self.paneID(b)))
        #expect(!model.isProjectTerminated(projectID))
    }

    @Test func terminatedPrimaryLastPaneKeepsItsPrimaryFlag() throws {
        // The primary-close last-pane path follows the terminated-state
        // semantics: the sole pane is the primary, and terminating it keeps
        // both the pane and its flag in place.
        let pane = TestPane()
        let model = Self.makeModel(.init(view: pane))
        let projectID = try #require(model.state.focusedProject)

        #expect(model.markPaneTerminated(Self.paneID(pane)))
        #expect(model.state.projects[projectID]?.primaryPane == Self.paneID(pane))
    }

    @Test func splittingWhileTerminatedClearsTheTerminatedState() throws {
        let pane = TestPane()
        let model = Self.makeModel(.init(view: pane))
        let projectID = try #require(model.state.focusedProject)
        #expect(model.markPaneTerminated(Self.paneID(pane)))

        // The terminated state is defined only for a sole last pane: a tree
        // that grows past one pane leaves it.
        let other = TestPane()
        model.replaceFocusedPaneTree(
            try model.focusedPaneTree.inserting(view: other, at: pane, direction: .right))

        #expect(!model.isProjectTerminated(projectID))
    }

    // MARK: Sibling-pane close (SPEC §23.2)

    @Test func removeExitedPaneClosesOnlyThatPane() throws {
        let a = TestPane()
        let b = TestPane()
        let model = Self.makeModel(try .init(view: a).inserting(view: b, at: a, direction: .right))
        let projectID = try #require(model.state.focusedProject)
        model.setProjectNote(projectID, to: "still here")

        let removed = model.removeExitedPane(Self.paneID(b))

        #expect(removed)
        let project = try #require(model.state.projects[projectID])
        #expect(project.paneTree.find(id: b.id) == nil)
        #expect(project.paneTree.find(id: a.id) != nil)
        #expect(!project.isTerminated)
        #expect(project.note == "still here")
    }

    @Test func removeExitedPaneRejectsAProjectsLastPane() throws {
        let pane = TestPane()
        let model = Self.makeModel(.init(view: pane))
        let projectID = try #require(model.state.focusedProject)

        // A last pane is never removed by the exit path: that case is
        // `.terminated` (the project must not close).
        #expect(!model.removeExitedPane(Self.paneID(pane)))
        #expect(model.state.projects[projectID]?.paneTree.find(id: pane.id) != nil)
    }

    @Test func removeExitedPaneWorksForHiddenProjects() throws {
        // Two projects; hide the second (multi-pane) one, then close one of its
        // exited panes model-side — the path the controller uses for panes
        // outside the focused project's mirrored tree.
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

        #expect(model.projectID(containing: Self.paneID(hiddenB)) == hiddenProject.id)
        #expect(model.removeExitedPane(Self.paneID(hiddenB)))
        let project = try #require(model.state.projects[hiddenProject.id])
        #expect(project.paneTree.find(id: hiddenB.id) == nil)
        #expect(project.paneTree.find(id: hiddenA.id) != nil)
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
        // The terminated state itself is runtime-only: a restore recreates
        // every pane with a fresh shell, so the project comes back live.
        #expect(!project.isTerminated)
    }

    // MARK: Enter restart (SPEC §23.3)

    @Test func restartTerminatedPaneStartsFreshPaneInSameSlot() throws {
        let pane = TestPane()
        let model = Self.makeModel(.init(view: pane))
        let projectID = try #require(model.state.focusedProject)
        model.setProjectNote(projectID, to: "keep me")
        #expect(model.markPaneTerminated(Self.paneID(pane)))

        let fresh = TestPane()
        let restarted = model.restartTerminatedPane(in: projectID, with: fresh)

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

    @Test func restartIsRejectedWhenNotTerminated() throws {
        let pane = TestPane()
        let model = Self.makeModel(.init(view: pane))
        let projectID = try #require(model.state.focusedProject)

        #expect(!model.restartTerminatedPane(in: projectID, with: TestPane()))
        #expect(model.state.projects[projectID]?.paneTree.find(id: pane.id) != nil)
    }
}
