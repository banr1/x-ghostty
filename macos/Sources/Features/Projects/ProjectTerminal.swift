import Foundation

/// A machine registered in the config as a place where a project's panes run.
///
/// Every pane of a project opens inside a tmux session on the project's
/// terminal. The local terminal is reached directly; any other terminal is
/// reached with `ssh -t <host>`, leaving user, key and port to the ssh config of
/// the machine xghostty runs on.
struct ProjectTerminal: Equatable, Hashable {
    /// The name shown in the project list's terminal column. Unique in a registry.
    let name: String

    /// The host name handed to ssh, and the name compared against this
    /// machine's hostname to find the local terminal.
    let host: String

    /// The tmux colour of the session's status bar, or `nil` for tmux's default.
    let color: String?

    init(name: String, host: String, color: String? = nil) {
        self.name = name
        self.host = host
        self.color = color
    }

    /// Parses one registration of the form `<name>,<host>[,<color>]`.
    ///
    /// Surrounding whitespace of each field is ignored. A registration without
    /// a name or a host is not a terminal and yields `nil`.
    init?(registration: String) {
        let fields = registration
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard fields.count == 2 || fields.count == 3 else { return nil }
        guard !fields[0].isEmpty, !fields[1].isEmpty else { return nil }
        let color = fields.count == 3 && !fields[2].isEmpty ? fields[2] : nil
        self.init(name: fields[0], host: fields[1], color: color)
    }
}

/// The registered terminals and which of them is this machine.
struct ProjectTerminalRegistry: Equatable {
    /// All terminals, in registration order. Always contains `local`.
    let terminals: [ProjectTerminal]

    /// The terminal that is this machine: panes on it start tmux without ssh.
    let local: ProjectTerminal

    /// Builds the registry from the config's registrations and this machine's
    /// hostname.
    ///
    /// Unparsable registrations and repeated names are dropped (the first one
    /// wins). The first terminal whose host matches `hostname` is the local
    /// one. When none matches — in particular when nothing is registered — an
    /// implicit local terminal named after the hostname, with the default
    /// colour, is appended so a local terminal always exists.
    init(registrations: [String], hostname: String) {
        var terminals: [ProjectTerminal] = []
        for registration in registrations {
            guard let terminal = ProjectTerminal(registration: registration) else { continue }
            guard !terminals.contains(where: { $0.name == terminal.name }) else { continue }
            terminals.append(terminal)
        }

        if let local = terminals.first(where: { Self.hostsMatch($0.host, hostname) }) {
            self.local = local
        } else {
            let name = Self.normalizedHost(hostname)
            let local = ProjectTerminal(name: name.isEmpty ? "local" : name, host: hostname)
            terminals.append(local)
            self.local = local
        }
        self.terminals = terminals
    }

    /// Whether two host names name the same machine: a trailing `.local` and
    /// letter case are ignored.
    static func hostsMatch(_ lhs: String, _ rhs: String) -> Bool {
        let lhs = normalizedHost(lhs)
        return !lhs.isEmpty && lhs == normalizedHost(rhs)
    }

    private static func normalizedHost(_ host: String) -> String {
        var host = host.lowercased()
        if host.hasSuffix(".") { host.removeLast() }
        if host.hasSuffix(".local") { host.removeLast(".local".count) }
        return host
    }

    func isLocal(_ terminal: ProjectTerminal) -> Bool {
        terminal == local
    }

    /// The terminal a project with the stored terminal name runs on.
    ///
    /// `nil` is the default (local). A name that is no longer registered is
    /// also treated as local; the stored name itself is kept by the caller so
    /// re-registering the terminal brings the project back to it.
    func terminal(named name: String?) -> ProjectTerminal {
        guard let name else { return local }
        return terminals.first { $0.name == name } ?? local
    }

    /// The values offered by the project list's terminal column.
    var candidateNames: [String] {
        terminals.map(\.name)
    }

