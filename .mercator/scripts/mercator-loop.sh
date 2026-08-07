#!/usr/bin/env bash
# mercator-loop.sh — the continuous autonomous Mercator loop (META.md §19.1).
#
#   assert CWD == CONTROL_ROOT -> trust gate -> single-flight lock (I-018)
#   per cycle:
#     pre-gates (should-stop / should-complete, side-effect-free, I-019)
#     -> assert clean git worktree -> ensure -> start-run
#     -> validate -> should-reset
#     -> claude -p (or -c -p): headless, isolation flags fixed
#     -> end-run -> record-progress -> raise-loop-gates (§13.4)
#     -> validate -> cycle git commit
#     -> post-gates (stop / complete)
#
# A gated invocation refuses before start-run: it writes nothing, commits
# nothing, and prints the stop reason plus the resume instruction (§13.4).
#
# Exit codes (§19.1-5): every designed terminal — complete, a latched stop
# gate, the --max-cycles budget — exits 0. A stop is the designed hand-off to
# the human, reported as STOP, never as ERROR. Nonzero means failure only:
# 2 usage/environment/predicate crash, 4 git refusal, 5 lock contention,
# 130/143 interrupted (SIGINT/SIGTERM). Machine callers query the gate state
# via `mercator state should-stop` / `should-complete`, not via this exit code.
#
# Usage: cd ./.mercator && bash scripts/mercator-loop.sh --project ../PROJECT_TITLE \
#          [-n N | --max-cycles N] [--max-session-cycles N]

# shellcheck source=./_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

assert_control_root
resolve_project "$@"
resolve_git_context

MAX_CYCLES=25
MAX_SESSION_CYCLES=8 # §14.1 backstop: a session lasts at most N cycles (1 fresh + N-1 continued)
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  [[ "${args[$i]}" == "--max-cycles" || "${args[$i]}" == "-n" ]] &&
    MAX_CYCLES="${args[$((i + 1))]:-${MAX_CYCLES}}"
  [[ "${args[$i]}" == "--max-session-cycles" ]] &&
    MAX_SESSION_CYCLES="${args[$((i + 1))]:-${MAX_SESSION_CYCLES}}"
done
[[ "${MAX_CYCLES}" =~ ^[1-9][0-9]*$ ]] ||
  {
    err "-n/--max-cycles must be a positive integer, got: ${MAX_CYCLES}"
    exit 2
  }
[[ "${MAX_SESSION_CYCLES}" =~ ^[1-9][0-9]*$ ]] ||
  {
    err "--max-session-cycles must be a positive integer, got: ${MAX_SESSION_CYCLES}"
    exit 2
  }

command -v claude >/dev/null 2>&1 || {
  err "claude CLI not found; cannot run the loop."
  exit 2
}
require_claude_launch_trust "Over-Project Agent" "${CONTROL_ROOT}"
resolve_session_model
build_sanitized_claude_env

PROMPT_TEMPLATE="${CONTROL_ROOT}/.agent/prompts/mercator-cycle.md"
[[ -f "${PROMPT_TEMPLATE}" ]] || {
  err "missing prompt template: ${PROMPT_TEMPLATE}"
  exit 2
}
PROMPT_TEMPLATE_CONTENT="$(cat "${PROMPT_TEMPLATE}")"

acquire_loop_lock

