#!/usr/bin/env bash
# mercator-init.sh — bind this control plane to ONE target project, then bootstrap it.
#
# Mercator ships as a project-agnostic template: the live control-plane files
# (.claude/settings.json, CLAUDE.md, justfile) start in an *unbound, safe* state
# with no access to any project. This command renders the bind templates in
# templates/control/ into those live files with the chosen project substituted
# in, then runs mercator-bootstrap.sh (seed + state ensure + validate)
# so a workspace with a real human-written ESSENCE.md gets a consistent initial
# state in a single step. If ESSENCE.md is missing, bootstrap seeds a placeholder
# and the human must replace it before doctor/loop.
#
# Design decision (see META.md §26): one control plane binds to exactly one
# project. Re-binding to a different project requires --force.
#
# Usage:
#   cd ./.mercator && bash scripts/mercator-init.sh --project ../PROJECT_TITLE [--force]
#   (or, via the human shortcut) just init ../PROJECT_TITLE

# shellcheck source=./_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

assert_control_root
resolve_project "$@"
# Binding runs entirely through `mercator util` (render / seed / relpath /
# project-index); fail closed up front instead of half-rendering (§5.4).
require_mercator_bin

# I-018: binding rewrites the live control-plane files and (via bootstrap) the
# project state; it must never run beside a live loop/resume. First-time init
# finds no lock and takes it; the bootstrap child below inherits it.
acquire_or_inherit_loop_lock
# §13.5: untrapped INT/TERM would free the lock (EXIT trap) while a foreground
# child (render, bootstrap) still runs; trapping defers the signal until the
# child returns, so the transition never outlives its lock.
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

FORCE=0
for arg in "$@"; do
  [[ "${arg}" == "--force" ]] && FORCE=1
done

TEMPLATES="${CONTROL_ROOT}/templates/control"
INDEX="${CONTROL_ROOT}/.agent/state/project_index.json"

# PROJECT_REL is the project path relative to CONTROL_ROOT, e.g. ../my-project.
# It is what the charter and human-facing docs reference.
PROJECT_REL="$("${MERCATOR_BIN}" util relpath "${PROJECT_ROOT}" "${CONTROL_ROOT}")"
# PROJECT_ABS is the RESOLVED ABSOLUTE project path. Claude Code matches
# permission path rules and sandbox filesystem paths against the resolved
# absolute target, and a RELATIVE rule (`Edit(../my-project/**)`,
# `Read(../my-project/.env)`) silently never matches — so a relative allow rule
# grants nothing (every project Edit/Write is denied) and a relative deny/
# sandbox-denyRead rule protects nothing (the secret is readable). The rendered
# settings therefore use PROJECT_ABS: permission rules take the `//<abs>`
# spelling (a leading `/` prepended in the template), sandbox filesystem paths
# take the plain `<abs>` spelling. This mirrors _lib.sh's read-only-session
# settings, which already build permission rules as f"/{resolved_project}".
PROJECT_ABS="${PROJECT_ROOT}"
# CONTROL_ABS is the RESOLVED ABSOLUTE control-plane path, for the same reason
# on the CONTROL_ROOT side. A relative sandbox filesystem entry (`./.agent/tmp`,
# `./scripts`) resolves against a base the framework does not control — the
# CLI's project-root determination for project settings, `~/.claude` for user
# settings, never the session cwd — and a misresolved entry fails SILENTLY:
# a relative allowWrite leaves CONTROL_ROOT/.agent/tmp unwritable, so every
# mutating state command (validate included) dies creating its lock
# inside sandboxed Bash; a relative denyWrite protects no control surface at
# the OS layer. Sandbox paths are also not symlink-canonicalized by the CLI,
# so this must be the PHYSICAL path — CONTROL_ROOT already is (`pwd -P`).
CONTROL_ABS="${CONTROL_ROOT}"

log "Binding control plane to ${PROJECT_TITLE} (${PROJECT_REL})"

# --- Topology guard (soft) --------------------------------------------------
# Cycle commits require CONTROL_ROOT and PROJECT_ROOT to share one git repo.
# Warn early rather than fail, so a workspace can be `git init`-ed afterwards.
if command -v git >/dev/null 2>&1; then
  c_root="$(git -C "${CONTROL_ROOT}" rev-parse --show-toplevel 2>/dev/null || true)"
  p_root="$(git -C "${PROJECT_ROOT}" rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -z "${c_root}" || -z "${p_root}" ]]; then
    warn "CONTROL_ROOT or PROJECT_ROOT is not inside a git repository yet; cycle commits need one shared repo."
  elif [[ "${c_root}" != "${p_root}" ]]; then
    warn "CONTROL_ROOT and PROJECT_ROOT are in different git repositories; the loop's cycle commits will refuse to run."
  fi
fi

