# Justfile for local development.
# Run `just` (or `just --list`) to see available recipes.
#
# Ghostty requires Zig 0.15.x. The system zig may be a different version,
# so default to the Homebrew keg-only 0.15 and allow overriding via ZIG.
zig := env_var_or_default("ZIG", "/opt/homebrew/opt/zig@0.15/bin/zig")

# Path to the prebuilt app bundles.
app         := justfile_directory() / "macos/build/Debug/Ghostty.app"
release-app := justfile_directory() / "macos/build/Release/Ghostty.app"

# List available recipes.
default:
    @just --list

# Build and launch Ghostty in debug mode (full build, including the macOS app).
run *args:
    {{zig}} build run {{args}}

# Build and launch Ghostty in release mode (ReleaseFast; optimized, no safety checks).
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
        xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty \
        -configuration Debug SYMROOT="{{justfile_directory()}}/macos/build" {{action}}

# Run the Swift unit tests only (GhosttyUITests crash in headless envs).
swift-test:
    env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin \
        xcodebuild -project macos/Ghostty.xcodeproj -scheme Ghostty \
        -configuration Debug SYMROOT="{{justfile_directory()}}/macos/build" \
        -only-testing:GhosttyTests test