# §13.5: an interrupted cycle terminates its claude child and closes its run
# record so runs.jsonl stays consistent; the dirty worktree is then recovered
# by `just resume`. claude runs as a background child under `wait` so that
# signal traps are processed immediately instead of after claude exits.
CURRENT_RUN_ID=""
CLAUDE_PID=""
# §28.6: per-cycle stderr capture so a nonzero `claude` exit can be classified
# as infra vs unknown. The FIFO carries claude's stderr to a `tee` that both
# streams it to the terminal (so the human still sees the error live) and saves
# it for classify_claude_exit. These are torn down after every cycle and by the
# signal handler; they live under .agent/tmp (gitignored) so they never dirty
# the worktree the next cycle asserts clean (I-014).
CLAUDE_STDERR_FILE=""
CLAUDE_STDERR_FIFO=""
CLAUDE_TEE_PID=""
cleanup_cycle_capture() {
  if [[ -n "${CLAUDE_TEE_PID}" ]] && kill -0 "${CLAUDE_TEE_PID}" 2>/dev/null; then
    # The tee should have exited on the FIFO's EOF once claude closed it; only
    # a still-live tee (e.g. claude killed mid-write) needs a nudge.
    kill "${CLAUDE_TEE_PID}" 2>/dev/null || true
    wait "${CLAUDE_TEE_PID}" 2>/dev/null || true
  fi
  CLAUDE_TEE_PID=""
  [[ -n "${CLAUDE_STDERR_FIFO}" ]] && rm -f "${CLAUDE_STDERR_FIFO}"
  [[ -n "${CLAUDE_STDERR_FILE}" ]] && rm -f "${CLAUDE_STDERR_FILE}"
  CLAUDE_STDERR_FIFO=""
  CLAUDE_STDERR_FILE=""
}
on_loop_signal() {
  local signal="$1"
  local code="$2"
  err "received ${signal}; aborting the loop."
  if [[ -n "${CLAUDE_PID}" ]] && kill -0 "${CLAUDE_PID}" 2>/dev/null; then
    # §13.5: claude runs as its own process-group leader (set -m at spawn), so
    # the group kill also reaches every verification/build child it started via
    # Bash — a plain single-pid kill would leave such grandchildren running
    # past the lock release. Fall back to the single pid if the group signal
    # fails.
    kill -- -"${CLAUDE_PID}" 2>/dev/null || kill "${CLAUDE_PID}" 2>/dev/null || true
    # Wait for claude to actually die before the EXIT trap frees the
    # single-flight lock: releasing it while the agent still shuts down would
    # let an immediate `just resume --force` race its final writes (I-018).
    wait "${CLAUDE_PID}" 2>/dev/null || true
  fi
  cleanup_cycle_capture
  if [[ -n "${CURRENT_RUN_ID}" ]]; then
    state end-run --project "${PROJECT_ARG}" --run-id "${CURRENT_RUN_ID}" \
      --status "interrupted" >/dev/null 2>&1 || true
    err "run ${CURRENT_RUN_ID} recorded as interrupted; the worktree keeps its partial changes."
    err "Recover with: review the diff, then \`just resume\` (META.md §13.5)."
  fi
  exit "${code}"
}
trap 'on_loop_signal SIGINT 130' INT
trap 'on_loop_signal SIGTERM 143' TERM
# §13.5: claude runs in its OWN process group (set -m), so a terminal hangup
# reaches the wrapper's group but NOT claude's — without this trap the default
# HUP action would run the EXIT trap and free the single-flight lock while a
# headless claude keeps writing, and the documented `just resume --force`
# recovery would then close a still-live run. The handler kills claude's group
# and reaps it before releasing the lock, exactly like INT/TERM.
trap 'on_loop_signal SIGHUP 129' HUP

# A latched stop gate is the loop working as designed — the hand-off to the
# human (§13.4-3) — so it is reported as STOP and exits 0; ERROR/nonzero would
# make every wrapper (just, CI) present the designed pause as a failure.
report_stop_and_exit() {
  local stop_json="$1"
  local when="$2"
  printf '%s\n' "${stop_json}"
  log "STOP: $(stop_message_from_json "${stop_json}"). ${when}"
  print_resume_hint
  exit 0
}

report_complete_and_exit() {
  local complete_json="$1"
  local completion_scope
  printf '%s\n' "${complete_json}"
  completion_scope="$("${MERCATOR_BIN}" util json-get completion_scope <<<"${complete_json}")"
  # §19.3: COMPLETE is either explicit must-scope closure, or musts done plus
  # an approved should phase whose Todos are all explicitly resolved.
  if [[ "${completion_scope}" == "must" ]]; then
    log "Project complete at the explicitly accepted must scope (full_complete). Loop complete."
  else
    log "Project complete: must phase done and every should Todo explicitly resolved (full_complete). Loop complete."
  fi
  log "To continue beyond this, update ESSENCE.md, then run \`just resume\` and \`just loop\` (META.md §19.3)."
  exit 0
}

# Evaluate the stop/complete gate pair and exit if either holds; $1 gives the
# stop report its context line.
# shellcheck disable=SC2153  # state_predicate assigns STOP_JSON/COMPLETE_JSON via nameref.
exit_if_gated() {
  if state_predicate STOP_JSON should-stop --project "${PROJECT_ARG}"; then
    report_stop_and_exit "${STOP_JSON}" "$1"
  fi
  if state_predicate COMPLETE_JSON should-complete --project "${PROJECT_ARG}"; then
    report_complete_and_exit "${COMPLETE_JSON}"
  fi
}

