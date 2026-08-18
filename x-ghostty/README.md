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
- **Projects.** A "project" layer sits above splits. Projects can be created,
  zoomed, hidden, shown, renamed, reordered, and jumped to by ordinal
  (Cmd+1-9). The project list (see below) is the ledger that holds every
  project; the on-screen arrangement is derived from it. See
  [SPEC.md](SPEC.md) for the design.
- **Notes.** Each project holds a short handwritten note (up to 10 lines),
  persisted with the project and restored across restarts. `Cmd+E` opens a
  note editor overlay for the focused project (`Cmd+Enter` saves and closes,
  Esc discards and closes; to keep `Cmd+Enter` free for this, the upstream
  `cmd+enter` fullscreen default is unbound — fullscreen remains on
  `Ctrl+Cmd+F` and the Window menu; the upstream `cmd+e` search-selection
  default is likewise removed, though the action stays available for user
  keybinds); clicking the note glyph at the right
  edge of a project's header band opens that project's note editor directly,
  without moving focus; `Cmd+Opt+E` toggles a read-only
  overview that lays every visible project's note — along with its priority,
  deadline, and next trigger — over it at once (press
  `Cmd+Opt+E` again or Esc to leave). Inside the editor the standard editing
  shortcuts apply, including `Cmd+Z` / `Cmd+Shift+Z` for undo and redo of the
  note body — the history covers one editing session and nothing else, so it
  can never reach back into the project layer's own undo. See SPEC.md §21.
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
- **Priorities, deadlines & next triggers.** Each project can carry a priority
  (high/medium/low, unset by default), a date-only deadline (invalid dates are
  rejected to unset), and a next trigger — who or what moves the project next
  (self / team member / external person / event, unset by default). All three
  are set in the project list's cells and persisted with the project. The
  project's header band shows a subtle priority mark (`!!!`/`!!`/`!`) and the
  deadline (never the next trigger); the note overview shows all three
  alongside the note; a past-due deadline gets a single-stage subtle emphasis.
  `Cmd+S` reorders the project list's rows by priority and `Cmd+Shift+S` by
  deadline — every row is sorted, hidden ones included, sorting happens only
  when invoked (never automatically), it works whether or not the list is
  open, and the `Cmd+1-9` ordinals follow the visible rows of the new order.
  Priority means "today's focus", so it clears itself every morning: at local
  06:00 every project's priority — hidden ones included — goes back to unset,
  once per day, silently, without reordering anything. Deadlines, notes, and
  next triggers are left alone. See SPEC.md §24 and §28.
- **Deletion protection.** Closing a project always asks for confirmation,
  whether or not anything is running in it. When a project's last pane's shell
  exits, the project stays as a terminated pane — its note, priority,
  deadline, and next trigger kept — and pressing Return starts a new shell in
  the same pane.
  The only way a project and its information are lost is an explicitly
  confirmed close. See SPEC.md §23.
- **Hiding.** `Cmd+Opt+H` immediately hides the focused project — no
  selection screen — and the remaining projects re-lay themselves out with
  the remembered layout type. At least one project always stays visible, so
  hiding the last visible project is refused. See SPEC.md §25.
- **Project list.** `Cmd+L` opens the ledger: a table covering roughly 80% of
  the window that lists *every* project, hidden ones included, in one
  unpartitioned row order with six columns — visibility, title, priority,
  deadline, next trigger, and the note's first line. This row order is the
  source of truth: the on-screen arrangement is derived from it, and the
  `Cmd+1-9` ordinals are its visible rows counted from the top. The list has
  a cell cursor (Tab / Shift+Tab / Enter / Shift+Enter, or arrows); typing in
  a text cell starts an edit that Enter / Tab commit and Esc cancels; Space
  cycles a selection cell — on the visibility column it hides or shows the
  project on the spot, immediately re-laying out the terminals behind the
  list (the change sticks even if you then press Esc). On the deadline cell
  Space steps the date instead: today first, then one day forward per press,
  with Shift+Space stepping back and clearing the cell when it reaches
  today — each press takes effect immediately (typing a date still works,
  and is how past dates are set). `Cmd+↑`/`Cmd+↓` move
  the cursor's row and `Cmd+←`/`Cmd+→` its column — the cursor follows the
  moved row or column, so repeated presses keep moving the same one — and
  both orders persist
  across restarts. `Cmd+Opt+E` toggles showing every row's full note.
  `Cmd+N` — inside or outside the list — creates a new project right below
  the cursor row, ready for its title to be typed; the list is the only
  creation path. `Cmd+Enter` on a visible row focuses that project and
  closes the list (on a hidden row it does nothing), Esc closes it, and the
  table scrolls to follow the cursor. This is also the only way back for a
  hidden project: there is no always-on hidden-project shelf, so nothing
  permanently occupies terminal space. See SPEC.md §27.
- **Remote splits.** Splitting a pane whose shell is on a remote host (as
  reported by shell integration over OSC 7) opens the new pane on that same
  host and in the same directory, reconnecting with `ssh` and leaving user,
  key, and port to your `~/.ssh/config`. A pane that is back at its own shell
  prompt counts as local again even if its last report came from elsewhere, so
  returning from `ssh` and splitting gives you a local pane. If the location
  cannot be determined or the connection fails, you simply get a local pane as
  before. Only splits do this — new projects always start locally. See
  SPEC.md §29.
- **Layout types.** The screen arrangement is a layout type — a shape (wide,
  tall, or pedestal: n−1 on top plus one full-width across the bottom) times
  an ordinal direction (row-major or column-major) — remembered persistently
  and re-applied automatically whenever the number of visible projects
  changes (hiding, showing, creating, closing). `Cmd+Opt+L` lists only the
  distinct choices for the current visible count (identical arrangements are
  collapsed; with a single choice it just says there is nothing to choose):
  arrow keys + Enter apply one, Esc closes without changing anything, and
  the project count never changes. Project boundaries cannot be resized or
  equalized by hand — pane resizing inside a zoomed project still works. See
  SPEC.md §26.
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
