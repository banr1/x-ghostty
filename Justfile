# Justfile for local development.
# Run `just` (or `just --list`) to see available recipes.
#
# XGhostty requires Zig 0.15.x. The system zig may be a different version,
# so default to the Homebrew keg-only 0.15 and allow overriding via ZIG.
zig := env_var_or_default("ZIG", "/opt/homebrew/opt/zig@0.15/bin/zig")

# Path to the prebuilt app bundles. Release-family optimize modes all build
# under the "ReleaseLocal" Xcode configuration (see XGhosttyXcodebuild.zig).
app         := justfile_directory() / "macos/build/Debug/XGhostty.app"
release-app := justfile_directory() / "macos/build/ReleaseLocal/XGhostty.app"

# List available recipes.
default:
    @just --list

# Build and launch XGhostty in debug mode (full build, including the macOS app).
run *args:
    {{zig}} build run {{args}}

# Build and launch XGhostty in release mode (ReleaseFast; optimized, no safety checks).
run-release *args:
    {{zig}} build run -Doptimize=ReleaseFast {{args}}

# Build everything without re-running the macOS app build (faster Zig-core iteration).
build *args:
    {{zig}} build -Demit-macos-app=false {{args}}

# Build in release mode without the macOS app (faster Zig-core iteration).
build-release *args:
    {{zig}} build -Demit-macos-app=false -Doptimize=ReleaseFast {{args}}

# Build the full app bundle (slower; needed for Swift/app changes).
build-app *args:
    {{zig}} build {{args}}

# Build release and install to /Applications so Raycast/Spotlight can launch it.
# Quits a running instance first, then relaunches the installed copy.
install *args:
    #!/usr/bin/env bash
    set -euo pipefail
    {{zig}} build -Doptimize=ReleaseFast {{args}}
    if pgrep -xq xghostty; then
        osascript -e 'quit app "XGhostty"'
        while pgrep -xq xghostty; do sleep 0.2; done
    fi
    rm -rf /Applications/XGhostty.app
    ditto "{{release-app}}" /Applications/XGhostty.app
    # The Zig build edits Info.plist after xcodebuild signs the bundle, which
    # invalidates the signature; LaunchServices (open/Raycast) then refuses to
    # launch it on Apple Silicon. Re-sign ad-hoc so it launches cleanly.
    codesign --force --deep --sign - /Applications/XGhostty.app
    open /Applications/XGhostty.app

# Open the already-built debug app without rebuilding.
app:
    open "{{app}}"

# Open the already-built release app without rebuilding.
app-release:
    open "{{release-app}}"

# Run Zig tests. Optionally pass a filter: `just test "my test name"`.
test filter="":
    {{zig}} build test {{ if filter == "" { "" } else { "-Dtest-filter='" + filter + "'" } }}

# Format Zig sources.
fmt:
    {{zig}} fmt .

# Build the macOS Swift app via xcodebuild with a clean env (avoids Nix interference).
swift-build action="build":
    env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin \
        xcodebuild -project macos/XGhostty.xcodeproj -scheme XGhostty \
        -configuration Debug SYMROOT="{{justfile_directory()}}/macos/build" {{action}}

# Run the Swift unit tests only (XGhosttyUITests crash in headless envs).
swift-test:
    env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin \
        xcodebuild -project macos/XGhostty.xcodeproj -scheme XGhostty \
        -configuration Debug SYMROOT="{{justfile_directory()}}/macos/build" \
        -only-testing:XGhosttyTests test
