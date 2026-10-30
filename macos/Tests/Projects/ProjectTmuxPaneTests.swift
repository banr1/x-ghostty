import Foundation
import Testing
@testable import XGhostty

/// A value-type pane element standing in for `XGhostty.SurfaceView`, which
/// cannot be constructed without a live XGhostty app. The generic model layer
/// runs the exact same code for both element types.
private struct TestPane: Codable, Identifiable, Equatable {
    let id: UUID
    init(id: UUID = UUID()) { self.id = id }
}

private typealias TestProjectState = ProjectStateOf<TestPane>

/// Tests for each pane's tmux session (must 129, 133, 136 items 8 and 9): the
/// binding of a pane to its terminal and pane index, its save and restore, and
/// the sessions to kill after closed panes' undo period.
struct ProjectTmuxPaneTests {
    private static let terminals = ProjectTerminalRegistry(
        registrations: ["mini,mac-mini,colour33", "loop,mini-loopback,colour166"],
        hostname: "mac-mini")

    private static func makeProject(
        _ pane: TestPane,
        terminalName: String? = nil
    ) -> TestProjectState {
        TestProjectState(
            id: ProjectID(),
            name: "alpha",
            paneTree: .init(view: pane),
            terminalName: terminalName,
            createdAt: Date(timeIntervalSince1970: 0))
    }

    private static func roundTrip(_ project: TestProjectState) throws -> TestProjectState {
        let data = try JSONEncoder().encode(project)
        return try JSONDecoder().decode(TestProjectState.self, from: data)
    }

    private static func sid(_ pane: TestPane) -> SurfaceID {
        SurfaceID(rawValue: pane.id)
    }

    // MARK: Binding

    @Test func panesBindToTheProjectTerminalWithIncreasingIndices() throws {
        let first = TestPane()
        let second = TestPane()
        var project = Self.makeProject(first, terminalName: "loop")
        project.paneTree = try project.paneTree.inserting(view: second, at: first, direction: .right)

        let a = project.bindPane(Self.sid(first))
        let b = project.bindPane(Self.sid(second))
        #expect(a == TmuxPaneBinding(terminalName: "loop", index: 1))
        #expect(b == TmuxPaneBinding(terminalName: "loop", index: 2))
        let prefix = project.id.rawValue.uuidString.lowercased()
        #expect(project.sessionName(for: Self.sid(first)) == "\(prefix)-1")
        #expect(project.sessionName(for: Self.sid(second)) == "\(prefix)-2")
    }

    @Test func bindingIsFixedOnceAndIgnoresLaterTerminalChanges() {
        let pane = TestPane()
        var project = Self.makeProject(pane)
        let initial = project.bindPane(Self.sid(pane))
        project.terminalName = "loop"
        let again = project.bindPane(Self.sid(pane))
        #expect(initial == TmuxPaneBinding(terminalName: nil, index: 1))
        #expect(again == initial)
    }

    @Test func aPaneOutsideTheTreeIsNotBound() {
        var project = Self.makeProject(TestPane())
        let stranger = TestPane()
        let binding = project.bindPane(Self.sid(stranger))
        #expect(binding == nil)
        #expect(project.paneBindings.isEmpty)
        #expect(project.sessionName(for: Self.sid(stranger)) == nil)
    }

    @Test func aClosedPaneIndexIsNeverReused() throws {
        let first = TestPane()
        let second = TestPane()
        let third = TestPane()
        var project = Self.makeProject(first)
        project.bindPane(Self.sid(first))
        project.paneTree = try project.paneTree.inserting(view: second, at: first, direction: .right)
        project.bindPane(Self.sid(second))
        project.paneTree = project.paneTree.removing(.leaf(view: second))
        project.paneTree = try project.paneTree.inserting(view: third, at: first, direction: .right)

        let binding = project.bindPane(Self.sid(third))
        #expect(binding?.index == 3)
    }

    @Test func aSplitAfterATerminalChangeStartsOnTheNewTerminal() throws {
        let first = TestPane()
        let second = TestPane()
        var project = Self.makeProject(first)
        project.bindPane(Self.sid(first))
        project.terminalName = "loop"
        project.paneTree = try project.paneTree.inserting(view: second, at: first, direction: .right)
        let binding = project.bindPane(Self.sid(second))
        #expect(binding == TmuxPaneBinding(terminalName: "loop", index: 2))
        #expect(project.paneBindings[Self.sid(first)]?.terminalName == nil)
    }

    @Test func restartingATerminatedPaneKeepsItsSession() {
        let dead = TestPane()
        let fresh = TestPane()
        var project = Self.makeProject(dead, terminalName: "mini")
        project.bindPane(Self.sid(dead))
        let session = project.sessionName(for: Self.sid(dead))
        let marked = project.markPaneTerminated(Self.sid(dead))
        let restarted = project.restartTerminatedPane(with: fresh)

        #expect(marked)
        #expect(restarted)
        #expect(project.sessionName(for: Self.sid(fresh)) == session)
        #expect(project.paneBindings[Self.sid(fresh)]?.terminalName == "mini")
        #expect(project.paneBindings[Self.sid(dead)] == nil)
    }

    // MARK: Save and restore (C136 item 9)

