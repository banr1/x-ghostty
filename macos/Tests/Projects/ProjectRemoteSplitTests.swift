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

    // MARK: - A report that has gone stale

    @Test func foregroundShellClassification() {
        for path in ["/bin/zsh", "/bin/bash", "/usr/local/bin/fish", "/bin/-zsh", "/BIN/ZSH"] {
            #expect(
                PaneForegroundProcess.classify(executablePath: path) == .shell,
                "\(path) is the pane's own shell")
        }

        for path in ["/usr/bin/ssh", "/usr/bin/vim", "/opt/homebrew/bin/mosh-client"] {
            #expect(
                PaneForegroundProcess.classify(executablePath: path) == .other,
                "\(path) is something the pane is running")
        }

        // A failed lookup must never read as "the pane is at its own prompt".
        #expect(PaneForegroundProcess.classify(executablePath: nil) == .unknown)
        #expect(PaneForegroundProcess.classify(executablePath: "") == .unknown)
    }

    @Test func paneSittingAtItsOwnShellSplitsLocallyDespiteARemoteReport() {
        // The defect this fences: the shell integration only re-reports a
        // changed PWD, so returning from ssh into the same local directory
        // leaves the remote report standing. The pane is plainly here - its own
        // shell is in the foreground - so the split is local (成功条件 19).
        let report = PaneLocationReport(host: "workbench", path: "/srv/app")
        #expect(RemoteSplit.launch(for: report, foreground: .shell) == .local)
        #expect(RemoteSplit.launch(for: report, foreground: .other) == .ssh(host: "workbench", path: "/srv/app"))
        #expect(RemoteSplit.launch(for: report, foreground: .unknown) == .ssh(host: "workbench", path: "/srv/app"))
    }

    @Test func reportSurvivesACommandThatEndedInsideALiveRemoteSession() {
        // A remote shell's own command marks travel the same stream. While the
        // session process is still in the foreground, they say nothing about
        // this pane's location and must not drop the remote report.
        var tracker = PaneLocationTracker()
        tracker.record(PaneLocationReport(host: "workbench", path: "/srv/app"))

        tracker.commandFinished(foreground: .other)
        #expect(tracker.report == PaneLocationReport(host: "workbench", path: "/srv/app"))
        #expect(tracker.splitLaunch(foreground: .other) == .ssh(host: "workbench", path: "/srv/app"))

        tracker.commandFinished(foreground: .unknown)
        #expect(tracker.report == PaneLocationReport(host: "workbench", path: "/srv/app"))
    }

    @Test func remoteReportIsDroppedWhenACommandEndsBackAtTheLocalShell() {
        var tracker = PaneLocationTracker()
        tracker.record(PaneLocationReport(host: "workbench", path: "/srv/app"))

        // ssh exits: the command ends with the pane's own shell in front of it.
        tracker.commandFinished(foreground: .shell)
        #expect(tracker.report == nil)

        // And it stays local even once the pane is busy again with no new
        // report - the stale claim is gone for good, not just fenced.
        #expect(tracker.splitLaunch(foreground: .other) == .local)
    }

    @Test func aFreshReportRevivesTheRemoteDecision() {
        var tracker = PaneLocationTracker()
        tracker.record(PaneLocationReport(host: "workbench", path: "/srv/app"))
        tracker.commandFinished(foreground: .shell)

        // Going out again reports again, and the pane is remote once more.
        tracker.record(PaneLocationReport(host: "workbench", path: "/srv/other"))
        #expect(tracker.splitLaunch(foreground: .other) == .ssh(host: "workbench", path: "/srv/other"))
    }

    @Test func resetForgetsWhereThePaneWas() {
        // The child exited (and an Enter may start a new shell in the pane):
        // whatever runs next runs here.
        var tracker = PaneLocationTracker()
        tracker.record(PaneLocationReport(host: "workbench", path: "/srv/app"))
        tracker.reset()

        #expect(tracker.report == nil)
        #expect(tracker.splitLaunch(foreground: .other) == .local)
    }

    @Test func aLocalReportIsUnaffectedByTheFence() {
        var tracker = PaneLocationTracker()
        tracker.record(PaneLocationReport(host: "", path: "/Users/banri/src"))

        #expect(tracker.splitLaunch(foreground: .shell) == .local)
        #expect(tracker.splitLaunch(foreground: .other) == .local)
    }
}
