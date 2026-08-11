<!--
  x-ghostty is a fork of Ghostty (https://github.com/ghostty-org/ghostty),
  created from a snapshot of the upstream source. It is distributed under the
  same MIT License (see LICENSE); copyright remains with Mitchell Hashimoto and
  the Ghostty contributors. This fork is independent and is not affiliated with
  or endorsed by the upstream Ghostty project.
-->

# x-ghostty

> **x-ghostty** is a fork of [Ghostty](https://github.com/ghostty-org/ghostty).
> It is distributed under the same [MIT License](LICENSE); copyright remains with
> Mitchell Hashimoto and the Ghostty contributors. This fork is independent and
> not affiliated with or endorsed by the upstream project.

A macOS-only, single-window terminal emulator built on the Ghostty terminal
core.

## About

x-ghostty keeps Ghostty's terminal emulation and rendering core and replaces
its window management with a single model:

- **One window.** There is exactly one terminal window. There are no tabs, no
  additional windows, and no quick terminal. Closing the last project closes the
  window and quits the app.
- **Projects.** A "project" layer sits above splits. Projects are arranged in a
  `ProjectTree` within the single window and can be created, moved, resized,
  zoomed, hidden, shown, renamed, and jumped to by ordinal (Cmd+1-9). See
  [SPEC.md](SPEC.md) for the design.
- **Notes.** Each project holds a short handwritten note (up to 10 lines),
  persisted with the project and restored across restarts. `Cmd+N` opens a
  note editor overlay for the focused project (`Cmd+Enter` saves and closes,
  Esc discards and closes; to keep `Cmd+Enter` free for this, the upstream
  `cmd+enter` fullscreen default is unbound — fullscreen remains on
  `Ctrl+Cmd+F` and the Window menu); clicking the note glyph at the right
  edge of a project's header band opens that project's note editor directly,
  without moving focus; `Cmd+Opt+N` toggles a read-only
  overview that lays every visible project's note over it at once (press
  `Cmd+Opt+N` again or Esc to leave). See SPEC.md §21.
- **Primary panes.** Each project has exactly one primary pane (by default its
  first pane). The overall (non-zoomed) view renders only each project's
  primary, so a many-pane project stays readable at a glance — a subtle
  pane-count badge in the project's top-right corner signals when more panes
  exist behind the primary; zooming into a
  project shows its full split layout, with a subtle mark on the primary when
  the project has multiple panes. While zoomed, `Cmd+P` makes the focused pane
  the primary. Pane operations (splitting, pane focus movement, pane zoom,
  resize/equalize) work only while zoomed. If the primary pane's shell exits,
  the nearest remaining pane is promoted. The primary flag is persisted with
  the pane layout and restored across restarts. See SPEC.md §22.
- **Priorities & deadlines.** Each project can carry a priority
  (high/medium/low, unset by default) and a date-only deadline, set in the
  same `Cmd+N` overlay as the note (invalid dates are rejected to unset) and
  persisted with it. The project's header band and the note overview show a
  subtle priority mark (`!!!`/`!!`/`!`) and the deadline; a past-due deadline
  gets a single-stage subtle emphasis. `Cmd+S` reorders the visible projects by
  priority and `Cmd+Shift+S` by deadline — sorting happens only when invoked
  (never automatically), the layout keeps its shape, hidden projects are
  untouched, and the `Cmd+1-9` ordinals follow the new order. See SPEC.md §24.
- **Deletion protection.** Closing a project always asks for confirmation,
  whether or not anything is running in it. When a project's last pane's shell
  exits, the project stays as a terminated pane — its note, priority, and
  deadline kept — and pressing Return starts a new shell in the same pane.
  The only way a project and its information are lost is an explicitly
  confirmed close. See SPEC.md §23.
- **Splits** work as they do upstream, nested inside each project; in the
  overall view only each project's primary pane is shown (see above).

Everything else — the VT implementation, renderer, font stack, shell
integration, configuration system, and command palette — is inherited from
Ghostty. See the [Ghostty documentation](https://ghostty.org/docs) for
configuration reference; keys related to tabs, multiple windows, and the
Linux/GTK app do not exist in this fork.

Removed relative to upstream Ghostty: the GTK (Linux/FreeBSD) app, tabs,
multi-window, the quick terminal, AppleScript, App Intents, and Services
integration.

## Building

Requires Zig 0.15.x and Xcode.

```shell-session
zig build            # builds the Zig core and the macOS app bundle
just test            # runs the Zig test suite (zig build test)
just swift-test      # runs the Swift unit tests (XGhosttyTests)
```

See [HACKING.md](HACKING.md) for details, [Justfile](Justfile) for common
development recipes, and [AGENTS.md](AGENTS.md) for the short version.

## `libghostty-vt`

The upstream `libghostty-vt` library (terminal sequence parsing and terminal
state, usable from Zig and C) is still present and buildable:

```shell-session
zig build -Demit-lib-vt
```

## Crash Reports

x-ghostty has a built-in crash reporter that saves crash reports to disk under
`$XDG_STATE_HOME/xghostty/crash` (default `~/.local/state/xghostty/crash`).
**Crash reports are _not_ automatically sent anywhere off your machine.**

Crash reports are only generated the next time the app is started after a
crash. Use `xghostty +crash-report` to list available reports.

Crash reports end in the `.ghosttycrash` extension and are in
[Sentry envelope format](https://develop.sentry.dev/sdk/envelopes/).

> [!WARNING]
>
> The crash report can contain sensitive information. The report doesn't
> purposely contain sensitive information, but it does contain the full
> stack memory of each thread at the time of the crash. This information
> is used to rebuild the stack trace but can also contain sensitive data
> depending on when the crash occurred.