    /// The registered terminal with exactly the display name `name`, or `nil`.
    /// Unlike `terminal(named:)` there is no local fallback: this is the
    /// lookup for input that must name a registered terminal.
    func registeredTerminal(named name: String) -> ProjectTerminal? {
        terminals.first { $0.name == name }
    }

    /// What a project stores when `terminal` is chosen for it: `nil` for the
    /// local terminal (the default), the display name otherwise.
    func storedName(for terminal: ProjectTerminal) -> String? {
        isLocal(terminal) ? nil : terminal.name
    }

    /// The stored terminal name a pasted string sets, or `nil` when the string
    /// is not a registered name and the paste must be ignored. Pasting the local
    /// terminal's name stores the default.
    func pastedTerminalName(_ text: String) -> String?? {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let terminal = registeredTerminal(named: name) else { return nil }
        return .some(storedName(for: terminal))
    }

    /// The registry new and restored panes resolve their terminals against
    /// when no workspace is at hand (a restore decodes surfaces before the
    /// workspace model exists). Until the config registers terminals, only
    /// the implicit local terminal exists.
    static var shared = ProjectTerminalRegistry(registrations: [], hostname: machineHostname)

    /// This machine's hostname as the kernel reports it (`gethostname`), the
    /// name a registered host is compared against. Read without a DNS lookup.
    static var machineHostname: String {
        var buffer = [CChar](repeating: 0, count: 256)
        guard gethostname(&buffer, buffer.count) == 0 else { return "" }
        return String(cString: buffer)
    }
}

/// Which tmux session one pane lives in: the terminal it was started on and
/// its pane index within the project (the session is `<project id>-<index>`).
///
/// Fixed when the pane is first started. Changing the project's terminal
/// afterwards only affects panes started later, so an open pane keeps
/// re-attaching to the terminal it was started on.
struct TmuxPaneBinding: Codable, Equatable, Hashable {
    /// The stored terminal name (`nil` for the local terminal), resolved
    /// through `ProjectTerminalRegistry.terminal(named:)` like a project's.
    let terminalName: String?

    /// The pane index, unique within the project and never reused.
    let index: Int

    func sessionName(project: ProjectID) -> String {
        TmuxSession.name(project: project, index: index)
    }
}

/// A pane closed by `Cmd+W`, `close_project` or the list's row `Delete`, whose
/// session is killed when the undo period expires unless the pane came back.
struct TmuxClosedPane: Equatable, Hashable {
    let project: ProjectID
    let pane: SurfaceID
    let binding: TmuxPaneBinding

    var sessionName: String {
        binding.sessionName(project: project)
    }
}

/// An open pane whose session's `status-left` is to show `title` after its
/// project was renamed (must 131).
struct TmuxRetitle: Equatable {
    let pane: TmuxClosedPane
    let title: String
}

/// The bound panes open across a workspace (must 133). Comparing two states
/// finds the panes a change closed, whichever path closed them — `Cmd+W`,
/// `close_project`, the list's row `Delete`, a redo — and, once their undo
/// period expires, which of their sessions still have to be killed.
struct TmuxOpenPanes: Equatable {
    private(set) var panes: [SurfaceID: TmuxClosedPane] = [:]

    /// The title of each project, as its sessions' `status-left` shows it.
    private(set) var titles: [ProjectID: String] = [:]

    init() {}

    init<Pane>(projects: some Sequence<ProjectStateOf<Pane>>)
    where Pane: Codable & Identifiable & Equatable, Pane.ID == UUID {
        for project in projects {
            titles[project.id] = project.name
            for pane in project.tmuxPanesInTree {
                panes[pane.pane] = pane
            }
        }
    }

    /// The sessions whose `status-left` a rename made stale when moving to
    /// `next` (must 131): each pane open in both whose project's title
    /// changed, with the new title. A pane first opened in `next` attached
    /// with the new title already.
    func retitles(to next: TmuxOpenPanes) -> [TmuxRetitle] {
        next.panes.values
            .sorted { $0.sessionName < $1.sessionName }
            .compactMap { pane in
                guard panes[pane.pane] != nil,
                      let old = titles[pane.project],
                      let new = next.titles[pane.project],
                      old != new else { return nil }
                return TmuxRetitle(pane: pane, title: new)
            }
    }

