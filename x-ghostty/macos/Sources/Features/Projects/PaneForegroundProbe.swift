import Darwin
import Foundation
import XGhosttyKit

/// Looks up what a pane's pty is running in the foreground right now.
///
/// This is the thin I/O half of `PaneForegroundProcess`: it asks the terminal
/// core for the foreground process group of the pane's pty and the kernel for
/// that process's executable, then hands the answer to the model layer to
/// classify. Every failure path is `.unknown`, so a pane whose foreground cannot
/// be read behaves exactly as it did before this fence existed (SPEC §29).
enum PaneForegroundProbe {
    /// The foreground process of `surface`'s pty.
    static func foregroundProcess(of surface: xghostty_surface_t?) -> PaneForegroundProcess {
        guard let surface else { return .unknown }
        return classify(pid: xghostty_surface_foreground_pid(surface))
    }

    /// The foreground process for an already-resolved pid, split out so the pid
    /// handling is readable on its own.
    private static func classify(pid raw: UInt64) -> PaneForegroundProcess {
        guard raw != 0, let pid = pid_t(exactly: raw) else { return .unknown }
        return PaneForegroundProcess.classify(executablePath: executablePath(of: pid))
    }

    /// The executable path of `pid`, or `nil` when it cannot be read (the
    /// process already exited, or the kernel refused).
    private static func executablePath(of pid: pid_t) -> String? {
        // libproc's PROC_PIDPATHINFO_MAXSIZE (4 * MAXPATHLEN) is a C macro that
        // Swift does not import, so the same size is spelled out here.
        var buffer = [CChar](repeating: 0, count: 4 * Int(PATH_MAX))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }
}
