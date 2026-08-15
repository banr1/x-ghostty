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
}
