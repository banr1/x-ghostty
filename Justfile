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

# A running instance is left alive; it picks up the new build on its next launch.
# Build release and install to /Applications so Raycast/Spotlight can launch it.
install *args:
    #!/usr/bin/env bash
    set -euo pipefail
    {{zig}} build -Doptimize=ReleaseFast {{args}}
    staging="$(mktemp -d /Applications/.XGhostty-install-XXXXXX)"
    trap 'rm -rf "$staging"' EXIT
    ditto "{{release-app}}" "$staging/XGhostty.app"
    # The Zig build edits Info.plist after xcodebuild signs the bundle, which
    # invalidates the signature; LaunchServices (open/Raycast) then refuses to
    # launch it on Apple Silicon. Re-sign ad-hoc so it launches cleanly.
    codesign --force --deep --sign - "$staging/XGhostty.app"
    # Swap the bundle instead of quitting: a running instance keeps its old
    # (now unlinked) bundle inode and survives the install.
    old=""
    if [ -e /Applications/XGhostty.app ]; then
        old="$(mktemp -d /Applications/.XGhostty-old-XXXXXX)"
        mv /Applications/XGhostty.app "$old/XGhostty.app"
    fi
    mv "$staging/XGhostty.app" /Applications/XGhostty.app
    [ -z "$old" ] || rm -rf "$old"
    # Match on the install path, not the executable name: debug builds are also
    # called `xghostty`, and they must not count as "already running".
    if ! pgrep -fq '/Applications/XGhostty.app/Contents/MacOS/xghostty'; then
        open /Applications/XGhostty.app
    fi

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

# Run the verification suite (Zig tests + Swift unit tests) with all caches
# kept inside the repo, so it also works in sandboxes that deny writes to
# $HOME. `just check zig` / `just check swift` run a single half.
check target="all":
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{justfile_directory()}}"
    export ZIG_GLOBAL_CACHE_DIR="{{justfile_directory()}}/.zig-global-cache"
    if [ "{{target}}" = "all" ] || [ "{{target}}" = "zig" ]; then
        {{zig}} build test
    fi
    if [ "{{target}}" = "all" ] || [ "{{target}}" = "swift" ]; then
        # No `env -i` here (unlike swift-build/swift-test): sandboxed
        # environments route network access and temp dirs through env vars,
        # and stripping them breaks SwiftPM's package resolution. TMPDIR is
        # pinned into the repo for the same reason: SwiftPM lock files in the
        # default per-user temp dir are unwritable under a sandbox.
        mkdir -p "{{justfile_directory()}}/.tmp"
        TMPDIR="{{justfile_directory()}}/.tmp" \
            xcodebuild -project macos/XGhostty.xcodeproj -scheme XGhostty \
            -configuration Debug SYMROOT="{{justfile_directory()}}/macos/build" \
            -derivedDataPath "{{justfile_directory()}}/macos/build/DerivedData" \
            -resultBundlePath "{{justfile_directory()}}/.tmp/XGhosttyTests-$(date +%Y%m%d%H%M%S).xcresult" \
            -only-testing:XGhosttyTests test
    fi
