#!/bin/bash

# Build the macOS XGhostty app using xcodebuild with a clean environment
# to avoid Nix shell interference (NIX_LDFLAGS, NIX_CFLAGS_COMPILE, etc.).

set -euo pipefail

scheme="XGhostty"     # Xcode scheme
configuration="Debug" # Build configuration (Debug, Release, ReleaseLocal)
action="build"        # xcodebuild action (build, test, clean, etc.)

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scheme) scheme="$2"; shift 2 ;;
        --configuration) configuration="$2"; shift 2 ;;
        --action) action="$2"; shift 2 ;;
        *) echo "unknown option: $1" >&2; exit 1 ;;
    esac
done

script_dir="$(cd "$(dirname "$0")" && pwd)"
project="$script_dir/XGhostty.xcodeproj"
build_dir="$script_dir/build"

# Skip UI tests for CLI-based invocations because it requires
# special permissions.
skip_testing=()
if [[ "$action" == "test" ]]; then
    skip_testing=(-skip-testing XGhosttyUITests)
fi

exec env -i \
    "HOME=$HOME" \
    "PATH=/usr/bin:/bin:/usr/sbin:/sbin" \
    xcodebuild \
    -project "$project" \
    -scheme "$scheme" \
    -configuration "$configuration" \
    "SYMROOT=$build_dir" \
    ${skip_testing[@]+"${skip_testing[@]}"} \
    "$action"
