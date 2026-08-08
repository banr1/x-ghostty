import Mercator.Core.Json
import Mercator.Core.Sha256
import Mercator.State.Model
import Mercator.State.Predicates
import Mercator.State.Validate

/-!
`Mercator.State.Loop` — loop 系 mutating コマンドの
純粋決定核。

置換元は state.py の `cmd_record_progress` / `cmd_raise_loop_gates` /
`cmd_start_run` / `cmd_end_run` / `cmd_reset_context` と progress signature
基盤(`normalize_for_progress` / `stable_json_bytes` /
`compute_progress_signature`)。

エラーチャネルの規約(§3.4 の型区別):
- gate 系関数(`recordProgressGate` / `startRunGate` / `resetContextGate`)の
  `.error` は Python `die(...)` の文言 — IO シェルが `die`(exit 2、
  `[mercator state] ERROR:` プレフィクス)へ写す。
- apply / core 系関数(`resetContextApply` / `raiseLoopGatesCore`)の
  `.error` は Python の uncaught 例外(TypeError 等)— IO シェルが
  ハードエラー枠(traceback 相当 + exit 2)へ写す。

I-021: gate-holding の context.json / project.json は「読めない・形状崩れ」
を明示的な die へ写像し、既定値から再構築する経路を提供しない。
-/

namespace Mercator.State.Loop

open Mercator.Core
open Mercator.State.Model
open Mercator.State.Validate (schemaVersion)

/-! ## progress signature(state.py L1431–1553) -/

/-- state.py `PROGRESS_EXCLUDED_DIRS`。 -/
def progressExcludedDirs : List String := [
  ".git", ".mercator", ".mypy_cache", ".next", ".ruff_cache", ".pytest_cache",
  ".turbo", ".uv-cache", ".venv", "__pycache__", "build", "coverage", "dist",
  "logs", "node_modules", "target", "tmp"
]

/-- state.py `CONTROL_PROGRESS_PATHS`(§11.3 の High-Risk 面と同じ集合)。 -/
def controlProgressPaths : List String := [
  "CLAUDE.md", "README.md", "META.md", "justfile", "scripts", ".claude",
  ".agent/prompts", "templates"
]

/-- Python `is_progress_excluded`: `Path(rel).parts` と除外集合の交差
(ファイル名成分自身も含む)。 -/
def isProgressExcluded (rel : String) (excluded : List String) : Bool :=
  (rel.splitOn "/").any excluded.contains

/-- `normalize_for_progress` が落とす揮発フィールド(全階層)。 -/
def volatileProgressKeys : List String := [
  "last_validated_at", "last_run_id", "written_at", "summary",
  "next_actions", "open_questions"
]

mutual
  /-- Python `normalize_for_progress`: dict は揮発キーを除きキー順ソート、
  list は各要素へ再帰。`sort_keys=True` の直列化と合わせて署名を安定化する。 -/
  def normalizeForProgress : Json.Value → Json.Value
    | .obj entries =>
      .obj (((normalizeEntries entries).filter
          (fun e => !volatileProgressKeys.contains e.1)).mergeSort
        (fun a b => a.1 ≤ b.1))
    | .arr items => .arr (normalizeItems items)
    | v => v

  def normalizeItems : List Json.Value → List Json.Value
    | [] => []
    | v :: rest => normalizeForProgress v :: normalizeItems rest

  def normalizeEntries : List (String × Json.Value) → List (String × Json.Value)
    | [] => []
    | (k, v) :: rest => (k, normalizeForProgress v) :: normalizeEntries rest
end

/-- Python `stable_json_bytes` の文字列部: normalize →
`json.dumps(..., ensure_ascii=False, sort_keys=True, separators=(",", ":"))`。
ソートは normalize が全階層で済ませている。 -/
def stableJsonString (v : Json.Value) : String :=
  (normalizeForProgress v).renderCompact