# --- Idempotency / 1:1 guard ------------------------------------------------
# A control plane binds to exactly one project. Refuse to bind over a different
# already-registered project unless --force is given.
if [[ -f "${INDEX}" ]]; then
  # META.md §8.1: the registry is the single `project` object. Reading it here
  # keeps the 1:1 re-bind guard honest: without it a --force-less
  # `just init ../other` rendered the live bind files for `other` before ensure
  # refused — a half-applied re-bind. An unreadable index is a no-op (exit 0,
  # empty): `state ensure` rebuilds the registry right after this guard.
  OTHER="$("${MERCATOR_BIN}" util project-index other "${INDEX}" "${PROJECT_ROOT}" "${CONTROL_ROOT}")"
  if [[ -n "${OTHER}" && "${FORCE}" -ne 1 ]]; then
    err "This control plane is already bound to a different project: ${OTHER}"
    err "One control plane binds to one project. Re-bind with --force to override:"
    err "  bash scripts/mercator-init.sh --project ${PROJECT_ARG} --force"
    exit 2
  fi
fi

# --- Enforce the 1:1 invariant in the index ---------------------------------
# META.md §8.1: prune a registered project OTHER than the target so
# project_index reflects exactly the one bound project after a --force re-bind
# (bootstrap's `state ensure` re-adds the target); this keeps Stop-hook scans
# and status honest. The key stays as an explicit null — the §8.1 unbound
# shape — and the rewrite is atomic like every canonical-state write (§13.5).
if [[ -f "${INDEX}" ]]; then
  "${MERCATOR_BIN}" util project-index prune "${INDEX}" "${PROJECT_ROOT}" "${CONTROL_ROOT}"
fi

# --- Render bind templates --------------------------------------------------
# Token substitution is context-aware: settings.json needs JSON string escaping,
# justfile needs Just string escaping, and Markdown keeps human-readable paths.
render() {
  local src="${TEMPLATES}/$1"
  local dst="${CONTROL_ROOT}/$2"
  local mode="${3:-raw}"
  if [[ ! -f "${src}" ]]; then
    err "missing bind template: templates/control/$1"
    exit 2
  fi
  # Context-aware token substitution lives in the pure Lean core
  # (Mercator/Core/Render.lean): JSON string escaping for settings.json, Just
  # string escaping for the justfile, control-character rejection for raw
  # Markdown. Validation happens BEFORE the live file is touched, then the
  # swap is atomic (`.render.<pid>.tmp` → rename): these are the
  # enforcement-bearing bindings (settings.json permissions/hooks), so a
  # crash or a render error must never leave a truncated/invalid live file.
  "${MERCATOR_BIN}" util render "${src}" "${dst}" "${mode}" \
    --title "${PROJECT_TITLE}" --rel "${PROJECT_REL}" \
    --abs "${PROJECT_ABS}" --control-abs "${CONTROL_ABS}"
  log "rendered: $2"
}

render "settings.json.tmpl" ".claude/settings.json" "json"
render "CLAUDE.md.tmpl" "CLAUDE.md" "raw"
render "justfile.tmpl" "justfile" "just"

# --- Seed the workspace-root README (keep existing) -------------------------
# The workspace root ($(dirname CONTROL_ROOT)) gets a human-facing README that
# describes the two-root layout. Never clobber an existing one — the human (or a
# real repo README) owns the workspace root.
WORKSPACE_ROOT="$(dirname "${CONTROL_ROOT}")"
WS_README="${WORKSPACE_ROOT}/README.md"
WS_TMPL="${CONTROL_ROOT}/templates/workspace/README.md.tmpl"
if [[ -f "${WS_README}" ]]; then
  log "keep existing: workspace README.md"
elif [[ -f "${WS_TMPL}" ]]; then
  # Atomic (`.seed.<pid>.tmp` → rename): a crash mid-seed must not leave a
  # truncated README that the next init then preserves as "existing".
  "${MERCATOR_BIN}" util seed "${WS_TMPL}" "${WS_README}" \
    --replace "__MERCATOR_PROJECT_TITLE__=${PROJECT_TITLE}" \
    --replace "__MERCATOR_PROJECT_PATH__=${PROJECT_REL}"
  log "seeded: workspace README.md"
fi

# --- Bootstrap the target project ------------------------------------------
log "Bootstrapping the target project..."
bash "${CONTROL_ROOT}/scripts/mercator-bootstrap.sh" --project "${PROJECT_ARG}"

log "Init complete. Control plane bound to ${PROJECT_TITLE}."
log "Next: run 'just trust', ensure ${PROJECT_ROOT}/ESSENCE.md is the real human-written Essence, review generated files, commit the initial Mercator state, then run: just loop"
log "If you (re)write ESSENCE.md after this init, record it first with 'just resume' — without that attestation the first loop stops as essence_unreviewed_change (META.md §13.1-10)."