    /// Moves to `next`, returning the panes open here but not in `next`.
    mutating func advance(to next: TmuxOpenPanes) -> [TmuxClosedPane] {
        let closed = panes.values
            .filter { next.panes[$0.pane] == nil }
            .sorted { $0.sessionName < $1.sessionName }
        self = next
        return closed
    }

    /// The sessions of `closed` to kill now that their undo period expired,
    /// grouped by terminal. A pane open again (brought back by undo) keeps
    /// its session, and so does any session an open pane attaches to: a
    /// restarted terminated pane takes over the dead pane's session.
    func killTargets(
        closed: some Sequence<TmuxClosedPane>,
        registry: ProjectTerminalRegistry
    ) -> [ProjectTerminal: Set<String>] {
        var targets = TmuxSession.killTargets(
            closed: closed, open: Set(panes.keys), registry: registry)
        for pane in panes.values {
            let terminal = registry.terminal(named: pane.binding.terminalName)
            targets[terminal]?.remove(pane.sessionName)
            if targets[terminal]?.isEmpty == true {
                targets[terminal] = nil
            }
        }
        return targets
    }
}

/// The tmux side of restoring a project's panes (must 129).
///
/// A restored surface is created while its project's pane tree is decoded,
/// and its command must be known at that moment. The project's decode runs
/// the tree decode inside `decoding`, and each surface asks `command(for:)`:
/// a saved pane re-attaches to its session on its terminal, and a pane with
/// no saved session (a save from before tmux sessions) is bound to the
/// project's terminal and the next unused index. The bindings handed out are
/// returned to the project. The context is task-local: it is seen only by
/// the decode that installed it, never by a concurrent one.
enum TmuxPaneRestore {
    /// Mutated only by the synchronous decode of the task that installed it.
    private final class Context: @unchecked Sendable {
        let project: ProjectID
        let title: String
        let terminalName: String?
        let registry: ProjectTerminalRegistry
        var bindings: [SurfaceID: TmuxPaneBinding]
        var lastIndex: Int

        init(
            project: ProjectID,
            title: String,
            terminalName: String?,
            registry: ProjectTerminalRegistry,
            bindings: [SurfaceID: TmuxPaneBinding],
            lastIndex: Int
        ) {
            self.project = project
            self.title = title
            self.terminalName = terminalName
            self.registry = registry
            self.bindings = bindings
            self.lastIndex = lastIndex
        }
    }

    @TaskLocal private static var current: Context?

    /// Runs `decodeTree` with the project's saved sessions available to the
    /// surfaces it creates, and returns its result together with the
    /// bindings after the decode — the saved ones plus any handed out — and
    /// the highest index.
    static func decoding<T>(
        project: ProjectID,
        title: String,
        terminalName: String?,
        bindings: [SurfaceID: TmuxPaneBinding],
        lastIndex: Int,
        registry: ProjectTerminalRegistry = .shared,
        _ decodeTree: () throws -> T
    ) rethrows -> (T, [SurfaceID: TmuxPaneBinding], Int) {
        let context = Context(
            project: project,
            title: title,
            terminalName: terminalName,
            registry: registry,
            bindings: bindings,
            lastIndex: lastIndex)
        let tree = try $current.withValue(context) { try decodeTree() }
        return (tree, context.bindings, context.lastIndex)
    }

