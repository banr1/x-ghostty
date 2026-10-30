import Foundation
import Testing
@testable import XGhostty

/// Tests for the terminal registry and the tmux commands each pane runs on its
/// project's terminal (IDEAL C127, C129〜C131, C134, C136).
struct ProjectTerminalTests {
    private let mini = "mini,mac-mini.local,colour33"
    private let loop = "loop,mini-loopback,#ff8800"

    // MARK: - Registry

    @Test func registrationsAreReadInOrder() {
        let registry = ProjectTerminalRegistry(registrations: [mini, loop], hostname: "Mac-Mini.local")
        #expect(registry.terminals == [
            ProjectTerminal(name: "mini", host: "mac-mini.local", color: "colour33"),
            ProjectTerminal(name: "loop", host: "mini-loopback", color: "#ff8800"),
        ])
        #expect(registry.candidateNames == ["mini", "loop"])
    }

    @Test func configLinesSplitIntoRegistrations() {
        // The config hands `project-terminal` over as one value per line.
        let lines = "\(mini)\n\n  \n\(loop)"
        let registrations = ProjectTerminalRegistry.registrations(fromConfigLines: lines)
        #expect(registrations == [mini, loop])
        let registry = ProjectTerminalRegistry(registrations: registrations, hostname: "mac-mini")
        #expect(registry.candidateNames == ["mini", "loop"])
        #expect(registry.local.name == "mini")
        #expect(ProjectTerminalRegistry.registrations(fromConfigLines: "").isEmpty)
    }

    @Test func reloadedRegistrationsReplaceTheRegistry() {
        // A reload builds a new registry from the new registrations: an added
        // terminal becomes a candidate, and a project stored on a removed one
        // runs locally until it is registered again.
        let before = ProjectTerminalRegistry(registrations: [mini], hostname: "mac-mini")
        let after = ProjectTerminalRegistry(registrations: [mini, loop], hostname: "mac-mini")
        #expect(before != after)
        #expect(before.terminal(named: "loop") == before.local)
        #expect(after.terminal(named: "loop").name == "loop")
        let removed = ProjectTerminalRegistry(registrations: [], hostname: "mac-mini")
        #expect(removed.terminal(named: "loop") == removed.local)
    }

    @Test func onlyTheTerminalMatchingTheHostnameIsLocal() {
        let registry = ProjectTerminalRegistry(registrations: [mini, loop], hostname: "MAC-MINI")
        #expect(registry.local.name == "mini")
        #expect(registry.isLocal(registry.terminal(named: "mini")))
        #expect(!registry.isLocal(registry.terminal(named: "loop")))
    }

    @Test func hostnameMatchIgnoresDotLocalAndCase() {
        #expect(ProjectTerminalRegistry.hostsMatch("Mac-Mini.local", "mac-mini"))
        #expect(ProjectTerminalRegistry.hostsMatch("mac-mini", "MAC-MINI.LOCAL"))
        #expect(!ProjectTerminalRegistry.hostsMatch("mac-mini", "mac-mini-2"))
        #expect(!ProjectTerminalRegistry.hostsMatch("", ""))
    }

    @Test func withoutRegistrationsOnlyAnImplicitLocalTerminalExists() {
        let registry = ProjectTerminalRegistry(registrations: [], hostname: "Banri-Air.local")
        #expect(registry.terminals.count == 1)
        #expect(registry.local.name == "banri-air")
        #expect(registry.local.color == nil)
        #expect(registry.isLocal(registry.terminal(named: nil)))
    }

    @Test func malformedAndDuplicateRegistrationsAreDropped() {
        let registry = ProjectTerminalRegistry(
            registrations: ["", "nohost", ",host", "name,", "a,b,c,d", mini, "mini,other,red"],
            hostname: "mac-mini")
        #expect(registry.terminals == [ProjectTerminal(name: "mini", host: "mac-mini.local", color: "colour33")])
    }

    @Test func colorIsOptionalAndFieldsAreTrimmed() {
        #expect(ProjectTerminal(registration: " air , banri-air ") == ProjectTerminal(name: "air", host: "banri-air"))
        #expect(ProjectTerminal(registration: "air,banri-air,") == ProjectTerminal(name: "air", host: "banri-air"))
    }

    @Test func aProjectWithoutATerminalOrAnUnregisteredOneRunsLocally() {
        let registry = ProjectTerminalRegistry(registrations: [mini, loop], hostname: "mac-mini")
        #expect(registry.terminal(named: nil) == registry.local)
        #expect(registry.terminal(named: "gone") == registry.local)
        #expect(registry.terminal(named: "loop").name == "loop")
    }

    @Test func pastingAcceptsOnlyRegisteredNames() {
        let registry = ProjectTerminalRegistry(registrations: [mini, loop], hostname: "mac-mini")
        #expect(registry.pastedTerminalName("loop") == .some("loop"))
        #expect(registry.pastedTerminalName(" loop\n") == .some("loop"))
        #expect(registry.pastedTerminalName("mini") == .some(nil))
        #expect(registry.pastedTerminalName("elsewhere") == nil)
        #expect(registry.pastedTerminalName("") == nil)
    }

    // MARK: - Session names

    @Test func sessionNamesAreProjectIDAndPaneIndex() throws {
        let id = ProjectID(rawValue: try #require(UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")))
        #expect(TmuxSession.name(project: id, index: 1) == "6f9619ff-8b86-d011-b42d-00c04fc964ff-1")
        #expect(TmuxSession.name(project: id, index: 2) != TmuxSession.name(project: id, index: 1))
        #expect(TmuxSession.name(project: ProjectID(), index: 1) != TmuxSession.name(project: id, index: 1))
    }

    @Test func paneIndicesAreNeverReused() {
        #expect(TmuxSession.nextIndex(after: []) == 1)
        #expect(TmuxSession.nextIndex(after: [1, 2]) == 3)
        #expect(TmuxSession.nextIndex(after: [3]) == 4)
    }

    // MARK: - Attach command

    private let local = ProjectTerminal(name: "mini", host: "mac-mini", color: "colour33")
    private let remote = ProjectTerminal(name: "loop", host: "mini-loopback", color: "#ff8800")

    @Test func localPanesRunTmuxDirectlyInsideSh() {
        let command = TmuxSession.attachCommand(
            session: "p-1", title: "x-ghostty", start: .project, terminal: local, isLocal: true)
        #expect(command.hasPrefix("/bin/sh -c '"))
        #expect(command.contains("exec tmux new-session -A -s p-1 -c \"$d\""))
        #expect(!command.contains("ssh"))
        #expect(!command.contains("TERM="))
    }

    @Test func remotePanesWrapTheSameScriptInSshWithTerm() {
        let localCommand = TmuxSession.attachCommand(
            session: "p-1", title: "x-ghostty", start: .project, terminal: remote, isLocal: true)
        let command = TmuxSession.attachCommand(
            session: "p-1", title: "x-ghostty", start: .project, terminal: remote, isLocal: false)
        #expect(command.hasPrefix("env TERM=xterm-256color ssh -t mini-loopback "))
        #expect(command == "env TERM=xterm-256color ssh -t mini-loopback "
            + XGhostty.Shell.quote(localCommand))
    }

    @Test func hostTitleAndSessionAreQuoted() {
        let terminal = ProjectTerminal(name: "odd", host: "host with space", color: "red")
        let command = TmuxSession.attachCommand(
            session: "p-1", title: "it's mine; rm -rf ~", start: .project, terminal: terminal, isLocal: false)
        #expect(command.contains("ssh -t 'host with space' "))
        #expect(!command.contains("; rm -rf ~;"))

        let script = TmuxSession.attachCommand(
            session: "p-1", title: "it's mine; rm -rf ~", start: .project, terminal: terminal, isLocal: true)
        #expect(script.contains(XGhostty.Shell.quote("it's mine; rm -rf ~")
            .replacingOccurrences(of: "'", with: #"'"'"'"#)))
    }

    @Test func projectStartDirectoryFallsBackFromTheTitleToWorkspaceToHome() {
        let command = TmuxSession.attachCommand(
            session: "p-1", title: "x-ghostty", start: .project, terminal: local, isLocal: true)
        let title = command.range(of: "d=\"$HOME/workspace/\"x-ghostty")
        let workspace = command.range(of: "d=\"$HOME/workspace\";")
        let home = command.range(of: "d=\"$HOME\";")
        #expect(title != nil && workspace != nil && home != nil)
        if let title, let workspace, let home {
            #expect(title.lowerBound < workspace.lowerBound)
            #expect(workspace.lowerBound < home.lowerBound)
        }
        #expect(!command.contains("pane_current_path"))
    }

    @Test func splitsInheritTheOriginSessionsCurrentPath() {
        let command = TmuxSession.attachCommand(
            session: "p-2", title: "x-ghostty", start: .inherit(fromSession: "p-1"), terminal: local, isLocal: true)
        #expect(command.contains("tmux display-message -p -t =p-1: "))
        #expect(command.contains("#{pane_current_path}"))
        let inherit = command.range(of: "pane_current_path")
        let fallback = command.range(of: "$HOME/workspace/")
        #expect(inherit != nil && fallback != nil)
        if let inherit, let fallback { #expect(inherit.lowerBound < fallback.lowerBound) }
    }

    // MARK: - Session options

    @Test func sessionOptionsTargetOnlyThatSession() {
        let commands = TmuxSession.optionCommands(session: "p-1", title: "x-ghostty", color: "colour33")
        #expect(commands.contains("set-option -t =p-1: status-style bg=colour33"))
        #expect(commands.contains("set-option -t =p-1: status-left '[x-ghostty] '"))
        #expect(commands.contains("set-option -t =p-1: prefix C-s"))
        for command in commands {
            #expect(command.hasPrefix("set-option -t =p-1: "))
            #expect(!command.split(separator: " ").contains("-g"))
        }
    }

    @Test func theDefaultColourLeavesStatusStyleAlone() {
        let commands = TmuxSession.optionCommands(session: "p-1", title: "t", color: nil)
        #expect(!commands.contains { $0.contains("status-style") })
        #expect(commands.contains("set-option -t =p-1: prefix C-s"))
    }

    @Test func theAttachCommandSetsTheOptionsAfterCreatingOrAttaching() {
        let command = TmuxSession.attachCommand(
            session: "p-1", title: "x-ghostty", start: .project, terminal: local, isLocal: true)
        let attach = command.range(of: "new-session -A")
        let option = command.range(of: "set-option -t =p-1: prefix C-s")
        #expect(attach != nil && option != nil)
        if let attach, let option { #expect(attach.lowerBound < option.lowerBound) }
    }

    @Test func hashesInTitlesAreShownLiterally() {
        #expect(TmuxSession.statusLeft(title: "issue #12") == "[issue ##12] ")
    }

    // MARK: - Retitle and kill

    @Test func retitleSetsOnlyStatusLeftOnThatSession() {
        let argv = TmuxSession.retitleArguments(session: "p-1", title: "new", terminal: local, isLocal: true)
        #expect(argv.prefix(2) == ["/bin/sh", "-c"])
        #expect(argv.last?.contains("tmux set-option -t =p-1: status-left '[new] '") == true)
        #expect(argv.last?.split(separator: " ").contains("-g") == false)
    }

    @Test func killReachesRemoteTerminalsOverBatchSsh() {
        let argv = TmuxSession.killArguments(sessions: ["p-1", "p-2"], terminal: remote, isLocal: false)
        #expect(argv.prefix(4) == ["/usr/bin/ssh", "-o", "BatchMode=yes", "mini-loopback"])
        #expect(argv.last?.contains("tmux kill-session -t =p-1") == true)
        #expect(argv.last?.contains("tmux kill-session -t =p-2") == true)
    }
}
