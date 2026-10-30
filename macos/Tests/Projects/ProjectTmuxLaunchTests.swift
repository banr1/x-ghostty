import Foundation
import Testing
@testable import XGhostty

/// A value-type pane element standing in for `XGhostty.SurfaceView`. Like
/// the real surface, a decoded pane asks `TmuxPaneRestore` for the command it
/// starts with.
private struct LaunchPane: Codable, Identifiable, Equatable {
    let id: UUID
    let command: String?

    init(id: UUID = UUID(), command: String? = nil) {
        self.id = id
        self.command = command
    }

    enum CodingKeys: String, CodingKey { case id }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        command = TmuxPaneRestore.command(for: id)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
    }
}

private typealias LaunchProjectState = ProjectStateOf<LaunchPane>

/// Tests for the command each pane starts with (must 129, 130, 132): a new
/// project's pane, a split, the restart of a terminated pane and a restored
/// pane all start as the attach command of their own tmux session.
struct ProjectTmuxLaunchTests {
    private static let terminals = ProjectTerminalRegistry(
        registrations: ["mini,mac-mini,colour33", "loop,mini-loopback,colour166"],
        hostname: "mac-mini")

    private static func sid(_ pane: LaunchPane) -> SurfaceID {
        SurfaceID(rawValue: pane.id)
    }

    private static func newProject(name: String = "alpha") -> LaunchProjectState {
        LaunchProjectState.new(
            id: ProjectID(),
            name: name,
            createdAt: Date(timeIntervalSince1970: 0),
            registry: terminals
        ) { id, command in LaunchPane(id: id, command: command) }
    }

    private static func attach(
        _ project: LaunchProjectState,
        index: Int,
        start: TmuxStartDirectory = .project,
        terminal: String? = nil
    ) -> String {
        let resolved = terminals.terminal(named: terminal)
        return TmuxSession.attachCommand(
            session: TmuxSession.name(project: project.id, index: index),
            title: project.name,
            start: start,
            terminal: resolved,
            isLocal: terminals.isLocal(resolved))
    }

    // MARK: New project

    @Test func aNewProjectPaneStartsAsTheAttachCommandOfItsFirstSession() throws {
        let project = Self.newProject()
        let pane = try #require(project.paneTree.firstLeaf)
        #expect(Array(project.paneTree).count == 1)
        #expect(pane.command == Self.attach(project, index: 1))
        #expect(project.paneBindings[Self.sid(pane)] == TmuxPaneBinding(terminalName: nil, index: 1))
        #expect(project.focusedSurface == Self.sid(pane))
        #expect(project.isPrimary(Self.sid(pane)))
        let command = try #require(pane.command)
        #expect(command.contains("tmux new-session -A -s"))
        #expect(!command.contains("ssh"))
    }

    // MARK: Split

