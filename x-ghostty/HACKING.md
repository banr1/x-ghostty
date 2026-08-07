# Developing x-ghostty

This document describes the technical details behind x-ghostty's development.

x-ghostty is macOS-only. To start development you need a Git checkout, Zig
0.15.x, and Xcode:

```shell
git clone <your fork of x-ghostty>
cd x-ghostty
```

When you're developing x-ghostty, it's very likely that you will want to build
a _debug_ build to diagnose issues more easily. This is already the default for
Zig builds, so simply run `zig build` **without any `-Doptimize` flags**.

The available build steps are:

| Command                 | Description                                                                                        |
| ----------------------- | -------------------------------------------------------------------------------------------------- |
| `zig build`             | Builds the Zig core and the macOS app bundle                                                       |
| `zig build run`         | Builds and runs the app                                                                            |
| `zig build test`        | Runs unit tests (accepts `-Dtest-filter=<filter>` to only run tests whose name matches the filter) |
| `zig build test-lib-vt` | Runs the `libghostty-vt` unit tests (also accepts `-Dtest-filter`)                                 |
| `zig build dist`        | Builds a source tarball                                                                            |
| `zig build distcheck`   | Builds and validates a source tarball                                                              |

Useful flags:

- `-Demit-macos-app=false` skips building the macOS app bundle. Use this when
  you're only iterating on the Zig core — it is significantly faster.
- `-Demit-lib-vt` builds `libghostty-vt`.

A [Justfile](Justfile) wraps the most common recipes (`just run`, `just build`,
`just test`, `just fmt`, `just swift-build`, `just swift-test`).

## Xcode Version and SDKs

Building the macOS app requires that Xcode, the macOS SDK, the iOS SDK, and the
Metal Toolchain are all installed.

A common issue is that the incorrect version of Xcode is either installed or
selected. Use the `xcode-select` command to ensure that the correct version of
Xcode is selected:

```shell-session
sudo xcode-select --switch /Applications/Xcode.app
```

> [!IMPORTANT]
>
> Main branch development requires **Xcode 26 and the macOS 26 SDK**.
>
> You do not need to be running on macOS 26 to build; you can still use
> Xcode 26 on macOS 15 stable.

> [!WARNING]
>
> Zig 0.15.x has a [known linking issue](https://codeberg.org/ziglang/zig/issues/31658)
> with **Xcode 26.4**. If you are on Xcode 26.4, you must use a
> Homebrew-installed Zig (`brew install zig@0.15`), which contains a patch that
> works around the issue. Alternatively, you can downgrade to **Xcode 26.3**.

## AI and Agents

[AGENTS.md](AGENTS.md) (symlinked as `CLAUDE.md`) is read by most of the
popular AI agents and contains the short version of the build, test, and
formatting commands. `.agents/` also contains vetted prompts and skills for
common tasks.

## Logging

x-ghostty logs to the macOS unified log by default, and can also log to
`stderr`. Use the system `log` CLI to view the logs:

```shell-session
sudo log stream --level debug --predicate 'subsystem=="com.mitchellh.xghostty"'
```

Logging is configured in two ways. The first is by what optimization level
x-ghostty is compiled with: `Debug` builds output debug logs to `stderr`, other
optimization levels do not.

x-ghostty also checks the `XGHOSTTY_LOG` environment variable. It can be used
to control which destinations receive logs. Two destinations are defined:

- `stderr` - logging to `stderr`.
- `macos` - logging to macOS's unified log.

Combine values with a comma to enable multiple destinations. Prefix a
destination with `no-` to disable it. Enabling and disabling destinations
can be done at the same time. Setting `XGHOSTTY_LOG` to `true` will enable all
destinations. Setting `XGHOSTTY_LOG` to `false` will disable all destinations.

## Linting

### Zig

Zig code is formatted with the compiler's own formatter:

```
zig fmt .
```

### Prettier

Docs and resources (not including Zig code) are linted using
[Prettier](https://prettier.io) with out-of-the-box settings. If you are
modifying anything Prettier will lint, run this from the repo root before you
commit:

```
prettier --write .
```

### ShellCheck

Bash scripts are checked with [ShellCheck](https://www.shellcheck.net/):

```
shellcheck \
    --check-sourced \
    --severity=warning \
    $(find . \( -name "*.sh" -o -name "*.bash" \) -type f ! -path "./zig-out/*" ! -path "./macos/build/*" ! -path "./.git/*" | sort)
```

### SwiftLint

Swift code is linted using [SwiftLint](https://github.com/realm/SwiftLint):

```
swiftlint lint --strict --fix
```

To check for violations without auto-fixing, drop `--fix`.

## Input Stack Testing

The input stack is the part of the codebase that starts with a
key event and ends with text encoding being sent to the pty (it
does not include _rendering_ the text, which is part of the
font or rendering stack).

If you modify any part of the input stack, you must manually verify
all the following input cases work properly. We unfortunately do
not automate this in any way, but if we can do that one day that'd
save a LOT of grief and time.

Note: this list may not be exhaustive.

### Dead Key Input

Set your keyboard layout to "Spanish" (or another layout that uses dead keys).

1. Launch x-ghostty
2. Press `'`
3. Press `a`
4. Verify that `á` is displayed

We should also test canceling dead key input:

1. Launch x-ghostty
2. Press `'`
3. Press escape
4. Press `a`
5. Verify that `a` is displayed (no diacritic)

### CJK Input

Enable a Japanese input source in System Settings.

1. Launch x-ghostty
2. Switch to the Japanese input source
3. On a US physical layout, type: `konn`, you should see `こん` in preedit.
4. Press `Enter`
5. Verify that `こん` is displayed in the terminal.

We should also test switching input methods while preedit is active, which
should commit the text:

1. Launch x-ghostty
2. Switch to the Japanese input source
3. On a US physical layout, type: `konn`, you should see `こん` in preedit.
4. Switch to another input source
5. Verify that `こん` is displayed in the terminal as committed text.
