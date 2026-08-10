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

private typealias TestGroupState = GroupStateOf<TestPane>
private typealias TestWorkspaceState = WorkspaceStateOf<TestPane>
private typealias TestWorkspaceModel = WorkspaceModelOf<TestPane>

/// Tests for the deletion-protection model layer (SPEC §23): the
/// always-confirm group close, the child-exit judgment (terminated last pane
/// vs. closing sibling pane), the terminated state's persistence semantics,
/// and the Enter-restart transition.
struct GroupTerminatedTests {
    /// A single-group model around `tree`, with a deterministic name.
    private static func makeModel(_ tree: SplitTree<TestPane>) -> TestWorkspaceModel {
        TestWorkspaceModel(wrapping: tree, name: "amber-owl")
    }

    private static func paneID(_ pane: TestPane) -> SurfaceID {
        SurfaceID(rawValue: pane.id)
    }

    // MARK: Always-confirm group close (SPEC §23.1)

    @Test func closeGroupRequiresConfirmationRegardlessOfRunningProcesses() {
        let model = Self.makeModel(.init(view: TestPane()))

        // The confirmation requirement never depends on whether a process is
        // alive: the dialog is the single sanctioned loss path for a group.
        #expect(model.closeGroupRequiresConfirmation(anyLiveProcess: true))
        #expect(model.closeGroupRequiresConfirmation(anyLiveProcess: false))
    }

    // MARK: Child-exit judgment (SPEC §23.2)

