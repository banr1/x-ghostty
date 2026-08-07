#!/usr/bin/env bash
# mercator-once.sh — run exactly one Mercator cycle (META.md §18.1).
#
# Usage: cd ./.mercator && bash scripts/mercator-once.sh --project ../PROJECT_TITLE

# shellcheck source=./_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

assert_control_root
exec bash "${CONTROL_ROOT}/scripts/mercator-loop.sh" "$@" --max-cycles 1