/-- `compute_progress_signature` の観測入力。ファイルツリーの
`(相対パス, SHA-256)` 列は IO シェルが収集する(git ls-files 優先・
walk フォールバック、control 面は接頭辞付与 + 全体ソート済み)。 -/
structure SignatureInputs where
  spec : RawFile
  todo : RawFile
  recommendations : RawFile
  blockers : RawFile
  highRisk : RawFile
  projectEntries : List (String × String)
  controlEntries : List (String × String)

/-- Python `compute_progress_signature`: 署名ペイロード(state 4 面 +
high-risk ログ + プロジェクト/コントロールのファイル指紋)の安定直列化の
SHA-256 hex。state 読みは `read_json_or_empty`(診断なし = 破損は空扱い)、
ログは `read_jsonl_or_empty`。 -/
def progressSignature (i : SignatureInputs) : String :=
  let entryArr (es : List (String × String)) : Json.Value :=
    .arr (es.map fun e => .arr [.str e.1, .str e.2])
  let payload : Json.Value := .obj [
    ("state", .obj [
      ("spec.json", (readJsonOrEmpty "spec.json" i.spec).1),
      ("todo.json", (readJsonOrEmpty "todo.json" i.todo).1),
      ("recommendations.json",
        (readJsonOrEmpty "recommendations.json" i.recommendations).1),
      ("blockers.json", (readJsonOrEmpty "blockers.json" i.blockers).1)]),
    ("logs", .obj [
      ("high_risk_changes.jsonl",
        .arr (readJsonlOrEmpty "high_risk_changes.jsonl" i.highRisk).1)]),
    ("project_files", entryArr i.projectEntries),
    ("control_files", entryArr i.controlEntries)
  ]
  Sha256.hexDigest (stableJsonString payload).toUTF8

/-! ## record-progress(state.py `cmd_record_progress` L1988–2094) -/

/-- Python dict `setdefault`: キーが在れば(値が null でも)そのまま、
無ければ末尾へ追加。 -/
def setdefault (v : Json.Value) (k : String) (dflt : Json.Value) : Json.Value :=
  match v.get? k with
  | some _ => v
  | none => v.set k dflt

/-- record-progress の進捗カウンタ読み: `int(raw) if raw is not None else 0`。
診断文言は should-stop の `progressCounter` と異なり `context.json:`
プレフィクスを持たない(Python 原文どおり)。 -/
private def counterOr0 (progress : Json.Value) (key : String) : Int × List String :=
  match progress.get? key with
  | none | some .null => (0, [])
  | some v =>
    match pyInt? v with
    | some n => (n, [])
    | none => (0, [s!"progress.{key} is not an integer"])

/-- I-021 ゲートを通過した context と、進捗カウンタの事前値。 -/
structure RecordGate where
  context : Json.Value
  priorIdle : Int
  priorInfra : Int
  /-- `progress.get("last_signature")`(欠落・null は Python の None)。 -/
  previous : Option Json.Value

/-- `cmd_record_progress` の I-021 ゲート(ファイル欠落は IO 側の
`is_file()` 検査)。`.error` は die 文言。検査順は Python と同一:
unreadable → schema_version setdefault → progress 形状 → shape 診断
(idle 閾値 → infra 閾値 → idle カウンタ → infra カウンタ)。 -/
def recordProgressGate (contextRaw : RawFile) : Except String RecordGate := do
  let (context, diag) := readJsonOrEmpty "context.json" contextRaw
  if let some d := diag then
    throw (s!"context.json is unreadable ({d}); repair it (git restore) "
      ++ "before recording progress.")
  let context := setdefault context "schema_version" (.str schemaVersion)
  let progress ← match context.get? "progress" with
    | some (.obj es) => pure (Json.Value.obj es)
    | _ => throw ("context.json progress is missing or not an object; repair it "
        ++ "(git restore) before recording progress.")
  let (_, d1) := Predicates.stopThreshold context "stop_after_idle_cycles"
    defaultStopAfterIdleCycles true
  let (_, d2) := Predicates.stopThreshold context "stop_after_infra_fails"
    defaultStopAfterInfraFails false
  let (priorIdle, d3) := counterOr0 progress "idle_cycles_since_progress"
  let (priorInfra, d4) := counterOr0 progress "infra_fails_since_ok"
  let shapeDiags := d1 ++ d2 ++ d3 ++ d4
  if !shapeDiags.isEmpty then
    throw (s!"context.json is shape-corrupt ({String.intercalate "; " shapeDiags}); "
      ++ "repair it (git restore) before recording progress.")
  let previous := match progress.get? "last_signature" with
    | some .null => none
    | x => x
  pure { context, priorIdle, priorInfra, previous }