finalize_cycle() {
  local run_status="$1"
  # §28.6: the infra/ok/unknown classification of this cycle's claude exit,
  # distinct from run_status (which is the run.jsonl record: ok/claude_exit_N).
  # record-progress consumes it to drive the infra_unreachable counter.
  local run_class="${2:-ok}"
  local commit_run_status="${run_status}"
  local validation_status
  local stop_json complete_json

  # Cleared BEFORE end-run: a trapped signal is deferred until the foreground
  # command returns and would otherwise re-close the same run as
  # `interrupted` right after this `end-run` recorded its real status,
  # leaving two contradictory end events. If end-run itself fails, the run
  # stays dangling and `just resume --force` recovers it (§13.5).
  CURRENT_RUN_ID=""
  state end-run --project "${PROJECT_ARG}" --run-id "${RUN_ID}" --status "${run_status}" >/dev/null
  state record-progress --project "${PROJECT_ARG}" --run-status "${run_class}" >/dev/null
  # §13.4 / I-017: conditions the loop is about to stop for must exist as
  # canonical Recommendations before the checkpoint, never only as counters.
  state raise-loop-gates --project "${PROJECT_ARG}" >/dev/null

  # §19.1-2 / §24.3: a stop or completion latched during the cycle is the
  # cycle's designed terminal and takes precedence in the commit trailer —
  # even over a nonzero claude exit (infra_unreachable latches ONLY on such
  # cycles, so claude_exit_N winning would make it unreachable). The raw
  # claude_exit_N stays recorded in runs.jsonl's run end status.
  if state_predicate stop_json should-stop --project "${PROJECT_ARG}"; then
    commit_run_status="$(stop_run_status_from_json "${stop_json}")"
  elif state_predicate complete_json should-complete --project "${PROJECT_ARG}"; then
    commit_run_status="complete"
  fi

  state_validate_soft --project "${PROJECT_ARG}" >/dev/null ||
    warn "validation errors remain at cycle end; committing checkpoint for recovery"
  validation_status="$(read_validation_status)"

  commit_cycle_checkpoint "${RUN_ID}" "${CYCLE}" "${MAX_CYCLES}" \
    "${commit_run_status}" "${validation_status}"
}

CYCLE=0
SESSION_MODE="fresh" # first cycle always starts a fresh session
CYCLES_SINCE_FRESH=0

