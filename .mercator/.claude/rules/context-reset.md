# Rule: Context Reset (META.md §14)

## Over-Project Agent (long-lived)

Reset triggers (tracked in `context.json.counters` vs `reset_policy`):

- context usage estimate over the hard threshold
- too many failed attempts / changed files / completed todos / decisions since the last reset
- a major spec rewrite or a completed high-risk change

Before any reset (and before you expect compaction), write a handoff:

1. `PROJECT_ROOT/.mercator/state/context.json` — `handoff.summary`, `handoff.next_actions`, `handoff.open_questions`, counters updated.
2. Append the decision to `reflection.jsonl`.
3. `CONTROL_ROOT/.agent/state/control_context.json` — control-plane-level note if relevant (about Mercator itself, not the target's projection).

A fresh session must be able to resume from disk alone: assume the next Mercator session read nothing but the state files.

## In-Project Agent (not under Mercator's context management — §14.2)

- A project-defined isolated verification run (§10) is a one-shot execution under the target's own rules; its context, memory, and session-continuation habits are the target product's design, not a Mercator session policy. Never substitute a direct live-project launch.
- Never rely on the In-Project Agent remembering anything across cycles; what Mercator keeps is only your interpretation of the observed results, recorded as cycle evidence in canonical state.
