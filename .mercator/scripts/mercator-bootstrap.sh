#!/usr/bin/env bash
# mercator-bootstrap.sh — initialize a project for Mercator (META.md §18.1, §26).
#
# Seeds PROJECT_ROOT with the placeholder Essence, README, and .gitignore from
# CONTROL_ROOT/templates/project (never overwriting existing files), creates
# the canonical state via mercator state ensure, then validates.
# The target's CLAUDE.md / .claude/** are the project's own content and are
# never seeded by Mercator (META.md §5.0, §17).
#
# Usage: cd ./.mercator && bash scripts/mercator-bootstrap.sh --project ../PROJECT_TITLE

# shellcheck source=./_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

assert_control_root
resolve_project "$@"
# Seeding runs through `mercator util seed`; fail closed before touching
# anything (§5.4).
require_mercator_bin

# I-018: seeding + state ensure mutate the project plane; inherit the lock
# when running as the init child, refuse beside a live foreign loop/resume.
acquire_or_inherit_loop_lock
# §13.5: untrapped INT/TERM would free an owned lock (EXIT trap) while a
# foreground child (seed, mercator state) still runs; trapping defers the signal
# until the child returns.
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

TEMPLATES="${CONTROL_ROOT}/templates/project"

log "Bootstrapping ${PROJECT_TITLE} at ${PROJECT_ROOT}"

# Seed a file from the template tree only when the destination does not exist.
# Human-owned files are therefore never clobbered (§7.2). Mode "title"
# substitutes the literal PROJECT_TITLE token; only the prose seeds that carry
# the token use it. Mode "verbatim" copies bytes unchanged, so the .gitignore
# can never be rewritten by a stray token match added to a future template
# revision.
seed() {
  local rel="$1"
  local mode="${2:-title}"
  local src="${TEMPLATES}/${rel}"
  local dst="${PROJECT_ROOT}/${rel}"
  if [[ ! -f "${src}" ]]; then
    warn "template missing: ${rel} (skipped)"
    return
  fi
  if [[ -f "${dst}" ]]; then
    log "keep existing: ${rel}"
    return
  fi
  mkdir -p "$(dirname "${dst}")"
  # Atomic (`.seed.<pid>.tmp` → rename): a crash mid-seed must not leave a
  # truncated file that the next bootstrap then keeps as "existing" — a
  # half-written ESSENCE.md without the placeholder marker would even pass
  # the placeholder gate as a "real" Essence.
  if [[ "${mode}" == "title" ]]; then
    "${MERCATOR_BIN}" util seed "${src}" "${dst}" --replace "PROJECT_TITLE=${PROJECT_TITLE}"
  else
    "${MERCATOR_BIN}" util seed "${src}" "${dst}"
  fi
  log "seeded: ${rel}"
}

seed "ESSENCE.md"
seed "README.md"
seed ".gitignore" verbatim

if essence_has_placeholder_marker "${PROJECT_ROOT}/ESSENCE.md"; then
  # §13.1-8 / §2.1.1: the top guide block OR any leftover section FILL marker
  # means the Essence is not yet written; the loop will gate on it.
  warn "ESSENCE.md is still a placeholder (guide block or a '<!-- FILL:' section marker remains). A human must write the real Essence before the loop runs."
fi

# Canonical state + control-plane registration, then validate.
state ensure --project "${PROJECT_ARG}"
state_validate_soft --project "${PROJECT_ARG}" || warn "validation reported issues (see validation.json)"

log "Bootstrap complete."
log "Next: ensure ${PROJECT_ROOT}/ESSENCE.md is the real human-written Essence, review \`just status\`, commit the initial Mercator state from the workspace root, then run: bash scripts/mercator-loop.sh --project ${PROJECT_ARG}"