structure RecordOutcome where
  newContext : Json.Value
  payload : Json.Value

/-- `cmd_record_progress` の適用部: 署名比較 → カウンタ更新 → 出力
ペイロード(キー順まで Python と同一)。常に exit 0。

resume note の消費(§19.3): `--run-status ok`(agent cycle が実際に完走した
cycle 終端)に限り、gate release resume が立てた `handoff.pending_cycle` を
false へ下ろす — これが `full_complete` の resume note 未消費ガードを解く
唯一の遷移である。infra / unknown / 未指定では note は未消費のまま保持する
(agent は走っていない)。handoff が object でない・フラグが無い場合は
何も触らない(record-progress が handoff を再構築してはならない)。 -/
def recordProgressApply (g : RecordGate) (current : String)
    (runStatus : Option String) (now : String) : RecordOutcome :=
  let (idleCycles, changed, changeKind) :=
    match g.previous with
    | none => ((0 : Int), true, "baseline")
    | some prev =>
      if prev == Json.Value.str current then (g.priorIdle + 1, false, "idle")
      else (0, true, "progress")
  let infraFails : Int :=
    match runStatus with
    | some "ok" => 0
    | some "infra" => g.priorInfra + 1
    | _ => g.priorInfra
  let progress := (g.context.get? "progress").getD (.obj [])
  let progress := progress.set "last_signature" (.str current)
  let progress := progress.set "idle_cycles_since_progress" (.num idleCycles 0)
  let progress := progress.set "infra_fails_since_ok" (.num infraFails 0)
  let progress := progress.set "last_checked_at" (.str now)
  let progress :=
    if changed then progress.set "last_progress_at" (.str now) else progress
  let newContext := g.context.set "progress" progress
  let newContext :=
    if runStatus == some "ok" then
      match newContext.get? "handoff" with
      | some (.obj hs) =>
        if (Json.Value.obj hs).get? "pending_cycle" |>.isSome then
          newContext.set "handoff"
            ((Json.Value.obj hs).set "pending_cycle" (.bool false))
        else newContext
      | _ => newContext
    else newContext
  let (threshold, _) := Predicates.stopThreshold newContext
    "stop_after_idle_cycles" defaultStopAfterIdleCycles true
  let (infraThreshold, _) := Predicates.stopThreshold newContext
    "stop_after_infra_fails" defaultStopAfterInfraFails false
  let payload : Json.Value := .obj [
    ("progress_changed", .bool changed),
    ("change_kind", .str changeKind),
    ("idle_cycles_since_progress", .num idleCycles 0),
    ("stop_after_idle_cycles", .num threshold 0),
    ("should_stop_for_idle", .bool (idleCycles ≥ threshold)),
    ("run_status", (runStatus.map Json.Value.str).getD .null),
    ("infra_fails_since_ok", .num infraFails 0),
    ("stop_after_infra_fails", .num infraThreshold 0),
    ("should_stop_for_infra", .bool (infraFails ≥ infraThreshold))
  ]
  { newContext, payload }

/-! ## raise-loop-gates(state.py `cmd_raise_loop_gates` L2179–2428) -/