while ((CYCLE < MAX_CYCLES)); do
  CYCLE=$((CYCLE + 1))
  log "=== Mercator cycle ${CYCLE}/${MAX_CYCLES} (${PROJECT_TITLE}) ==="

  # Pre-cycle gates (I-019): a latched stop or a completed project is
  # re-reported without starting a run — no run record, no counter change,
  # no checkpoint commit. Re-running `just loop` while gated is free.
  exit_if_gated "The loop is gated; no cycle was started and nothing was committed."

  assert_clean_worktree_for_cycle
  state ensure --project "${PROJECT_ARG}" >/dev/null
  RUN_ID="$(state start-run --project "${PROJECT_ARG}")"
  CURRENT_RUN_ID="${RUN_ID}"
  log "run ${RUN_ID} started (session: ${SESSION_MODE})"

  state_validate_soft --project "${PROJECT_ARG}" || warn "validation errors — the agent must repair state this cycle"

  if state_predicate RESET_JSON should-reset --project "${PROJECT_ARG}"; then
    log "Context reset triggered (§14.1). Next session starts fresh."
    state reset-context --project "${PROJECT_ARG}" >/dev/null
    SESSION_MODE="fresh"
  fi
  if [[ "${SESSION_MODE}" == "continue" ]] && ((CYCLES_SINCE_FRESH >= MAX_SESSION_CYCLES)); then
    log "Session continuation backstop: ${CYCLES_SINCE_FRESH} cycles since fresh (cap ${MAX_SESSION_CYCLES}, §14.1). Next session starts fresh."
    SESSION_MODE="fresh"
  fi

  # Plain string substitution: sed would corrupt the prompt when the project
  # title contains replacement metacharacters such as `&` or `\`.
  PROMPT="${PROMPT_TEMPLATE_CONTENT//PROJECT_TITLE/${PROJECT_TITLE}}"
  RUN_STATUS="ok"
  # §19.1-5 fail-closed floor: headless `-p` is load-bearing — under
  # `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` the CLI resolves the permission mode to
  # `default`, an unmatched tool maps to ask, and an ask that cannot be shown
  # is denied. The launcher deliberately omits the inert `--permission-mode
  # dontAsk` flag (the settings' `defaultMode: dontAsk` stays as the
  # declarative baseline for non-scrubbed launches). mercator-doctor.sh
  # asserts both headless forms (§28.5).
  CLAUDE_CMD=("${SANITIZED_CLAUDE_ENV[@]}" "MERCATOR_LOCK_TOKEN=${MERCATOR_LOCK_TOKEN}" claude -p "${PROMPT}" --setting-sources project --strict-mcp-config)
  if [[ "${SESSION_MODE}" == "fresh" ]]; then
    CYCLES_SINCE_FRESH=1
  else
    CLAUDE_CMD=("${SANITIZED_CLAUDE_ENV[@]}" "MERCATOR_LOCK_TOKEN=${MERCATOR_LOCK_TOKEN}" claude -c -p "${PROMPT}" --setting-sources project --strict-mcp-config)
    CYCLES_SINCE_FRESH=$((CYCLES_SINCE_FRESH + 1))
  fi
  # §16.1: the per-invocation model override applies to every cycle of this
  # loop run; without MERCATOR_MODEL the array is empty and settings.json decides.
  CLAUDE_CMD+=("${SESSION_MODEL_ARGS[@]+"${SESSION_MODEL_ARGS[@]}"}")

  # §28.6: capture claude's stderr while still streaming it live. A named FIFO
  # feeds a background `tee` that writes both to this stderr (the human sees
  # errors as they happen) and to a temp file for classification. Explicit tee
  # PID + FIFO EOF let us `wait` the tee so the file is fully flushed before we
  # read it — no race between claude's exit and tee's last write.
  mkdir -p "${CONTROL_ROOT}/.agent/tmp"
  CLAUDE_STDERR_FILE="$(mktemp "${CONTROL_ROOT}/.agent/tmp/claude-stderr.XXXXXX")"
  CLAUDE_STDERR_FIFO="$(mktemp -u "${CONTROL_ROOT}/.agent/tmp/claude-stderr-fifo.XXXXXX")"
  RUN_CLASS="ok"
  if mkfifo "${CLAUDE_STDERR_FIFO}" 2>/dev/null; then
    tee "${CLAUDE_STDERR_FILE}" <"${CLAUDE_STDERR_FIFO}" >&2 &
    CLAUDE_TEE_PID=$!
    # set -m: give claude its own process group so the signal trap can kill it
    # together with any verification/build child it spawned (§13.5). Disabled
    # again right after — job control must not affect the rest of the loop.
    set -m
    "${CLAUDE_CMD[@]}" 2>"${CLAUDE_STDERR_FIFO}" &
    CLAUDE_PID=$!
    set +m
    CLAUDE_RC=0
    wait "${CLAUDE_PID}" || CLAUDE_RC=$?
    CLAUDE_PID=""
    # claude closed the FIFO on exit; wait for tee to drain it and finish so the
    # capture file is complete before classify_claude_exit reads it.
    wait "${CLAUDE_TEE_PID}" 2>/dev/null || true
    CLAUDE_TEE_PID=""
    RUN_CLASS="$(classify_claude_exit "${CLAUDE_RC}" "${CLAUDE_STDERR_FILE}")"
  else
    # mkfifo failed (rare: full disk, unsupported fs). Fall back to running
    # claude with its stderr untouched — no capture, so a nonzero exit can only
    # be classified as `unknown`. The idle safety net (§13.1-7) still bounds it.
    warn "could not create stderr capture FIFO; infra classification degraded to unknown this cycle"
    set -m
    "${CLAUDE_CMD[@]}" &
    CLAUDE_PID=$!
    set +m
    CLAUDE_RC=0
    wait "${CLAUDE_PID}" || CLAUDE_RC=$?
    CLAUDE_PID=""
    RUN_CLASS="$(classify_claude_exit "${CLAUDE_RC}" "")"
  fi
  cleanup_cycle_capture

  [[ "${CLAUDE_RC}" -eq 0 ]] || RUN_STATUS="claude_exit_${CLAUDE_RC}"
  SESSION_MODE="continue"
  if [[ "${RUN_STATUS}" != "ok" ]]; then
    # §28.4: a failed invocation may be continuation-poisoned (e.g. `-c` with
    # no resumable conversation). Correctness relies on fresh restarts from
    # disk, so the next cycle starts a fresh session instead of retrying `-c`.
    if [[ "${RUN_CLASS}" == "infra" ]]; then
      # §13.1-12: an infra-caused failure is not the agent being stuck — Claude
      # itself could not run. Name the real cause so the human sees it directly
      # instead of it hiding behind the idle counter three cycles later.
      warn "claude failed for an infra reason (API connection / rate or plan usage limit / auth / Claude-side error); this counts toward the infra_unreachable stop (§13.1-12)."
      log "If it is a plan/model usage limit, wait for the reset or re-run with MERCATOR_MODEL=<tier> to continue on another model (§16.1)."
    fi
    log "claude exited nonzero (class: ${RUN_CLASS}); next session will start fresh (§14.1, §28.4)."
    SESSION_MODE="fresh"
  fi

  finalize_cycle "${RUN_STATUS}" "${RUN_CLASS}"

  exit_if_gated "Stopping before the next cycle."

  # Implementation-level failures never stop the loop immediately (§13.2);
  # the next cycle's agent sees the run status and validation output on disk.
  [[ "${RUN_STATUS}" == "ok" ]] || warn "run ${RUN_ID} ended with ${RUN_STATUS}; continuing (§13.2)"
done

log "Reached max cycles (${MAX_CYCLES}) without a stop or completion. Re-run \`just loop\` to continue."