    @Test func aSplitAttachesToANewSessionOnTheCurrentTerminalInheritingThePath() throws {
        var project = Self.newProject()
        let origin = try #require(project.paneTree.firstLeaf)
        project.terminalName = "loop"
        let newID = SurfaceID(rawValue: UUID())

        let command = project.splitLaunchCommand(
            newPane: newID, splitting: Self.sid(origin), registry: Self.terminals)

        let originSession = try #require(project.sessionName(for: Self.sid(origin)))
        #expect(command == Self.attach(
            project, index: 2, start: .inherit(fromSession: originSession), terminal: "loop"))
        #expect(command.contains("#{pane_current_path}"))
        #expect(command.contains("ssh -t"))
        #expect(command.contains("TERM=xterm-256color"))
        #expect(project.paneBindings[newID] == TmuxPaneBinding(terminalName: "loop", index: 2))
        // The split pane keeps the terminal it was started on.
        #expect(project.paneBindings[Self.sid(origin)] == TmuxPaneBinding(terminalName: nil, index: 1))
    }

    @Test func aSplitOfAnUnboundPaneStartsByTheProjectRule() {
        let origin = LaunchPane()
        var project = LaunchProjectState(
            id: ProjectID(), name: "alpha", paneTree: .init(view: origin),
            createdAt: Date(timeIntervalSince1970: 0))
        let newID = SurfaceID(rawValue: UUID())

        let command = project.splitLaunchCommand(
            newPane: newID, splitting: Self.sid(origin), registry: Self.terminals)

        #expect(command == Self.attach(project, index: 1))
        #expect(!command.contains("#{pane_current_path}"))
    }

    // MARK: Restart

    @Test func restartingATerminatedPaneReattachesToTheSameSession() throws {
        var project = Self.newProject()
        let dead = try #require(project.paneTree.firstLeaf)
        let marked = project.markPaneTerminated(Self.sid(dead))
        #expect(marked)
        let replacement = LaunchPane()

        let command = project.restartLaunchCommand(
            newPane: Self.sid(replacement), registry: Self.terminals)
        #expect(command == dead.command)

        let restarted = project.restartTerminatedPane(with: replacement)
        #expect(restarted)
        #expect(project.sessionName(for: Self.sid(replacement))
            == TmuxSession.name(project: project.id, index: 1))
        #expect(project.lastPaneIndex == 1)
    }

    @Test func restartingAnUnboundTerminatedPaneStartsAFreshSession() {
        let dead = LaunchPane()
        var project = LaunchProjectState(
            id: ProjectID(), name: "alpha", paneTree: .init(view: dead),
            createdAt: Date(timeIntervalSince1970: 0))
        _ = project.markPaneTerminated(Self.sid(dead))
        let replacement = LaunchPane()

        let command = project.restartLaunchCommand(
            newPane: Self.sid(replacement), registry: Self.terminals)
        #expect(command == Self.attach(project, index: 1))
        _ = project.restartTerminatedPane(with: replacement)
        #expect(project.paneBindings[Self.sid(replacement)] == TmuxPaneBinding(terminalName: nil, index: 1))
    }

    @Test func aLiveProjectHasNoRestartCommand() {
        var project = Self.newProject()
        let command = project.restartLaunchCommand(
            newPane: SurfaceID(rawValue: UUID()), registry: Self.terminals)
        #expect(command == nil)
        #expect(project.paneBindings.count == 1)
    }

    // MARK: Restore

    @Test func restoredPanesReattachToTheirSavedSessions() throws {
        var project = Self.newProject(name: "beta")
        let first = try #require(project.paneTree.firstLeaf)
        let second = LaunchPane()
        _ = project.splitLaunchCommand(
            newPane: Self.sid(second), splitting: Self.sid(first), registry: Self.terminals)
        project.paneTree = try project.paneTree.inserting(view: second, at: first, direction: .right)

        let data = try JSONEncoder().encode(project)
        let restored = try JSONDecoder().decode(LaunchProjectState.self, from: data)

        let registry = ProjectTerminalRegistry.shared
        for (pane, index) in [(first, 1), (second, 2)] {
            let decoded = try #require(restored.paneTree.find(id: pane.id).flatMap {
                if case .leaf(let leaf) = $0 { return leaf } else { return nil }
            })
            #expect(decoded.command == TmuxSession.attachCommand(
                session: TmuxSession.name(project: project.id, index: index),
                title: "beta",
                start: .project,
                terminal: registry.local,
                isLocal: true))
        }
        #expect(restored.paneBindings == project.paneBindings)
        #expect(restored.lastPaneIndex == 2)
    }

    @Test func panesRestoredFromASaveWithoutSessionsAreBoundAsTheyStart() throws {
        let pane = LaunchPane()
        let project = LaunchProjectState(
            id: ProjectID(), name: "gamma", paneTree: .init(view: pane),
            createdAt: Date(timeIntervalSince1970: 0))
        var object = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(project)) as? [String: Any])
        object.removeValue(forKey: "paneSessions")
        object.removeValue(forKey: "lastPaneIndex")
        let data = try JSONSerialization.data(withJSONObject: object)

        let restored = try JSONDecoder().decode(LaunchProjectState.self, from: data)

        let decoded = try #require(restored.paneTree.firstLeaf)
        #expect(restored.paneBindings[Self.sid(pane)] == TmuxPaneBinding(terminalName: nil, index: 1))
        #expect(restored.lastPaneIndex == 1)
        #expect(decoded.command?.contains(TmuxSession.name(project: project.id, index: 1)) == true)
    }

    @Test func aPaneDecodedOutsideAProjectKeepsItsDefaultCommand() throws {
        let pane = LaunchPane()
        let decoded = try JSONDecoder().decode(LaunchPane.self, from: JSONEncoder().encode(pane))
        #expect(decoded.command == nil)
    }

    // MARK: Workspace

    @Test func theWorkspaceBindsASplitInTheProjectHoldingTheOrigin() throws {
        let project = Self.newProject()
        let origin = try #require(project.paneTree.firstLeaf)
        let model = WorkspaceModelOf<LaunchPane>(wrappingProject: project)
        model.terminalRegistry = Self.terminals
        let newID = SurfaceID(rawValue: UUID())

        let command = model.splitLaunchCommand(newPane: newID, splitting: Self.sid(origin))

        #expect(command?.contains("#{pane_current_path}") == true)
        #expect(model.state.projects[project.id]?.paneBindings[newID]
            == TmuxPaneBinding(terminalName: nil, index: 2))
        #expect(model.splitLaunchCommand(
            newPane: SurfaceID(rawValue: UUID()), splitting: SurfaceID(rawValue: UUID())) == nil)
    }

    @Test func aNewWorkspaceProjectIsNamedAndAttached() throws {
        let model = WorkspaceModelOf<LaunchPane>(wrappingProject: Self.newProject(name: "alpha"))
        model.terminalRegistry = Self.terminals

        let created = model.makeNewProject { id, command in LaunchPane(id: id, command: command) }

        #expect(created.name != "alpha")
        let pane = try #require(created.paneTree.firstLeaf)
        #expect(pane.command == Self.attach(created, index: 1))
    }
}