structure RaiseInputs where
  /-- `should_stop_payload(ctx)` の payload(`Predicates.shouldStopPayload`)。 -/
  stopPayload : Json.Value
  /-- `completion_state(ctx)` の payload(`Predicates.completionPayload`)。 -/
  completion : Json.Value
  todo : RawFile
  recommendations : RawFile
  /-- gate ごとの (compact スタンプ, uuid4().hex[:4] 相当)。最大 4 gate。 -/
  ids : List (String × String)
  /-- `now_local()`(created_at / reflection at)。 -/
  now : String

structure RaiseOutcome where
  /-- 書き戻す recommendations.json(raise が無ければ none = 書かない)。 -/
  newRecs : Option Json.Value
  /-- reflection.jsonl へ追記する loop_gate レコード(同上)。 -/
  reflection : Option Json.Value
  /-- stdout ペイロード。 -/
  payload : Json.Value

private def truthyAt (payload : Json.Value) (k : String) : Bool :=
  ((payload.get? k).getD .null).truthy

private def intAt (payload : Json.Value) (k : String) : Int :=
  ((payload.get? k).bind pyInt?).getD 0

private def rawAt (payload : Json.Value) (k : String) : Json.Value :=
  (payload.get? k).getD .null

/-- gate Recommendation の組み立て(Python `gate_rec` — キー順まで同一)。 -/
private def gateRec (id created : String) (kind target reason : String)
    (details : Json.Value) : Json.Value :=
  .obj [
    ("id", .str id),
    ("type", .str "Human-input Recommendation"),
    ("status", .str "proposed"),
    ("raised_by", .str "mercator-loop"),
    ("gate", .str kind),
    ("target", .str target),
    ("reason", .str reason),
    ("details", details),
    ("requires_human_approval", .bool true),
    ("agent_action", .str "stop_until_human_review"),
    ("created_at", .str created)
  ]