    @Test func lastPaneExitIsJudgedTerminatedForEveryExitKind() throws {
        let pane = TestPane()
        let model = Self.makeModel(.init(view: pane))
        let groupID = try #require(model.state.focusedGroup)

        // Normal exit, abnormal exit, and process death all reach the model
        // the same way; a last pane is always `.terminated`.
        #expect(model.childExitOutcome(for: Self.paneID(pane), abnormalExit: false)
                == .terminated(groupID))
        #expect(model.childExitOutcome(for: Self.paneID(pane), abnormalExit: true)
                == .terminated(groupID))
    }

    @Test func siblingPaneNormalExitIsJudgedClosePane() throws {
        let a = TestPane()
        let b = TestPane()
        let model = Self.makeModel(try .init(view: a).inserting(view: b, at: a, direction: .right))
        let groupID = try #require(model.state.focusedGroup)

        #expect(model.childExitOutcome(for: Self.paneID(b), abnormalExit: false)
                == .closePane(groupID))
    }

    @Test func siblingPaneAbnormalExitAwaitsKeyClose() throws {
        let a = TestPane()
        let b = TestPane()
        let model = Self.makeModel(try .init(view: a).inserting(view: b, at: a, direction: .right))
        let groupID = try #require(model.state.focusedGroup)

        #expect(model.childExitOutcome(for: Self.paneID(b), abnormalExit: true)
                == .keepPaneAwaitingKey(groupID))
    }

    @Test func unknownPaneExitHasNoOutcome() {
        let model = Self.makeModel(.init(view: TestPane()))
        #expect(model.childExitOutcome(for: SurfaceID(rawValue: UUID()), abnormalExit: false) == nil)
    }

    @Test func exitOutcomeIsRejudgedAfterSiblingsClosed() throws {
        // [A | B] where A exited abnormally and awaits a key. If B closes
        // first, A becomes the group's last pane — a later judgment must be
        // `.terminated`, not a close (deletion protection).
        let a = TestPane()
        let b = TestPane()
        let model = Self.makeModel(try .init(view: a).inserting(view: b, at: a, direction: .right))
        let groupID = try #require(model.state.focusedGroup)
        #expect(model.childExitOutcome(for: Self.paneID(a), abnormalExit: true)
                == .keepPaneAwaitingKey(groupID))

        model.replaceFocusedPaneTree(model.focusedPaneTree.removing(.leaf(view: b)))

        #expect(model.childExitOutcome(for: Self.paneID(a), abnormalExit: true)
                == .terminated(groupID))
    }

    // MARK: Terminated state (SPEC §23.2)

    @Test func markPaneTerminatedKeepsGroupWithNoteAndPane() throws {
        let pane = TestPane()
        let model = Self.makeModel(.init(view: pane))
        let groupID = try #require(model.state.focusedGroup)
        model.setGroupNote(groupID, to: "deploy at five\ncheck the logs")

        let marked = model.markPaneTerminated(Self.paneID(pane))

        #expect(marked)
        let group = try #require(model.state.groups[groupID])
        #expect(group.isTerminated)
        #expect(model.isGroupTerminated(groupID))
        #expect(group.terminatedPane == Self.paneID(pane))
        #expect(group.paneTree.find(id: pane.id) != nil)
        #expect(group.note == "deploy at five\ncheck the logs")
    }

    @Test func markPaneTerminatedRejectsPaneAmongSeveral() throws {
        let a = TestPane()
        let b = TestPane()
        let model = Self.makeModel(try .init(view: a).inserting(view: b, at: a, direction: .right))
        let groupID = try #require(model.state.focusedGroup)

        #expect(!model.markPaneTerminated(Self.paneID(b)))
        #expect(!model.isGroupTerminated(groupID))
    }

    @Test func terminatedPrimaryLastPaneKeepsItsPrimaryFlag() throws {
        // The primary-close last-pane path follows the terminated-state
        // semantics: the sole pane is the primary, and terminating it keeps
        // both the pane and its flag in place.
        let pane = TestPane()
        let model = Self.makeModel(.init(view: pane))
        let groupID = try #require(model.state.focusedGroup)

        #expect(model.markPaneTerminated(Self.paneID(pane)))
        #expect(model.state.groups[groupID]?.primaryPane == Self.paneID(pane))
    }

    @Test func splittingWhileTerminatedClearsTheTerminatedState() throws {
        let pane = TestPane()
        let model = Self.makeModel(.init(view: pane))
        let groupID = try #require(model.state.focusedGroup)
        #expect(model.markPaneTerminated(Self.paneID(pane)))

        // The terminated state is defined only for a sole last pane: a tree
        // that grows past one pane leaves it.
        let other = TestPane()
        model.replaceFocusedPaneTree(
            try model.focusedPaneTree.inserting(view: other, at: pane, direction: .right))

        #expect(!model.isGroupTerminated(groupID))
    }

    // MARK: Sibling-pane close (SPEC §23.2)

    @Test func removeExitedPaneClosesOnlyThatPane() throws {
        let a = TestPane()
        let b = TestPane()
        let model = Self.makeModel(try .init(view: a).inserting(view: b, at: a, direction: .right))
        let groupID = try #require(model.state.focusedGroup)
        model.setGroupNote(groupID, to: "still here")

        let removed = model.removeExitedPane(Self.paneID(b))

        #expect(removed)
        let group = try #require(model.state.groups[groupID])
        #expect(group.paneTree.find(id: b.id) == nil)
        #expect(group.paneTree.find(id: a.id) != nil)
        #expect(!group.isTerminated)
        #expect(group.note == "still here")
    }

    @Test func removeExitedPaneRejectsAGroupsLastPane() throws {
        let pane = TestPane()
        let model = Self.makeModel(.init(view: pane))
        let groupID = try #require(model.state.focusedGroup)

        // A last pane is never removed by the exit path: that case is
        // `.terminated` (the group must not close).
        #expect(!model.removeExitedPane(Self.paneID(pane)))
        #expect(model.state.groups[groupID]?.paneTree.find(id: pane.id) != nil)
    }

    @Test func removeExitedPaneWorksForHiddenGroups() throws {
        // Two groups; hide the second (multi-pane) one, then close one of its
        // exited panes model-side — the path the controller uses for panes
        // outside the focused group's mirrored tree.
        let visible = TestPane()
        let hiddenA = TestPane()
        let hiddenB = TestPane()

        let visibleGroup = TestGroupState(
            id: GroupID(), name: "visible", paneTree: .init(view: visible), createdAt: Date())
        let hiddenGroup = TestGroupState(
            id: GroupID(), name: "hidden",
            paneTree: try .init(view: hiddenA).inserting(view: hiddenB, at: hiddenA, direction: .right),
            createdAt: Date())

        let model = TestWorkspaceModel(TestWorkspaceState(
            canonicalGroupTree: .init(view: GroupRef(id: visibleGroup.id)),
            groups: [visibleGroup.id: visibleGroup, hiddenGroup.id: hiddenGroup],
            hiddenGroupIDs: [hiddenGroup.id],
            focusedGroup: visibleGroup.id))

        #expect(model.groupID(containing: Self.paneID(hiddenB)) == hiddenGroup.id)
        #expect(model.removeExitedPane(Self.paneID(hiddenB)))
        let group = try #require(model.state.groups[hiddenGroup.id])
        #expect(group.paneTree.find(id: hiddenB.id) == nil)
        #expect(group.paneTree.find(id: hiddenA.id) != nil)
    }

    // MARK: Persistence (SPEC §23.4)

    @Test func terminatedGroupRoundTripKeepsNote() throws {
        let pane = TestPane()
        let model = Self.makeModel(.init(view: pane))
        let groupID = try #require(model.state.focusedGroup)
        model.setGroupNote(groupID, to: "the note survives\nthe shell does not")
        #expect(model.markPaneTerminated(Self.paneID(pane)))

        let data = try JSONEncoder().encode(model.state)
        let decoded = try JSONDecoder().decode(TestWorkspaceState.self, from: data)

        let group = try #require(decoded.groups[groupID])
        #expect(group.note == "the note survives\nthe shell does not")
        // The terminated state itself is runtime-only: a restore recreates
        // every pane with a fresh shell, so the group comes back live.
        #expect(!group.isTerminated)
    }

    // MARK: Enter restart (SPEC §23.3)

    @Test func restartTerminatedPaneStartsFreshPaneInSameSlot() throws {
        let pane = TestPane()
        let model = Self.makeModel(.init(view: pane))
        let groupID = try #require(model.state.focusedGroup)
        model.setGroupNote(groupID, to: "keep me")
        #expect(model.markPaneTerminated(Self.paneID(pane)))

        let fresh = TestPane()
        let restarted = model.restartTerminatedPane(in: groupID, with: fresh)

        #expect(restarted)
        let group = try #require(model.state.groups[groupID])
        #expect(!group.isTerminated)
        #expect(group.paneTree.find(id: fresh.id) != nil)
        #expect(group.paneTree.find(id: pane.id) == nil)
        #expect(!group.paneTree.isSplit)
        #expect(group.primaryPane == Self.paneID(fresh))
        #expect(group.focusedSurface == Self.paneID(fresh))
        #expect(group.note == "keep me")
    }

    @Test func restartIsRejectedWhenNotTerminated() throws {
        let pane = TestPane()
        let model = Self.makeModel(.init(view: pane))
        let groupID = try #require(model.state.focusedGroup)

        #expect(!model.restartTerminatedPane(in: groupID, with: TestPane()))
        #expect(model.state.groups[groupID]?.paneTree.find(id: pane.id) != nil)
    }
}