    /// The command a surface being restored with id `pane` starts with, or
    /// `nil` outside a project's decode (the surface then keeps its default
    /// command). An existing session is re-attached as is; tmux ignores the
    /// start directory then.
    static func command(for pane: UUID) -> String? {
        guard let context = current else { return nil }
        let id = SurfaceID(rawValue: pane)
        let binding: TmuxPaneBinding
        if let saved = context.bindings[id] {
            binding = saved
        } else {
            let index = TmuxSession.nextIndex(
                after: context.bindings.values.map(\.index) + [context.lastIndex])
            binding = TmuxPaneBinding(terminalName: context.terminalName, index: index)
            context.bindings[id] = binding
            context.lastIndex = index
        }
        let terminal = context.registry.terminal(named: binding.terminalName)
        return TmuxSession.attachCommand(
            session: binding.sessionName(project: context.project),
            title: context.title,
            start: .project,
            terminal: terminal,
            isLocal: context.registry.isLocal(terminal))
    }
}

/// Where a new tmux session starts.
enum TmuxStartDirectory: Equatable {
    /// `~/workspace/<title>` if it exists on the terminal, else `~/workspace`,
    /// else the home directory.
    case project

    /// The current path of the given session's active pane (a split inherits
    /// it from the pane it splits), falling back to the `project` rule when
    /// that session cannot be asked.
    case inherit(fromSession: String)
}

/// The tmux side of a pane: the session it lives in and the commands that
/// attach to, retitle and kill that session on the pane's terminal.
enum TmuxSession {
    /// The `TERM` handed to ssh: the remote side may lack xghostty's terminfo.
    static let remoteTerm = "xterm-256color"

    /// tmux's default `status-left-length` (10) would cut most titles.
    static let statusLeftLength = 100

    /// Where tmux is looked for on the terminal, ahead of the inherited `PATH`.
    /// A pane command and a non-interactive ssh command do not read the login
    /// profile that usually puts Homebrew on the `PATH`.
    private static let pathPrefix = "PATH=/opt/homebrew/bin:/usr/local/bin:$PATH"

    /// The session name of a project's `index`-th pane: `<project id>-<index>`.
    /// It depends on neither the title nor the terminal, so renaming a project
    /// or changing its terminal never renames a session.
    static func name(project: ProjectID, index: Int) -> String {
        "\(project.rawValue.uuidString.lowercased())-\(index)"
    }

    /// The pane index for a new pane given the indices already used in the
    /// project. Indices are never reused while the project lives, so a pane
    /// closed during its undo period cannot collide with its successor.
    static func nextIndex(after used: some Sequence<Int>) -> Int {
        (used.max() ?? 0) + 1
    }

    /// The pane command: attach to `session` on `terminal`, creating it in
    /// `start` when it does not exist, and set the session's own options.
    ///
    /// This replaces the pane's command (it is not typed into a local shell),
    /// so when tmux or ssh exits — detach, session end, ssh failure — the pane
    /// becomes terminated with the output left visible, and re-running the same
    /// command re-attaches or creates the session again.
    static func attachCommand(
        session: String,
        title: String,
        start: TmuxStartDirectory,
        terminal: ProjectTerminal,
        isLocal: Bool
    ) -> String {
        let script = [
            pathPrefix,
            startDirectoryScript(start, title: title),
            "exec tmux new-session -A -s \(quote(session)) -c \"$d\" "
                + optionCommands(session: session, title: title, color: terminal.color)
                .map { "';' " + $0 }
                .joined(separator: " "),
        ].joined(separator: "; ")

        if isLocal {
            return "/bin/sh -c \(quote(script))"
        }
        return "env TERM=\(remoteTerm) ssh -t \(quote(terminal.host)) \(quote("/bin/sh -c \(quote(script))"))"
    }

    /// The tmux `set-option` commands (without the leading `tmux`) that dress
    /// one session: status bar colour, title and prefix. Each targets the
    /// session itself; none is global (`-g`), so the terminal's `~/.tmux.conf`,
    /// server options and other sessions are left alone.
    static func optionCommands(session: String, title: String, color: String?) -> [String] {
        let target = quote(sessionOptionTarget(session))
        var commands: [String] = []
        if let color {
            commands.append("set-option -t \(target) status-style \(quote("bg=\(color)"))")
        }
        commands.append("set-option -t \(target) status-left-length \(statusLeftLength)")
        commands.append("set-option -t \(target) status-left \(quote(statusLeft(title: title)))")
        commands.append("set-option -t \(target) prefix C-s")
        return commands
    }