/-- `cmd_raise_loop_gates` の決定核(§13.4、I-017)。全域である — cycle の
finalize はこの遷移を通るので、壊れた `gate` フィールド 1 つでハードエラーに
なると checkpoint commit まで到達できず、次 cycle も I-014 で拒否される恒久
デッドロックになる。 -/
def raiseLoopGatesCore (i : RaiseInputs) : RaiseOutcome := Id.run do
  let sp := i.stopPayload
  -- I-021: state_unreadable なら recommendations.json を再構築せず skip
  if (rawAt sp "state_unreadable").truthy then
    return {
      newRecs := none, reflection := none,
      payload := .obj [
        ("raised", .arr []),
        ("gates", .arr []),
        ("skipped", .str "state_unreadable"),
        ("state_unreadable", rawAt sp "state_unreadable")] }
  let completion := i.completion
  let (todo, _) := readJsonOrEmpty "todo.json" i.todo
  let items := objectItems ((todo.get? "items").getD (.arr []))
  -- runnable は phase 依存(§19.3)
  let phase := ((completion.get? "phase").bind (·.asStr?)).getD defaultPhase
  let runnable := items.filter (Predicates.todoIsRunnable · phase)
  let (recs, _) := readJsonOrEmpty "recommendations.json" i.recommendations
  let (recItems, itemsWasList) := match recs.get? "items" with
    | some (.arr xs) => (xs, true)
    | _ => (([] : List Json.Value), false)
  let recs := if itemsWasList then recs else recs.set "items" (.arr [])
  -- open_gates: `gate` は gate 種別の名前なので、文字列でない値はどの種別も
  -- 名指ししていない = 冪等性(§13.4-7)の観点では不在として読む。壊れた値を
  -- 遷移の失敗にしてはならない(頭注のデッドロック)。
  let openGates := (((objectItems (.arr recItems)).filter fun r =>
    r.get? "status" == some (.str "proposed")
      && r.get? "raised_by" == some (.str "mercator-loop")).filterMap
    fun r => (r.get? "gate").bind (·.asStr?)).eraseDups
  let hasGate (k : String) : Bool := openGates.contains k
  -- Agent が既に可視化した停止条件は重複マテリアライズしない(§13.4-2)。
  -- ファイル事実系の停止(essence_missing / essence_placeholder /
  -- essence_structure / essence_asset_integrity / essence_unreviewed_change)は
  -- should-stop が直接検出し可視性は第 2・第 3 層が担うので、gate Recommendation
  -- を重ねない。
  -- `essence_asset_integrity` を落とすと、ESSENCE.md ⇄ essences/ 不整合が単独で
  -- 立っている cycle で idle 等の偽 gate が実体化され、人間は不整合修正に加えて
  -- 不要な `--resolve` まで求められていた(2026-07-27 修正)。**この集合に
  -- disk-fact 型の理由を足し忘れると同じ偽ゲート実体化バグが再発する** —
  -- `essence_structure`(§13.1-15)も同型なのでここに載せる。
  let alreadyVisible := truthyAt sp "essence_missing"
    || truthyAt sp "essence_placeholder"
    || truthyAt sp "essence_structure"
    || truthyAt sp "essence_asset_integrity"
    || truthyAt sp "essence_unreviewed_change"
    || truthyAt sp "essence_blockers"
    || truthyAt sp "blocking_recommendations"
    || truthyAt sp "human_requests"
  let idAt (n : Nat) : String :=
    let (stamp, suffix) := ((i.ids.drop n).headD ("", ""))
    s!"R-LG-{stamp}-{suffix}"
  let statusClosed (t : Json.Value) : Bool :=
    t.get? "status" == some (.str "done")
      || t.get? "status" == some (.str "canceled")
  -- §13.4-6 / §13.1-13: must 境界の phase-approval gate
  let mut raised : List Json.Value := []
  if truthyAt completion "awaiting_phase_approval" && !alreadyVisible
      && !hasGate "must_complete_awaiting_phase_approval" then
    let pendingShoulds := (items.filter fun t =>
      t.get? "priority" == some (.str "should") && !statusClosed t).map fun t =>
      Json.Value.obj [
        ("id", rawAt t "id"),
        ("status", rawAt t "status"),
        ("title", rawAt t "title")]
    let reason := "All must-priority Todos are done (a reviewable checkpoint, not the "
      ++ "terminus, §19.3). Advancing to the should phase is a human budget / "
      ++ "priority decision: `just resume` approves it (sets phase = "
      ++ "extended_approved and makes should Todos runnable); not re-running "
      ++ "the loop ends the project here. Editing ESSENCE.md is needed only "
      ++ "to change the requirements themselves."
    raised := raised ++ [gateRec (idAt raised.length) i.now
      "must_complete_awaiting_phase_approval" "todo.json" reason
      (.obj [
        ("must_done", rawAt completion "must_done"),
        ("must_total", rawAt completion "must_total"),
        ("pending_shoulds", .arr pendingShoulds)])]
  -- §13.4-3: no_runnable_todos(must 境界と projection drift では抑制)
  if !truthyAt completion "should_complete"
      && !truthyAt completion "must_phase_complete" && !alreadyVisible then
    if !items.isEmpty && runnable.isEmpty
        && !truthyAt completion "essence_projection_drift"
        && !hasGate "no_runnable_todos" then
      let openTodos := (items.filter (fun t => !statusClosed t)).map fun t =>
        Json.Value.obj [
          ("id", rawAt t "id"),
          ("status", rawAt t "status"),
          ("executor", match t.get? "executor" with
            | some (.obj es) => ((Json.Value.obj es).get? "mode").getD .null
            | _ => .null),
          ("blocked_reason", rawAt t "blocked_reason")]
      let reason :=
        if intAt completion "must_total" == 0 then
          "No runnable Todo remains and the projection has no "
            ++ "must-priority Todos, so completion cannot be decided "
            ++ "mechanically (§19.3). A human must grade Todo priorities "
            ++ "or update ESSENCE.md before the loop can continue."
        else
          "No runnable Todo remains (every remaining Todo is "
            ++ "blocked, canceled, or assigned to a human executor) but "
            ++ "must-priority Todos are not all done. A human decision "
            ++ "is required to unblock the work."
      raised := raised ++ [gateRec (idAt raised.length) i.now
        "no_runnable_todos" "todo.json" reason
        (.obj [("todos", .arr openTodos)])]
  -- §13.4-4: idle_cycles は must 境界から独立(completion / 可視化ガード内)
  let idleCycles := intAt sp "idle_cycles_since_progress"
  let idleThreshold := intAt sp "stop_after_idle_cycles"
  if !truthyAt completion "should_complete" && !alreadyVisible
      && idleCycles ≥ idleThreshold && !hasGate "idle_cycles" then
    let reason := s!"The loop made no semantic progress for "
      ++ s!"{idleCycles} consecutive cycles "
      ++ s!"(threshold {idleThreshold}). A human "
      ++ "should inspect recent runs.jsonl / reflection.jsonl entries, "
      ++ "address the cause, and resume."
    raised := raised ++ [gateRec (idAt raised.length) i.now
      "idle_cycles" "context.json" reason
      (.obj [
        ("idle_cycles_since_progress", rawAt sp "idle_cycles_since_progress"),
        ("stop_after_idle_cycles", rawAt sp "stop_after_idle_cycles")])]
  -- §13.1-12: infra_unreachable は completion / 可視化ガードの外
  let infraFails := intAt sp "infra_fails_since_ok"
  let infraThreshold := intAt sp "stop_after_infra_fails"
  if infraFails ≥ infraThreshold && !hasGate "infra_unreachable" then
    let reason := s!"claude failed to run for {infraFails} "
      ++ "consecutive cycles due to an infra problem (API connection / rate "
      ++ s!"limit / auth / Claude-side error; threshold "
      ++ s!"{infraThreshold}). The loop cannot make "
      ++ "progress while Claude is unreachable. A human should verify API "
      ++ "reachability and authentication (`claude auth status`), then resume."
    raised := raised ++ [gateRec (idAt raised.length) i.now
      "infra_unreachable" "context.json" reason
      (.obj [
        ("infra_fails_since_ok", rawAt sp "infra_fails_since_ok"),
        ("stop_after_infra_fails", rawAt sp "stop_after_infra_fails")])]
  let raisedIds := raised.map (rawAt · "id")
  let raisedKinds := raised.map fun r => ((r.get? "gate").bind (·.asStr?)).getD ""
  let (newRecs, reflection) :=
    if raised.isEmpty then (none, none)
    else
      let recs := setdefault recs "schema_version" (.str schemaVersion)
      let recs := recs.set "items" (.arr (recItems ++ raised))
      let reflection : Json.Value := .obj [
        ("at", .str i.now),
        ("type", .str "loop_gate"),
        ("summary", .str ("mercator-loop materialized stop gate(s): "
          ++ String.intercalate ", " raisedKinds)),
        ("recommendations", .arr raisedIds)]
      (some recs, some reflection)
  let allGates := (openGates ++ raisedKinds).eraseDups.mergeSort (· ≤ ·)
  let payload : Json.Value := .obj [
    ("raised", .arr raisedIds),
    ("gates", .arr (raisedKinds.map Json.Value.str)),
    ("open_gates", .arr (allGates.map Json.Value.str))]
  pure { newRecs, reflection, payload }

