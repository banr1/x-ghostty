#!/usr/bin/env bash
# atlas-builder-once.sh — run exactly one Atlas Builder cycle (META.md §18.1).
#
# Usage: cd ./.atlas-builder && bash scripts/atlas-builder-once.sh --project ../PROJECT_TITLE

# shellcheck source=./_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

assert_control_root
exec bash "${CONTROL_ROOT}/scripts/atlas-builder-loop.sh" "$@" --max-cycles 1
