import Foundation

/// Where a pane's shell says it is, as reported by shell integration (OSC 7).
///
/// The terminal core forwards the report as-is: `host` is empty whenever the
/// shell runs on this machine (the only case upstream Ghostty reports at all),
/// and carries the reported hostname when it does not.
struct PaneLocationReport: Equatable {
    /// The host the shell runs on. `nil` or empty means "no host information".
    var host: String?

    /// The reported working directory.
    var path: String?

    init(host: String? = nil, path: String? = nil) {
        self.host = host
        self.path = path
    }
}

/// How the new pane created by splitting an existing pane is started
/// (`SPEC.md` §29).
enum PaneSplitLaunch: Equatable {
    /// Start the pane the way panes have always been started: a local shell in
    /// the inherited working directory.
    case local

    /// Reconnect to `host` over ssh and land in `path` there.
    case ssh(host: String, path: String)

    /// The line the new pane's shell runs to re-establish the session, or `nil`
    /// for a plain local pane.
    ///
    /// This is *typed into a normal local shell* rather than replacing the
    /// pane's command, which is what makes the failure path right: if the host
    /// is unreachable, or ssh is missing, or the remote path is gone, the pane
    /// is still a working local shell in the inherited directory — "opens
    /// locally as before" (必須対応事項 61) with no special-case code.
    ///
    /// The remote side is quoted twice on purpose: once so the *local* shell
    /// passes the script through untouched (which also keeps `${SHELL}`
    /// unexpanded until it reaches the remote), and once around the path so the
    /// *remote* shell sees it whole. `-t` forces a tty so the remote shell is
    /// interactive. User, key and port are deliberately left to the remote
    /// side's ssh configuration (前提事項): only the reported host is used.
    var initialInput: String? {
        switch self {
        case .local:
            return nil

        case let .ssh(host, path):
            let remote = "cd \(XGhostty.Shell.quote(path)) && exec ${SHELL:-/bin/sh} -l"
            return "ssh -t \(XGhostty.Shell.quote(host)) \(XGhostty.Shell.quote(remote))\n"
        }
    }
}

/// What is running in the foreground of a pane's pty right now.
///
/// This is the second half of "is this pane somewhere else": the OSC 7 report
/// says where the pane's shell *was* when it last spoke, and the foreground
/// process says whether it is still speaking from there. A pane that is really
/// ssh'd out has ssh (or whatever launched it) in the foreground; a pane back at
/// its own prompt has its shell there.
enum PaneForegroundProcess: Equatable {
    /// The pane's own shell is the foreground process: nothing is running, so
    /// the pane is sitting at a local prompt on this machine.
    case shell

    /// Some other process is in the foreground - the pane is running something,
    /// which is what an open ssh session looks like from here.
    case other

    /// The foreground process could not be determined. This must not disable
    /// remote split: absent evidence of staleness, the report is trusted.
    case unknown

    /// Executable names that mean "this pane is at its own prompt". Only the
    /// executable's file name matters; a login shell's leading `-` (argv[0]
    /// convention) is tolerated so the same list works on either input.
    private static let shellNames: Set<String> = [
        "sh", "bash", "zsh", "fish", "dash", "ash",
        "ksh", "ksh93", "mksh", "pdksh",
        "csh", "tcsh",
        "nu", "elvish", "xonsh",
    ]

    /// Classify the foreground process from its executable path.
    ///
    /// `nil` or an empty path is `.unknown`, never `.shell`: failing to look a
    /// process up must not be mistaken for evidence that the pane came home.
    static func classify(executablePath: String?) -> PaneForegroundProcess {
        guard let executablePath, !executablePath.isEmpty else { return .unknown }

        var name = (executablePath as NSString).lastPathComponent
        if name.hasPrefix("-") { name.removeFirst() }
        guard !name.isEmpty else { return .unknown }

        return shellNames.contains(name.lowercased()) ? .shell : .other
    }
}

/// A pane's current location report and the rules that keep it honest.
///
/// The report alone is not enough. Shell integration only re-reports a working
/// directory when it changes (`bash` suppresses an unchanged PWD outright), so
/// after `ssh` exits back into a local shell in the same directory no new report
/// ever arrives and the last remote report would live on forever - splitting
/// such a pane would ssh out again although the pane is plainly here. Both rules
/// below exist to prevent exactly that, and both are conservative: the fallback
/// is always the local pane 必須対応事項 61 asks for.
struct PaneLocationTracker: Equatable {
    /// The last report received for the pane, if it is still credible.
    private(set) var report: PaneLocationReport?

    init(report: PaneLocationReport? = nil) {
        self.report = report
    }

    /// Record a fresh OSC 7 report. A report always replaces what came before:
    /// it is the shell speaking for itself.
    mutating func record(_ report: PaneLocationReport) {
        self.report = report
    }

    /// Forget everything about where this pane is. Used where a pane provably
    /// starts over on this machine - the child process exited, or a new shell
    /// was started in a terminated pane.
    mutating func reset() {
        report = nil
    }

    /// A command finished in this pane (shell integration's OSC 133 D).
    ///
    /// If the pane's own shell is in the foreground at that moment, the command
    /// that just ended was running *here*, which is what returning from `ssh`
    /// looks like: the claim of being elsewhere is over, whether or not a new
    /// report follows. If something else is still in the foreground the pane is
    /// still busy - a command ending inside a live ssh session reports through
    /// the same stream, and must not drop the remote report.
    mutating func commandFinished(foreground: PaneForegroundProcess) {
        guard foreground == .shell else { return }
        reset()
    }

    /// How a split of this pane should be launched right now.
    func splitLaunch(foreground: PaneForegroundProcess) -> PaneSplitLaunch {
        RemoteSplit.launch(for: report, foreground: foreground)
    }
}

/// The remote-split decision: everything about "is this pane somewhere else,
/// and how do we get back there" lives here, so it is testable without a
/// terminal (必須対応事項 62).
enum RemoteSplit {
    /// Host names that always mean this machine. The terminal core has already
    /// resolved locality before it reports a host at all, so this is a
    /// second fence rather than the primary one — a report that names the
    /// loopback must never turn into an ssh.
    private static let localHosts: Set<String> = [
        "localhost",
        "localhost.localdomain",
        "127.0.0.1",
        "::1",
    ]

    /// How a split of a pane at `report` should be launched.
    ///
    /// A report is remote only when it names a host that is not this machine
    /// *and* carries an absolute path to land in. Anything else — no report at
    /// all, no host information, a loopback host, a missing or relative path —
    /// is a location we cannot reconnect to, and 必須対応事項 61 makes that
    /// case a plain local pane.
    static func launch(for report: PaneLocationReport?) -> PaneSplitLaunch {
        guard let report else { return .local }

        let host = (report.host ?? "").trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, !localHosts.contains(host.lowercased()) else { return .local }

        let path = report.path ?? ""
        guard path.hasPrefix("/") else { return .local }

        return .ssh(host: host, path: path)
    }

    /// How a split should be launched given both what the pane last reported and
    /// what it is doing now.
    ///
    /// A pane whose own shell is the foreground process is at a prompt on this
    /// machine, so it is local no matter how old and how remote its last report
    /// is. Any other foreground - including one we could not identify - leaves
    /// the report as the only evidence there is, and `launch(for:)` decides.
    static func launch(
        for report: PaneLocationReport?,
        foreground: PaneForegroundProcess
    ) -> PaneSplitLaunch {
        guard foreground != .shell else { return .local }
        return launch(for: report)
    }
}
