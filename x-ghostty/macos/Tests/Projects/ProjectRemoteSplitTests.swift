import Foundation
import Testing
@testable import XGhostty

/// Tests for the remote-split decision (SPEC §29): reading a pane's OSC 7
/// working-directory report and deciding whether the new pane of a split starts
/// here or reconnects to the reporting host — 成功条件 18.
struct ProjectRemoteSplitTests {
    // MARK: - The three success-criterion cases

    @Test func localReportLaunchesLocally() {
        let report = PaneLocationReport(host: "", path: "/Users/banri/src/x-ghostty")
        #expect(RemoteSplit.launch(for: report) == .local)
        #expect(RemoteSplit.launch(for: report).initialInput == nil)
    }

    @Test func remoteReportLaunchesSshToThatHostAndPath() throws {
        let report = PaneLocationReport(host: "workbench", path: "/srv/app")
        let launch = RemoteSplit.launch(for: report)
        #expect(launch == .ssh(host: "workbench", path: "/srv/app"))

        let input = try #require(launch.initialInput)
        #expect(input == "ssh -t workbench 'cd /srv/app && exec ${SHELL:-/bin/sh} -l'\n")
    }

    @Test func reportWithoutHostInformationIsLocal() {
        #expect(RemoteSplit.launch(for: PaneLocationReport(host: nil, path: "/srv/app")) == .local)
        #expect(RemoteSplit.launch(for: nil) == .local)
    }

    // MARK: - Reports we cannot reconnect to

    @Test func loopbackHostsAreLocal() {
        for host in ["localhost", "LocalHost", "127.0.0.1", "::1", "localhost.localdomain"] {
            #expect(
                RemoteSplit.launch(for: PaneLocationReport(host: host, path: "/srv/app")) == .local,
                "\(host) names this machine")
        }
    }

    @Test func remoteHostWithoutAnAbsolutePathIsLocal() {
        // Nothing to `cd` to: 必須対応事項 61 makes an undeterminable location a
        // plain local pane rather than a half-applied reconnect.
        #expect(RemoteSplit.launch(for: PaneLocationReport(host: "workbench", path: nil)) == .local)
        #expect(RemoteSplit.launch(for: PaneLocationReport(host: "workbench", path: "")) == .local)
        #expect(RemoteSplit.launch(for: PaneLocationReport(host: "workbench", path: "src")) == .local)
    }

    @Test func blankHostIsLocal() {
        #expect(RemoteSplit.launch(for: PaneLocationReport(host: "   ", path: "/srv/app")) == .local)
    }

    // MARK: - The reconnect command

    @Test func pathsAndHostsAreQuotedForBothShells() throws {
        let launch = RemoteSplit.launch(
            for: PaneLocationReport(host: "work bench", path: "/srv/it's here/app dir"))
        let input = try #require(launch.initialInput)

        // Verified against a real /bin/sh: the local shell hands ssh exactly
        // ["-t", "work bench", <the whole remote script>], and the remote shell
        // parses "/srv/it's here/app dir" back out of that script intact.
        let expected = #"ssh -t 'work bench' 'cd '"'"'/srv/it'"'"'"'"'"'"'"'"'s here/app dir'"'"' && exec ${SHELL:-/bin/sh} -l'"#
        #expect(input == expected + "\n")
    }

    @Test func reconnectRunsInTheNewPanesShellSoFailureLeavesALocalShell() throws {
        // The reconnect is typed into an ordinary local shell rather than
        // replacing the pane's command: that is what makes a failed connection
        // fall back to a working local pane (必須対応事項 61).
        let input = try #require(
            RemoteSplit.launch(for: PaneLocationReport(host: "workbench", path: "/srv/app"))
                .initialInput)
        #expect(input.hasSuffix("\n"))
        #expect(input.hasPrefix("ssh -t "))
    }
}
