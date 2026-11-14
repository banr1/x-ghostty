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
  zoomed, hidden, shown, renamed, and reordered. Up to 24 projects can be
  visible at once, and every visible project carries a number (1 up to 24) in
  placement order, shown before its title in the header band and in the
  project list's number column; hidden projects have none. Keyboard focus
  moves with just two chords, the same in the overall view and while zoomed:
  `Opt+Tab` / `Opt+Shift+Tab` go to the next / previous one — the visible
  projects in number order in the overall view, the zoomed project's panes in
  split order while zoomed — wrapping around at both ends, and
  `Cmd+Opt+arrows` go to the neighbor in that direction (the adjacent visible
  project, or the adjacent pane while zoomed). Both do nothing while an
  overlay is up or when there is nowhere to go, and are never passed to the
  program in the terminal. There is no key that jumps to a project by number;
  a distant project is reached from the project list with `Cmd+Enter`
  (upstream's `goto_split` action stays available for user keybinds, with no
  default chord on macOS). The project list (see below) is the ledger that
  holds every
  project; the on-screen arrangement is derived from it. See
  [SPEC.md](SPEC.md) for the design.
- **Notes.** Each project holds a short handwritten note (up to 100 lines),
  persisted with the project and restored across restarts. Editing and
  pasting are never limited; if a save would exceed 100 lines a confirmation
  appears — OK keeps the first 100 lines, Cancel returns to editing. `Cmd+E`
  opens a note editor overlay for the focused project (`Cmd+Enter` saves and
  closes, Esc discards and closes; to keep `Cmd+Enter` free for this, the
  upstream `cmd+enter` fullscreen default is unbound — fullscreen remains on
  `Ctrl+Cmd+F` and the Window menu; the upstream `cmd+e` search-selection
  default is likewise removed, though the action stays available for user
  keybinds); clicking the note glyph at the right
  edge of a project's header band opens that project's note editor directly,
  without moving focus; `Cmd+Opt+E` toggles a read-only
  overview that lays every visible project's note — and nothing else — over
  it at once (press
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
  resize/equalize) work only while zoomed. If the primary pane is closed with
  `Cmd+W`, the nearest remaining pane is promoted; if its command merely exits,
  it stays primary as a terminated pane (see Deletion protection). The primary flag is persisted with
  the pane layout and restored across restarts. See SPEC.md §22.
- **Deletion protection.** Closing a project always asks for confirmation,
  whether or not anything is running in it. When a pane's command (its tmux
  client or ssh) exits — normally, abnormally, or by being killed — the pane
  is never closed: with or without sibling panes it stays in place as a
  terminated pane, with its last output visible, the split layout and the
  primary flag unchanged, and the project's note kept. Keys other than Return do nothing on it. Pressing Return on
  any terminated pane re-runs the command (its tmux attach) of every
  terminated pane of that project, each in its own pane, leaving live panes
  untouched. A pane leaves the split tree only through an explicit close
  (`Cmd+W`, `close_project`, or `Delete` on a selected row).
  The only way a project and its information are lost is an explicitly
  confirmed close (`Cmd+W` on the last pane, `close_project`, or `Delete` on
  a selected row in the project list); quitting and relaunching restores
  every project. See SPEC.md §23.
- **Hiding.** `Cmd+Opt+H` immediately hides the focused project — no
  selection screen — and the remaining projects re-lay themselves out with
  the remembered layout type. At least one project always stays visible, so
  hiding the last visible project is refused. See SPEC.md §25.
- **Project list.** `Cmd+L` toggles the ledger: a table covering roughly 80%
  of the window that lists *every* project, hidden ones included (drawn in
  the same color as visible rows), in one unpartitioned row order with five
  columns — visibility, kind (Core or Side), title, terminal, and the note's
  first line. The rows are always in the human's own (manual) order; there is
  no sorting. This row order is the source of truth: the on-screen
  arrangement is derived from it, and the project numbers count all of its
  visible rows, Cores first and then Sides, each kind in row order (a hidden
  row shows `·` instead of a number). Cell operations follow the Notion idiom. The
  cell cursor moves with the arrows and Tab / Shift+Tab (row-end wrap, edge
  stop); `Cmd+arrows` jump it to the edges. Enter operates on the cell: text
  cells start an edit with the caret in the existing text (typing instead
  replaces the content), the visibility cell hides or shows the project on
  the spot — immediately re-laying out the terminals behind the list — and
  the kind and terminal cells enumerate candidates below the cell (Core then
  Side; the registered terminals), chosen with `↑↓` and Enter;
  while candidates are listed, Tab / Shift+Tab close them without changing
  the value and move to the next / previous cell.
  While editing, Enter commits and moves down, Tab commits and moves right,
  Esc cancels the edit; in the note cell the edit covers the whole note
  (Shift+Enter inserts a newline, the cell expands and scrolls, and an
  over-100-line save asks for confirmation). Text cells are ordinary macOS
  text input, so an input method composes from the very first keystroke and,
  while an uncommitted string is up, Space / Enter / Esc drive the
  composition instead of the cell. The standard editing shortcuts —
  `Cmd+A` / `Cmd+C` / `Cmd+X` / `Cmd+V` and `Cmd+Z` / `Cmd+Shift+Z` — act
  on the cell's editor while an edit is up (never on the terminal behind),
  with undo scoped to that editing session. On the cell cursor, `Cmd+C`
  copies the cell's value and `Cmd+V` sets it from the clipboard (single
  cell only; the note column carries every line; a string the column does
  not accept is ignored — the kind column takes only Core or Side, the
  terminal column only a registered terminal's name; the visibility column
  takes no part). `Delete` clears the cell's value (the kind cell goes back
  to Core, the terminal cell to the local one; the note cell asks
  first); Esc on the cell cursor selects the whole row — `↑↓` move the
  selection, `Delete` deletes the row's project behind the same confirmation
  as closing it (hidden rows included; if it was the focused project, keyboard
  focus moves to the newly focused project exactly as with `close_project`,
  while the list stays open), Enter or Esc return to the cells.
  `Opt+↑↓` move the cursor's row (no confirmation) and `Opt+←→` its
  column; both orders persist across restarts. `Cmd+Opt+E` toggles showing
  every row's full note. `Cmd+N` — inside or outside the list — creates a
  new project below the cursor row, ready for its title to be typed; the list is the only creation
  path. `Cmd+Enter` on a visible row focuses that project and closes the
  list; on a hidden row it closes the list and focuses a nearby visible
  project. Opened while zoomed, the list overlays the zoom without releasing
  it (and `Cmd+Enter` switches the zoom target). The list closes on `Cmd+L`
  or a backdrop click — never on Esc — and the table scrolls to follow the
  cursor. This is also the only way back for a hidden project: there is no
  always-on hidden-project shelf, so nothing permanently occupies terminal
  space. See SPEC.md §27.
