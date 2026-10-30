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

    /// The stored terminal name a pasted string sets, or `nil` when the string
    /// is not a registered name and the paste must be ignored. Pasting the local
    /// terminal's name stores the default.
    func pastedTerminalName(_ text: String) -> String?? {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let terminal = terminals.first(where: { $0.name == name }) else { return nil }
        return .some(isLocal(terminal) ? nil : terminal.name)
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