    /// The argv that updates an open session's title after a rename.
    static func retitleArguments(
        session: String,
        title: String,
        terminal: ProjectTerminal,
        isLocal: Bool
    ) -> [String] {
        let script = "\(pathPrefix); tmux set-option -t \(quote(sessionOptionTarget(session))) status-left \(quote(statusLeft(title: title)))"
        return arguments(script: script, terminal: terminal, isLocal: isLocal)
    }

    /// The argv that kills the given sessions on one terminal.
    static func killArguments(
        sessions: [String],
        terminal: ProjectTerminal,
        isLocal: Bool
    ) -> [String] {
        let kills = sessions.map { "tmux kill-session -t \(quote("=\($0)")) 2>/dev/null" }
        let script = ([pathPrefix] + kills + ["true"]).joined(separator: "; ")
        return arguments(script: script, terminal: terminal, isLocal: isLocal)
    }

    /// The sessions to kill once the undo period of `closed` expires, grouped
    /// by the terminal they live on.
    ///
    /// A pane in `open` — brought back by undo — keeps its session. Each
    /// stored terminal name resolves through `registry` like a project's, so a
    /// pane whose terminal was unregistered is killed on the local terminal,
    /// where it was attached. A terminal with nothing to kill is absent.
    static func killTargets(
        closed: some Sequence<TmuxClosedPane>,
        open: Set<SurfaceID>,
        registry: ProjectTerminalRegistry
    ) -> [ProjectTerminal: Set<String>] {
        var targets: [ProjectTerminal: Set<String>] = [:]
        for pane in closed where !open.contains(pane.pane) {
            let terminal = registry.terminal(named: pane.binding.terminalName)
            targets[terminal, default: []].insert(pane.sessionName)
        }
        return targets
    }

    /// The text tmux shows as `status-left`. `#` starts a tmux format, so it
    /// is doubled to show a literal `#`.
    static func statusLeft(title: String) -> String {
        "[\(title.replacingOccurrences(of: "#", with: "##"))] "
    }

    /// The `-t` of `set-option` for one session's options. `set-option` takes
    /// a pane target, so the exact session name (`=`) needs the trailing `:`
    /// to resolve; `=<name>` alone is "no such session".
    private static func sessionOptionTarget(_ session: String) -> String {
        "=\(session):"
    }

    /// Picks the start directory into `$d` on the terminal's own shell.
    private static func startDirectoryScript(_ start: TmuxStartDirectory, title: String) -> String {
        var steps: [String] = []
        switch start {
        case .project:
            steps.append("d=")
        case .inherit(let origin):
            steps.append(
                "d=$(tmux display-message -p -t \(quote("=\(origin):")) '#{pane_current_path}' 2>/dev/null)")
        }
        steps.append("[ -n \"$d\" ] && [ -d \"$d\" ] || d=\"$HOME/workspace/\"\(quote(title))")
        steps.append("[ -d \"$d\" ] || d=\"$HOME/workspace\"")
        steps.append("[ -d \"$d\" ] || d=\"$HOME\"")
        return steps.joined(separator: "; ")
    }

    /// Runs a script in `/bin/sh` on the terminal: directly when local, over a
    /// non-interactive ssh otherwise (`BatchMode` so an unreachable or
    /// password-only host fails instead of prompting nobody).
    private static func arguments(script: String, terminal: ProjectTerminal, isLocal: Bool) -> [String] {
        if isLocal {
            return ["/bin/sh", "-c", script]
        }
        return ["/usr/bin/ssh", "-o", "BatchMode=yes", terminal.host, "/bin/sh -c \(quote(script))"]
    }

    private static func quote(_ string: String) -> String {
        XGhostty.Shell.quote(string)
    }
}