- **Shortcut list.** `Cmd+/` toggles a read-only overlay listing the
  effective shortcuts — upstream-inherited ones included — grouped by scene
  (overall view, zoom, project list, note editor, overview). It opens from
  any scene, stacking above whatever is on screen, and closing it (Esc or
  `Cmd+/` again) restores the previous state untouched, in-progress edits
  included. The upstream `cmd+k` clear-screen default is unbound (the action
  remains available for user keybinds). See SPEC.md §30.
- **Terminals and tmux sessions.** Machines are registered in the config with
  `project-terminal = <name>,<host>[,<color>]` (repeatable; reloading the
  config applies changes). The terminal whose host matches this machine's
  hostname (ignoring `.local` and case) is the local one; with nothing
  registered, an implicit local terminal named after the hostname exists.
  Each project runs on one terminal — local by default, chosen in the project
  list's terminal column. Every pane, local ones included, is started as the
  command `tmux new-session -A -s <project id>-<n>`, wrapped in
  `ssh -t <host>` (with `TERM=xterm-256color`) for a non-local terminal and
  leaving user, key, and port to your `~/.ssh/config`. A new session starts in
  `~/workspace/<title>`, else `~/workspace`, else home; a split inherits the
  current path of the pane it splits. On attach, only that session gets its
  status bar colored with the terminal's color, the project title as
  `status-left` (updated on rename), and `C-s` as its prefix — your
  `~/.tmux.conf` and other sessions are left alone. When tmux or ssh exits
  (detach, session end, a failed or dropped connection) the pane becomes
  terminated with its output still visible — siblings or not — and Return
  re-runs the same attach for every terminated pane of the project.
  Restarting xghostty re-attaches every pane to its saved session.
  Closing a pane or project kills its sessions once the undo period has
  passed (not if undone); quitting never kills them. The former OSC 7
  remote-split detection is gone, and the upstream core is back to its
  original OSC 7 handling. See SPEC.md §29.
- **Layout types.** The screen arrangement is a layout type — Wide or its
  transpose, Tall (the wide shape uses about √n rows and gives any remainder to
  the later rows, so the top rows hold fewer, wider slots — eight projects go
  2+3+3; the project numbers run along the rows on Wide and down the columns
  on Tall) —
  remembered persistently and re-applied automatically whenever the number of
  visible projects or a visible project's kind changes (hiding, showing,
  creating, closing, changing the kind). Each project is a Core or a Side: every
  project takes one slot, but a Side is half as wide as a Core in the same row
  (half as tall in the same column, on the tall shape), and the Cores are placed
  first. The project numbers follow that placement. A saved pedestal layout from an older
  version loads as Wide, and a saved row/column direction is dropped, keeping
  the shape. `Cmd+Opt+L` lists only the distinct choices for the
  current visible projects (identical arrangements are collapsed; with a single
  choice it just says there is nothing to choose):
  arrow keys + Enter apply one, Esc closes without changing anything, and
  the project count never changes. Project boundaries cannot be resized or
  equalized by hand — pane resizing inside a zoomed project still works. See
  SPEC.md §26.
- **Splits** work as they do upstream, nested inside each project; in the
  overall view only each project's primary pane is shown (see above).
- **What isn't drawn costs nothing.** Only the surfaces actually on screen
  render: each visible project's primary pane in the overall view, and every
  pane of the zoomed project while zoomed. Hidden projects' panes, non-primary
  panes in the overall view, and the other projects' panes while zoomed stop
  their renderer and display link entirely — their shells and PTYs keep running,
  so showing one again draws the latest screen including whatever arrived
  meanwhile. This holds from the moment a surface is born: every surface —
  restored, split off, or restarted from a terminated pane — is created
  stopped, and only starts drawing when the one model-layer transition the
  tests check puts it on screen; every later start and stop goes through
  that same transition. Overlays only cover the terminal; they never change what is drawn
  behind them. Closing a pane or project — by `Cmd+W`, `close_project`, or
  `Delete` on a selected list row alike — frees its surface along with its
  view, PTY, renderer, display link, threads, and IOSurfaces once the usual
  undo window expires, and so do surfaces replaced by restarting a
  terminated pane or discarded during launch-time restore. Two upstream
  leaks are fixed for this: a terminal view no longer subscribes to its own
  selection notifications with a strong self-reference, and the core surface
  is freed synchronously on the main thread instead of being deferred past
  its view's lifetime. Closing from the keyboard also re-runs pointer
  tracking once, so SwiftUI's hover state does not keep the closed views
  that were under a resting mouse pointer alive. This is why
  the app can sit idle for days holding many projects without burning CPU or
  GPU memory. See SPEC.md §31.

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