    @Test func paneTerminalsAndSessionNamesRoundTrip() throws {
        let first = TestPane()
        let second = TestPane()
        var project = Self.makeProject(first)
        project.bindPane(Self.sid(first))
        project.terminalName = "loop"
        project.paneTree = try project.paneTree.inserting(view: second, at: first, direction: .right)
        project.bindPane(Self.sid(second))

        let restored = try Self.roundTrip(project)
        #expect(restored.paneBindings == project.paneBindings)
        #expect(restored.paneBindings[Self.sid(first)] == TmuxPaneBinding(terminalName: nil, index: 1))
        #expect(restored.paneBindings[Self.sid(second)] == TmuxPaneBinding(terminalName: "loop", index: 2))
        #expect(restored.sessionName(for: Self.sid(second)) == project.sessionName(for: Self.sid(second)))
        #expect(restored.lastPaneIndex == 2)
    }

    @Test func saveKeepsOnlyPanesInTheTreeButKeepsTheHighestIndex() throws {
        let first = TestPane()
        let second = TestPane()
        let third = TestPane()
        var project = Self.makeProject(first)
        project.bindPane(Self.sid(first))
        project.paneTree = try project.paneTree.inserting(view: second, at: first, direction: .right)
        project.bindPane(Self.sid(second))
        project.paneTree = project.paneTree.removing(.leaf(view: second))

        var restored = try Self.roundTrip(project)
        #expect(Set(restored.paneBindings.keys) == [Self.sid(first)])
        #expect(restored.lastPaneIndex == 2)
        restored.paneTree = try restored.paneTree.inserting(view: third, at: first, direction: .right)
        let binding = restored.bindPane(Self.sid(third))
        #expect(binding?.index == 3)
    }

    @Test func aSaveWithoutPaneSessionsRestoresUnboundPanes() throws {
        let pane = TestPane()
        let project = Self.makeProject(pane)
        var json = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(project)) as? [String: Any])
        json.removeValue(forKey: "paneSessions")
        json.removeValue(forKey: "lastPaneIndex")
        let data = try JSONSerialization.data(withJSONObject: json)

        var restored = try JSONDecoder().decode(TestProjectState.self, from: data)
        #expect(restored.paneBindings.isEmpty)
        #expect(restored.lastPaneIndex == 0)
        let binding = restored.bindPane(Self.sid(pane))
        #expect(binding?.index == 1)
    }

    // MARK: Kill targets (C136 item 8)

    @Test func killTargetsAreSessionNamesGroupedByTerminal() throws {
        let first = TestPane()
        let second = TestPane()
        let third = TestPane()
        var project = Self.makeProject(first)
        project.bindPane(Self.sid(first))
        project.terminalName = "loop"
        project.paneTree = try project.paneTree.inserting(view: second, at: first, direction: .right)
        project.bindPane(Self.sid(second))
        project.paneTree = try project.paneTree.inserting(view: third, at: second, direction: .down)
        project.bindPane(Self.sid(third))

        let closed = project.tmuxPanesInTree
        let targets = TmuxSession.killTargets(closed: closed, open: [], registry: Self.terminals)

        let local = Self.terminals.local
        let loop = try #require(Self.terminals.registeredTerminal(named: "loop"))
        let s1 = try #require(project.sessionName(for: Self.sid(first)))
        let s2 = try #require(project.sessionName(for: Self.sid(second)))
        let s3 = try #require(project.sessionName(for: Self.sid(third)))
        #expect(targets.count == 2)
        #expect(targets[local] == [s1])
        #expect(targets[loop] == [s2, s3])
    }

    @Test func aPaneBroughtBackByUndoIsNotKilled() throws {
        let first = TestPane()
        let second = TestPane()
        var project = Self.makeProject(first)
        project.bindPane(Self.sid(first))
        project.paneTree = try project.paneTree.inserting(view: second, at: first, direction: .right)
        project.bindPane(Self.sid(second))

        let closed = project.closedTmuxPanes([Self.sid(first), Self.sid(second)])
        let targets = TmuxSession.killTargets(
            closed: closed, open: [Self.sid(second)], registry: Self.terminals)
        let s1 = try #require(project.sessionName(for: Self.sid(first)))
        #expect(targets == [Self.terminals.local: [s1]])

        let none = TmuxSession.killTargets(
            closed: closed, open: [Self.sid(first), Self.sid(second)], registry: Self.terminals)
        #expect(none.isEmpty)
    }

    @Test func aTerminatedPaneIsAKillTargetWhenItsProjectCloses() throws {
        let pane = TestPane()
        var project = Self.makeProject(pane, terminalName: "mini")
        project.bindPane(Self.sid(pane))
        let marked = project.markPaneTerminated(Self.sid(pane))
        #expect(marked)

        let targets = TmuxSession.killTargets(
            closed: project.tmuxPanesInTree, open: [], registry: Self.terminals)
        let mini = try #require(Self.terminals.registeredTerminal(named: "mini"))
        let session = try #require(project.sessionName(for: Self.sid(pane)))
        #expect(targets == [mini: [session]])
    }

    @Test func unboundPanesAndUnregisteredTerminalsResolveLikeTheProject() throws {
        let bound = TestPane()
        let unbound = TestPane()
        var project = Self.makeProject(bound, terminalName: "gone")
        project.bindPane(Self.sid(bound))
        project.paneTree = try project.paneTree.inserting(view: unbound, at: bound, direction: .right)

        let closed = project.tmuxPanesInTree
        #expect(closed.map(\.pane) == [Self.sid(bound)])
        let targets = TmuxSession.killTargets(closed: closed, open: [], registry: Self.terminals)
        let session = try #require(project.sessionName(for: Self.sid(bound)))
        #expect(targets == [Self.terminals.local: [session]])
    }
}