/-! ## run lifecycle(state.py `cmd_start_run` / `cmd_end_run` L2467–2523) -/

/-- `cmd_start_run` の I-021 ゲート(欠落は IO 側)。`.error` は die 文言。 -/
def startRunGate (projectRaw : RawFile) : Except String Json.Value := do
  let (project, diag) := readJsonOrEmpty "project.json" projectRaw
  if let some d := diag then
    throw (s!"project.json is unreadable ({d}); repair it (git restore) "
      ++ "instead of letting start-run rebuild it.")
  pure project

structure StartRunOutcome where
  /-- runs.jsonl / control_runs.jsonl へ追記するレコード。 -/
  record : Json.Value
  newProject : Json.Value

/-- `cmd_start_run` の適用部(レコードのキー順・project.json の setdefault
順序まで Python と同一)。 -/
def startRunApply (project : Json.Value) (runId now cwd title : String) :
    StartRunOutcome :=
  let record : Json.Value := .obj [
    ("at", .str now),
    ("run_id", .str runId),
    ("event", .str "start"),
    ("agent", .str "Over-Project Agent"),
    ("cwd", .str cwd),
    ("project", .str title)]
  let p := setdefault project "schema_version" (.str schemaVersion)
  let p := setdefault p "id" (.str "P-001")
  let p := setdefault p "title" (.str title)
  let p := setdefault p "status" (.str "active")
  let p := p.set "last_run_id" (.str runId)
  { record, newProject := p }

