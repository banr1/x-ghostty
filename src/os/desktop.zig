const std = @import("std");
const builtin = @import("builtin");
const build_config = @import("../build_config.zig");
const posix = std.posix;

const c = @cImport({
    @cInclude("unistd.h");
});

/// Returns true if the program was launched from a desktop environment.
///
/// On macOS, this returns true if the program was launched from Finder.
///
/// For other platforms and app runtimes, this returns false.
pub fn launchedFromDesktop() bool {
    return switch (builtin.os.tag) {
        // macOS apps launched from finder or `open` always have the init
        // process as their parent.
        .macos => macos: {
            // This special case is so that if we launch the app via the
            // app bundle (i.e. via open) then we still treat it as if it
            // was launched from the desktop.
            if (build_config.artifact == .lib) lib: {
                const env = "XGHOSTTY_MAC_LAUNCH_SOURCE";
                const source = posix.getenv(env) orelse break :lib;

                // Source can be "app", "cli", or "zig_run". We assume
                // its the desktop only if its "app". We may want to do
                // "zig_run" but at the moment there's no reason.
                if (std.mem.eql(u8, source, "app")) break :macos true;
            }

            break :macos c.getppid() == 1;
        },

        // On Linux and BSD, GTK sets GIO_LAUNCHED_DESKTOP_FILE and
        // GIO_LAUNCHED_DESKTOP_FILE_PID. We only check the latter to see if
        // we match the PID and assume that if we do, we were launched from
        // the desktop file. Pid comparing catches the scenario where
        // another terminal was launched from a desktop file and then launches
        // XGhostty and XGhostty inherits the env.
        .linux, .freebsd => ul: {
            const gio_pid_str = posix.getenv("GIO_LAUNCHED_DESKTOP_FILE_PID") orelse
                break :ul false;

            const pid = c.getpid();
            const gio_pid = std.fmt.parseInt(
                @TypeOf(pid),
                gio_pid_str,
                10,
            ) catch break :ul false;

            break :ul gio_pid == pid;
        },

        // TODO: This should have some logic to detect this. Perhaps std.builtin.subsystem
        .windows => false,

        // iPhone/iPad is always launched from the "desktop"
        .ios => true,

        else => @compileError("unsupported platform"),
    };
}