/-- `cmd_end_run` のレコード(`args.status or "unknown"` — 空文字も
unknown)。stdout はこのレコードの `json.dumps` 1 行。 -/
def endRunRecord (runId : String) (status? : Option String) (now title : String) :
    Json.Value :=
  let status := match status? with
    | some s => if s.isEmpty then "unknown" else s
    | none => "unknown"
  .obj [
    ("at", .str now),
    ("run_id", .str runId),
    ("event", .str "end"),
    ("status", .str status),
    ("project", .str title)]

/-! ## reset-context(state.py `cmd_reset_context` L2526–2564) -/

/-- `cmd_reset_context` の I-021 ゲート(欠落は IO 側)。`.error` は die 文言。 -/
def resetContextGate (contextRaw : RawFile) : Except String Json.Value := do
  let (context, diag) := readJsonOrEmpty "context.json" contextRaw
  if let some d := diag then
    throw (s!"context.json is unreadable ({d}); repair it (git restore) "
      ++ "before resetting context.")
  pure context

structure ResetOutcome where
  newContext : Json.Value
  reflection : Json.Value
  payload : Json.Value

/-- `cmd_reset_context` の適用部: カウンタのゼロ化(キー順・
`context_usage_estimate: 0.0` の float 表現まで Python と同一)+
handoff.written_at。`.error` は handoff が object でない場合の Python
TypeError(`context.setdefault("handoff", ...)["written_at"] = ...`)=
ハードエラーチャネル。 -/
def resetContextApply (context : Json.Value) (now : String) :
    Except String ResetOutcome := do
  let context := setdefault context "schema_version" (.str schemaVersion)
  let counters : Json.Value := .obj [
    ("context_usage_estimate", .num 0 1),
    ("failed_attempts_since_reset", .num 0 0),
    ("changed_files_since_reset", .num 0 0),
    ("completed_todos_since_reset", .num 0 0),
    ("important_decisions_since_reset", .num 0 0),
    ("major_spec_rewrite_since_reset", .bool false),
    ("high_risk_change_completed", .bool false)]
  let context := context.set "counters" counters
  let handoff ← match context.get? "handoff" with
    | none => pure (Json.Value.obj [])
    | some (.obj es) => pure (Json.Value.obj es)
    | some _ => throw "context.json handoff does not support item assignment (not an object)"
  let context := context.set "handoff" (handoff.set "written_at" (.str now))
  pure {
    newContext := context
    reflection := .obj [
      ("at", .str now),
      ("type", .str "context_reset"),
      ("summary", .str "Context reset executed; counters zeroed.")]
    payload := .obj [("reset", .bool true)] }

/-! ## コンパイル時テスト -/

-- normalize: 揮発キー除去 + 全階層キーソート + 配列は順序維持
#guard stableJsonString (.obj [
  ("b", .num 1 0),
  ("summary", .str "volatile"),
  ("a", .obj [("z", .null), ("written_at", .str "x"), ("k", .arr [.num 2 0, .num 1 0])])
]) == "{\"a\":{\"k\":[2,1],\"z\":null},\"b\":1}"

-- record-progress: baseline → idle → progress の遷移
#guard
  let gate : RecordGate := {
    context := .obj [("progress", .obj [])], priorIdle := 0, priorInfra := 0,
    previous := none }
  (recordProgressApply gate "sig" none "t").payload.get? "change_kind"
    == some (.str "baseline")
#guard
  let gate : RecordGate := {
    context := .obj [("progress", .obj [])], priorIdle := 1, priorInfra := 0,
    previous := some (.str "sig") }
  let p := (recordProgressApply gate "sig" (some "ok") "t").payload
  p.get? "idle_cycles_since_progress" == some (.num 2 0)
    && p.get? "should_stop_for_idle" == some (.bool false)
    && p.get? "infra_fails_since_ok" == some (.num 0 0)
#guard
  let gate : RecordGate := {
    context := .obj [("progress", .obj [])], priorIdle := 4, priorInfra := 1,
    previous := some (.str "old") }
  let p := (recordProgressApply gate "new" (some "infra") "t").payload
  p.get? "change_kind" == some (.str "progress")
    && p.get? "idle_cycles_since_progress" == some (.num 0 0)
    && p.get? "infra_fails_since_ok" == some (.num 2 0)
    && p.get? "should_stop_for_infra" == some (.bool true)

-- record-progress: resume note の消費は --run-status ok の cycle 終端だけ
-- (§19.3 — infra は保持、フラグ無し handoff は再構築しない)
#guard
  let gate : RecordGate := {
    context := .obj [("progress", .obj []),
      ("handoff", .obj [("summary", .str "Human resume: go"),
        ("pending_cycle", .bool true)])],
    priorIdle := 0, priorInfra := 0, previous := none }
  ((recordProgressApply gate "sig" (some "ok") "t").newContext.getPath?
    ["handoff", "pending_cycle"]) == some (.bool false)
#guard
  let gate : RecordGate := {
    context := .obj [("progress", .obj []),
      ("handoff", .obj [("pending_cycle", .bool true)])],
    priorIdle := 0, priorInfra := 0, previous := none }
  ((recordProgressApply gate "sig" (some "infra") "t").newContext.getPath?
    ["handoff", "pending_cycle"]) == some (.bool true)
#guard
  let gate : RecordGate := {
    context := .obj [("progress", .obj []),
      ("handoff", .obj [("pending_cycle", .bool true)])],
    priorIdle := 0, priorInfra := 0, previous := none }
  ((recordProgressApply gate "sig" none "t").newContext.getPath?
    ["handoff", "pending_cycle"]) == some (.bool true)
#guard
  let gate : RecordGate := {
    context := .obj [("progress", .obj []), ("handoff", .obj [])],
    priorIdle := 0, priorInfra := 0, previous := none }
  ((recordProgressApply gate "sig" (some "ok") "t").newContext.get? "handoff")
    == some (.obj [])

-- reset-context: counters の float 0.0 と handoff TypeError
#guard
  match resetContextApply (.obj []) "t" with
  | .ok o =>
    ((o.newContext.get? "counters").bind (·.get? "context_usage_estimate"))
      == some (.num 0 1)
  | .error _ => false
#guard
  match resetContextApply (.obj [("handoff", .str "x")]) "t" with
  | .error _ => true
  | .ok _ => false

-- end-run: 空 status は unknown
#guard (endRunRecord "R-1" (some "") "t" "p").get? "status" == some (.str "unknown")
#guard (endRunRecord "R-1" (some "crashed") "t" "p").get? "status"
  == some (.str "crashed")

end Mercator.State.Loop
