import Mercator.Core.Json
import Mercator.Core.Text
import Mercator.State.Model
import Mercator.State.Predicates
import Mercator.State.Loop
import Mercator.State.Validate

/-!
`Mercator.State.Resume` — `state.py cmd_resume`(L2767–3074)の純粋決定核。

resume は唯一の human re-entry 遷移(§13.3、I-011 — pre_tool_guard が agent に
deny する human-only コマンド)。停止ゲートの解放(gate_release)と、何も
latch されていない中間更新の記録(steering)の両モードを持ち、いずれも
control-plane attestation ledger へ ESSENCE.md の SHA-256 を追記する
(§13.1-10 — should-stop が信頼する唯一の review 記録)。

段階は Python と同一の 4 層:
1. 前提(§13.3 0→1): state 初期化 → ESSENCE.md 実在 → placeholder 拒否
2. I-021: runs.jsonl 読取不能は「in-flight 不明」として --force でも拒否、
   in-flight run は --force なしで拒否
3. pre 評価: `should_stop_payload` の state_unreadable は書き込み前に拒否
   (resume は blockers/recommendations/context を書き換えるため、読めない
   ファイルからの再構築を絶対にしない)
4. 遷移本体: mode 決定 → noop 判定 → 解決・カウンタゼロ化・handoff 差し替え
   → reflection / attestation レコード(`Plan` として書き込み列を返し、
   IO シェルが 3 手で適用する — §3.3-3)

crash recovery(§13.5): --force は start-without-end の全 run を
`aborted_by_resume` で閉じる(最新だけではない — 次の resume が再び拒否
しないため)。
-/

namespace Mercator.State.Resume

open Mercator.Core
open Mercator.State
open Mercator.State.Model

/-- Python `refuse_resume`(L2767): 単行 JSON + exit 1。 -/
def refusePayload (error : String) : Json.Value :=
  .obj [("resumed", .bool false), ("mode", .str "refused"), ("error", .str error)]

/-- `cmd_resume` の前提検査(L2794–2813)。順序は §13.3(0 → 1)。
`.error` は placeholder 判定の不正 UTF-8(Python の uncaught
UnicodeDecodeError = exit 2)。「実在するが読めない」ESSENCE.md は Python の
`essence_is_placeholder` が OSError を False に落とすのと同じく素通りし、
後段の sha256 読みでハードエラーになる。見出し契約違反(§2.1.1'・§13.1-15)と
essences/ の双方向不整合(§2.1.5)も前提側の**絶対拒否** — `--resolve` でも
steering でも回避できない。resume は壊れた Essence を attest してはならない。 -/
def preconditionError? (stateInitialized : Bool) (stateDir : String)
    (essence : EssenceRead) (assets : EssencesRead) :
    Except String (Option String) := do
  if !stateInitialized then
    return some (s!"project state is not initialized ({stateDir} missing); "
      ++ "run `just init` (or `just bootstrap`) first.")
  if let .absent := essence then
    return some "ESSENCE.md does not exist; the human must write it before resuming."
  if ← Predicates.essenceIsPlaceholder essence then
    return some ("ESSENCE.md is still the Mercator placeholder (empty, the guide "
      ++ "block, or an unfilled '<!-- FILL:' section marker remains, "
      ++ "§13.1-8); replace it with the real Essence before resuming.")
  let structureIssues := Predicates.essenceStructureIssues essence
  if !structureIssues.isEmpty then
    return some ("ESSENCE.md heading structure violates the canonical section "
      ++ "contract (" ++ String.intercalate "; " structureIssues
      ++ "); restructure it before resuming (§2.1.1) — resume must not attest "
      ++ "a malformed Essence.")
  let assetIssues := Predicates.essenceAssetIssues essence assets
  if !assetIssues.isEmpty then
    return some ("ESSENCE.md and essences/ are out of sync ("
      ++ String.intercalate "; " assetIssues
      ++ "); align them before resuming (§2.1.5) — resume must not attest "
      ++ "an inconsistent Essence.")
  return none

/-- Python `unfinished_run_ids`(L2594): start に対応する end の無い run_id を
古い順に。dict 挿入順の意味論を写す — 既存 start の再出現は位置を保ち、
end で除去された後の再 start は末尾へ入る。falsy な run_id はスキップ。
非 dict レコードは Python の `record.get` AttributeError(exit 2)、truthy な
非 hashable run_id(list/dict)は dict キー化の TypeError(exit 2)に対応する
`.error`。読取不能(破損 JSONL)は診断として返す(I-021 — 呼び出し側が
「不明」として拒否する)。 -/
def unfinishedRunIds (runsRaw : RawFile) :
    Except String (List Json.Value × List String) := do
  let (records, diag) := readJsonlOrEmpty "runs.jsonl" runsRaw
  let mut openRuns : List Json.Value := []
  for r in records do
    if !(r matches .obj _) then
      throw "runs.jsonl record is not an object (cannot read run_id)"
    let runId := (r.get? "run_id").getD .null
    if !runId.truthy then
      continue
    if (runId matches .arr _) || (runId matches .obj _) then
      throw "runs.jsonl run_id is unhashable"
    if r.get? "event" == some (.str "start") then
      if !openRuns.contains runId then
        openRuns := openRuns ++ [runId]
    else if r.get? "event" == some (.str "end") then
      openRuns := openRuns.filter (· != runId)
  return (openRuns, diag.toList)

/-- L2826: 読めない runs.jsonl は「in-flight を証明できない」— --force でも
拒否(I-021)。 -/
def runsUnreadableError (diags : List String) : String :=
  "runs.jsonl is unreadable (" ++ String.intercalate "; " diags
    ++ "); cannot prove no loop is in flight. Repair the file first "
    ++ "(restore it from the last checkpoint commit with `git restore`, "
    ++ "or remove the truncated trailing line), then re-run resume."

/-- L2833–2839: in-flight run の拒否文言。`", ".join` は Python と同じく
非文字列 id で TypeError(exit 2)。 -/
def inFlightError (inFlight : List Json.Value) : Except String String := do
  let ids ← inFlight.mapM fun
    | .str s => pure s
    | _ => throw "sequence item in run-id join: expected str instance"
  return "run(s) " ++ String.intercalate ", " ids
    ++ " look in-flight (start without end "
    ++ "in runs.jsonl); resuming under a running loop would race it. If "
    ++ "the loop is not running (crashed or killed mid-cycle), re-run "
    ++ "with --force."

/-- L2845–2855: pre 評価の `state_unreadable` 非空は書き込み前に拒否 —
resume は blockers/recommendations/context を書き換えるため、読めない読みから
の再構築は破損の静かな上書きになる(I-021)。 -/
def stateUnreadableError? (stopPayload : Json.Value) : Option String :=
  match stopPayload.get? "state_unreadable" with
  | some (.arr items@(_ :: _)) =>
    let diags := items.filterMap fun | Json.Value.str s => some s | _ => none
    some ("canonical state is unreadable ("
      ++ String.intercalate "; " diags
      ++ "); repair the file first (restore it from the last checkpoint "
      ++ "commit with `git restore`, or fix the truncated line), then "
      ++ "re-run resume.")
  | _ => none

/-- Python `git_worktree_changes` のパース部(L2591):
`sorted({line[3:] for line in stdout.splitlines() if len(line) > 3})`。
`project_worktree_changes` と違い引用剥ぎ・prefix 剥ぎ・strip を行わない
生の porcelain パス(git root 相対)。 -/
def gitStatusPaths (porcelain : String) : List String :=
  let paths := (Text.splitLinesPy porcelain).foldl (init := []) fun acc line =>
    if line.length ≤ 3 then acc
    else
      let path := String.ofList (line.toList.drop 3)
      if acc.contains path then acc else path :: acc
  paths.mergeSort (· ≤ ·)

/-- `_resume_transition` の観測一式(最初の書き込み前に全部読む — mode 決定と
reflection が「この遷移自身の副作用ではなく人間の状態」を記述するため、
L2841–2843)。 -/
structure TransitionInputs where
  /-- pre 評価の `should_stop_payload`(state_unreadable 検査済み)。 -/
  stopPayload : Json.Value
  blockersRaw : RawFile
  recsRaw : RawFile
  contextRaw : RawFile
  /-- essence_projection_drift(L1623)用の spec.json。 -/
  specRaw : RawFile
  /-- supervise authorizing gate 判定(§13.3-4'')用の todo.json。既定 .absent
  は「authorizing gate なし」に落ちる — preflight も同じ状態では refuse する
  ので、守るべき binding が存在しないことと同値(fail-open ではない)。 -/
  todoRaw : RawFile := .absent
  /-- `sha256_file(ctx.essence)`(前提検査済みなので通常 some)。 -/
  essenceSha : Option String
  /-- essences/ の現況マニフェスト(§2.1.5、attestation に essences として
  記録される — §13.1-10 拡張)。 -/
  essencesManifest : List (String × String) := []
  inFlight : List Json.Value
  force : Bool
  noteArg : Option String
  /-- 人間がこの遷移で解決すると明示した Recommendation / Blocker ID。 -/
  resolveIds : List String := []
  /-- 人間が supervise authorizing gate の**承認撤回**を明示した Recommendation
  ID(§13.3-4''): `--resolve` は unfinished High-Risk Todo の authorizing gate
  を拒否する(閉じると `just supervise` の preflight が恒久に通らなくなる —
  2026-08-04 の実障害)ため、意図的な撤回だけがこの明示フラグで閉じられる。 -/
  retractIds : List String := []
  /-- must 境界の明示判断: `approve_should` / `close_at_must`。 -/
  phaseDecision : Option String := none
  /-- 「ゲートを 1 件も解除しない。人間所有入力の編集だけを attestation して
  checkpoint する」という明示の意図表明(§13.3-4''')。

  open gate があるときの素の resume を拒否する規則(下の `forcing` 分岐)の
  目的は**過剰解除の防止**だが、空の `--resolve` は何も解除しないため、その
  拒否は目的に寄与しない一方で **steering(§13.3 冒頭が定義する途中修正の
  checkpoint)という別の正当な遷移を表現不能にしていた**。§19.3 が指示する
  手順(must 境界で要求を追加 → ESSENCE.md 編集 → steering checkpoint →
  loop)は、境界で実体化された phase gate が open のまま残るため必ずこの
  拒否に着弾する(2026-08-05 の実障害)。

  拒否条件を緩めるのではなく**意図を表明する手段**を足すことで、fail-closed
  の本旨(暗黙の一括解除の禁止)を保ったまま表現力を回復する。`--resolve` /
  `--retract-approval` / phase 判断との同時指定は意図の混線として拒否し、
  遷移核も独立に選択集合を空へ倒す(S-T7)。 -/
  steerOnly : Bool := false
  /-- `git_worktree_changes`: none = git 不在・非リポジトリ(「不明」であって
  clean ではない — noop 判定は `some []` のみ)。 -/
  worktree : Option (List String)
  now : String
  title : String
  /-- `os.path.relpath(project_root, CONTROL_ROOT)`(attestation 用)。 -/
  projectRootRel : String

/-- proceed 時の書き込み列。IO シェルは Python と同じ順に適用する:
end レコード(runs + control_runs)→ blockers → recommendations → context →
reflection → attestation → post 評価 → stdout。 -/
structure Plan where
  mode : String
  note : String
  /-- crash recovery の end レコード(runs.jsonl と control_runs.jsonl の
  両方へ 1 レコードずつ追記する)。 -/
  runRecords : List Json.Value
  newBlockers : Option Json.Value
  newRecs : Option Json.Value
  newContext : Json.Value
  reflection : Json.Value
  attestation : Json.Value
  resolvedBlockers : List Json.Value
  resolvedRecommendations : List Json.Value
  approvesShouldPhase : Bool
  closesAtMust : Bool
  idleCleared : Int
  drift : Bool
  worktree : Option (List String)
  closedRuns : List Json.Value

inductive Transition where
  /-- L2910–2928: 何も解放せず何も記録しない(exit 0、書き込みなし)。 -/
  | noop (payload : Json.Value)
  | proceed (plan : Plan)

private def optListJson : Option (List String) → Json.Value
  | none => .null
  | some xs => .arr (xs.map .str)

private def isOpenBlocker (b : Json.Value) : Bool :=
  b.get? "status" == some (.str "active")
    && b.get? "type" == some (.str "essence_blocking")

private def isOpenRec (r : Json.Value) : Bool :=
  (r.get? "type" == some (.str "Blocking Recommendation")
      && r.get? "status" == some (.str "proposed"))
    || Predicates.recommendationRequiresHuman r

/-- open な framework phase gate。gate/raised_by の形の判定は
`Predicates.isPhaseGateRecommendation` の**単一定義**を使う — 停止 message の
`--resolve` 案内(§13.4-2)が同じ述語で「`--resolve` では解除できない gate」を
除外するため、ここで綴りを複製すると案内と受理集合がずれる。 -/
private def isPhaseGateRec (r : Json.Value) : Bool :=
  isOpenRec r && Predicates.isPhaseGateRecommendation r

/-- item の id(非文字列 id は「選択されない」に落ちる)。S-T7 が選択集合の
filter 述語をこの名前で分解するため public(§3.3 — 可視性の変更は挙動を
変えない)。 -/
def itemId? (v : Json.Value) : Option String :=
  match v.get? "id" with
  | some (.str id) => some id
  | _ => none

private def duplicateStrings (xs : List String) : List String :=
  (xs.filter fun x => (xs.filter (· == x)).length > 1).eraseDups

/-- Framework-observed must/should boundary. Kept as one executable predicate
so resume validation, transition semantics, and S-T4 prove the same fact.

**唯一の権威は `stopPayload` の直接述語** `must_complete_awaiting_phase_approval`
であり、これは `shouldStopPayload` が現在の todo.json / context.phase から
**再計算**した実状態(mustPhaseComplete ∧ phase == must)である。

以前はこれに加えて「`gate`/`raised_by` フィールドを持つ open Recommendation」を
境界の代替根拠にしていたが、両フィールドは agent が `apply-projection` で書ける
ため、must 未完了(direct = false)でも `raised_by: "mercator-loop"` を詐称した
rec を置けば `--approve-should` が should phase の自律予算を奪取できた
(§13.3-4' / §21.5-1 / §19.3 破れ、2026-07-27 修正)。direct 述語は crash-window
(raise-loop-gates 実体化前)も含めて実境界を捉えるため、rec ベースの分岐は
冗長かつ危険であり撤去する。gate rec の**選択**(どの rec を resolved にするか)
には `isPhaseGateRec` を引き続き使うが、それは phase 昇格の**認可**には効かない。 -/
def hasFrameworkPhaseGate (stopPayload : Json.Value) (_recsRaw : RawFile) : Bool :=
  ((stopPayload.get? "must_complete_awaiting_phase_approval").getD .null).truthy

/-- ID 単位 resume の前提。open item があるときの resolve-all 既定を廃止し、
指定漏れは拒否する。phase gate は通常の `--resolve` だけでは解除できず、
`--approve-should` / `--close-at-must` の明示判断を要求する。

supervise authorizing gate(§13.3-4''、`Predicates.superviseAuthorizedTodo?`
の単一定義)は resume にとって二重に特別である:
1. `--resolve` を**拒否**する — unfinished High-Risk Todo の authorizing
   Recommendation を閉じると supervise preflight の open gate 要件が恒久に
   満たせなくなる(2026-08-04 の実障害: 承認時に resolve された R-001 が
   `just supervise` を『not an open human approval gate』で座礁させた)。
   閉じてよいのは (a) supervise 完了で Todo が unfinished でなくなった後の
   通常 `--resolve`、(b) 明示の承認撤回 `--retract-approval` のみ。
2. 素の resume を**強制しない** — この gate の「答え」は resolve ではなく
   supervise の実行なので、「open gate があるのに --resolve が無い」拒否の
   母集合から除外する。除外しないと、gate を open に保ったまま途中 checkpoint
   を記録する正規の手順(承認→ Essence 手直し→ resume →supervise)が
   デッドロックし、人間は承認を resolve で潰すしかなくなる(同実障害の根)。
撤回路 (b) があるため、陳腐化 gate の完全デッドロック(2026-07-28 の教訓、
下の stale phase gate と同型)はこの gate 種では構造的に起きない。

`--steer-only`(§13.3-4''')は最後の分岐の**意図表明版の免除**である: 何も
解除しないことを人間が明示した resume は、open gate があっても受理される。
他の選択フラグとの同時指定は意図の混線として拒否する。 -/
def selectionError? (i : TransitionInputs) : Option String :=
  let (blockers, _) := readJsonOrEmpty "blockers.json" i.blockersRaw
  let blockerItems := objectItems ((blockers.get? "items").getD (.arr []))
  let openBlockers := blockerItems.filter isOpenBlocker
  let (recs, _) := readJsonOrEmpty "recommendations.json" i.recsRaw
  let recItems := objectItems ((recs.get? "items").getD (.arr []))
  let openRecs := recItems.filter isOpenRec
  let openIds := (openBlockers ++ openRecs).filterMap itemId?
  let selected := i.resolveIds ++ i.retractIds
  let duplicate := duplicateStrings selected
  let unknown := selected.filter fun id => !openIds.contains id
  let (todo, _) := readJsonOrEmpty "todo.json" i.todoRaw
  let todoItems := objectItems ((todo.get? "items").getD (.arr []))
  let authorizations := Predicates.superviseAuthorizations openRecs todoItems
  let authorizedIds := authorizations.map (·.1)
  let resolvedAuthorizing := i.resolveIds.filter authorizedIds.contains
  let retractsNothing := i.retractIds.filter fun id => !authorizedIds.contains id
  let phaseIds := (openRecs.filter isPhaseGateRec).filterMap itemId?
  let frameworkPhaseGate := hasFrameworkPhaseGate i.stopPayload i.recsRaw
  if i.steerOnly && (!selected.isEmpty || i.phaseDecision.isSome) then
    -- 意図の混線: 「1 件も解除しない」と「この ID を解除する / phase を判断
    -- する」を同時に主張している。どちらを優先しても人間の書いた意図と
    -- 異なる遷移になるため、書き込み前に落とす。
    some ("--steer-only records the human's input edits without touching any "
      ++ "gate, so it cannot be combined with --resolve / --retract-approval "
      ++ "/ --approve-should / --close-at-must; drop --steer-only to make "
      ++ "those decisions, or drop them to record the edits alone")
  else if !duplicate.isEmpty then
    some s!"duplicate --resolve id(s): {String.intercalate ", " duplicate}"
  else if !unknown.isEmpty then
    some s!"--resolve names no currently open gate: {String.intercalate ", " unknown}"
  else if !resolvedAuthorizing.isEmpty then
    let recId := resolvedAuthorizing.headD ""
    let todoId := (authorizations.lookup recId).getD ""
    some (s!"{recId} is the open supervise authorization for unfinished "
      ++ s!"High-Risk Todo {todoId} (§12.1); resolving it now would leave "
      ++ s!"`just supervise --todo {todoId} --recommendation {recId}` "
      ++ "permanently refused (its preflight requires an open gate). Run that "
      ++ s!"supervised session first and resolve {recId} after its diff is "
      ++ s!"reviewed, or pass --retract-approval {recId} to withdraw the "
      ++ "approval deliberately.")
  else if !retractsNothing.isEmpty then
    some ("--retract-approval names no open supervise authorization gate: "
      ++ String.intercalate ", " retractsNothing
      ++ " (use --resolve for ordinary gates)")
  else if i.phaseDecision.isSome && !frameworkPhaseGate then
    some "--approve-should/--close-at-must requires an active must phase boundary"
  -- 二択を要求するのは framework が観測した Must 境界が**現に立っている**間
  -- だけである。境界が消えた後も残る陳腐化した phase gate Recommendation
  -- (典型: 境界で人間が ESSENCE.md を編集 → projection drift →
  -- `must_phase_complete = false`。§19.3 がまさにその手順を指示している)を
  -- ここで拒み続けると、`--resolve` も phase flag も no-flag もすべて拒否され、
  -- loop も pre-gate で拒否する **完全なデッドロック**になる(I-017「停止は
  -- 再開手順とともに可視」の破れ)。境界不在時の `--resolve` は「陳腐化した
  -- gate を閉じる」正しい遷移であり、phase 昇格は起こらない — `transition` の
  -- `approvesShouldPhase` / `closesAtMust` が独立に `frameworkPhaseGate` を
  -- 要求するため(S-T4)。条件が残っていれば次 cycle が新しい id で再実体化
  -- する(§21.5-3)。
  else if i.phaseDecision.isNone && frameworkPhaseGate
      && selected.any phaseIds.contains then
    some "a must phase gate requires --approve-should or --close-at-must; --resolve alone is insufficient"
  else
    -- §13.3-4'': authorizing gate は「resolve を待つ」gate ではなく
    -- 「supervise を待つ」gate なので、素の resume を拒否させる母集合から
    -- 除外する。それだけが open のときの素の resume は正規の途中 checkpoint
    -- (steering / gate 温存の記録)として受理される。
    -- §13.3-4''': `--steer-only` は「1 件も解除しない」ことを人間が明示した
    -- 形なので、この拒否の目的(暗黙の一括解除の禁止)に反しない。免除しないと
    -- §19.3 が指示する「要求を足して続行する」手順(ESSENCE.md 編集 →
    -- steering checkpoint)が open gate 下で表現できない(2026-08-05 の実障害)。
    let forcing := openIds.filter fun id => !authorizedIds.contains id
    if selected.isEmpty && i.phaseDecision.isNone && !i.steerOnly
        && !forcing.isEmpty then
      some ("open gates require explicit --resolve <ID>: "
        ++ String.intercalate ", " forcing
        ++ " (or --steer-only to record your input edits without touching "
        ++ "any gate)")
    else
      none

/-- resume が書き込む context の純粋構成(L2987–3010)。S-T6 の証明対象と
して名前付きに分離(§3.3 — 分離は挙動を変えない。共有前段 context0〜
progress0 の再計算は参照透過性により無害)。返り値は
(退避した prior handoff, 新 context)。

- §19.3: `approvesShouldPhase` は should phase の自律予算を付与する
  (要件変更ではない — ESSENCE.md も attestation 状態も触らない)。
- §13.1-12: idle / infra カウンタは無条件にゼロ化する(S-T6)。
- gate release は handoff を reflection へ退避して差し替える。steering は
  loop が mid-flight であり handoff は実 next actions を記述したままなので
  保持する(L2998–3009)。
- §19.3 resume note 未消費ガード: gate release の新 handoff は
  `pending_cycle` を持つ。`--close-at-must` は resume 自身が closure なので
  false(即時の must-scope COMPLETE を妨げない)、それ以外は true —
  note を消費する cycle が 1 回走るまで `full_complete` を封じ、
  record-progress(`--run-status ok`)が下ろす。 -/
def resumedContext (contextRaw : RawFile)
    (approvesShouldPhase closesAtMust gateRelease : Bool)
    (now note : String) : Json.Value × Json.Value :=
  let (context0, _) := readJsonOrEmpty "context.json" contextRaw
  let context1 := Loop.setdefault context0 "progress" (.obj [])
  let progress0 := (context1.get? "progress").getD (.obj [])
  let context2 := Loop.setdefault context1 "schema_version"
    (.str Validate.schemaVersion)
  let context3 :=
    if approvesShouldPhase then
      context2.set "phase" (.str phaseExtendedApproved)
    else if closesAtMust then
      context2.set "phase" (.str phaseClosedAtMust)
    else context2
  let progress1 := (progress0.set "idle_cycles_since_progress" (.num 0 0)).set
    "infra_fails_since_ok" (.num 0 0)
  let context4 := context3.set "progress" progress1
  if gateRelease then
    let prior := (context4.get? "handoff").getD .null
    let prior := if prior.truthy then prior else .obj []
    (prior, context4.set "handoff" (.obj [
      ("written_at", .str now),
      ("summary", .str s!"Human resume: {note}"),
      ("next_actions", .arr []),
      ("open_questions", .arr []),
      ("pending_cycle", .bool !closesAtMust)]))
  else (.null, context4)

/-- `_resume_transition` の決定核(L2841–3048)。前段の拒否(runs 読取不能・
in-flight・state_unreadable)を通過した観測に対しては全域 — Python がこの
区間で落とす経路は存在しない(counters は pre 評価が診断済み、join は
拒否文言のみ)。 -/
def transition (i : TransitionInputs) : Transition :=
  -- mode(L2856–2864): gate release は LATCH された停止の解放。
  -- essence_unreviewed_change はこの遷移自身が attestation で解消する
  -- disk fact なので latch に数えない(steering の導入事由)。
  let reasons := match i.stopPayload.get? "reasons" with
    | some (.arr rs) => rs
    | _ => []
  let latched := reasons.filter (· != Json.Value.str "essence_unreviewed_change")
  -- §13.3-4''': `--steer-only` は何も解除しないので、latch が残っていても
  -- gate release ではない。mode を steering に固定するのは文言の問題ではなく
  -- 意味論である: gate_release は既存 handoff を reflection へ退避して
  -- 「Human resume: {note}」で**置き換える**ため、1 件も解除していない遷移で
  -- それを走らせると、飛行中の実 next actions が理由なく失われる。
  let mode := if i.steerOnly || latched.isEmpty then "steering" else "gate_release"
  let essenceUnreviewed :=
    ((i.stopPayload.get? "essence_unreviewed_change").getD .null).truthy
  -- essence_projection_drift(L1623–1628)
  let (spec, _) := readJsonOrEmpty "spec.json" i.specRaw
  let recorded? := spec.get? "projected_from_essence_sha256"
  let drift := (i.essenceSha.map (!·.isEmpty)).getD false
    && ((recorded?.map (·.truthy)).getD false)
    && recorded? != (i.essenceSha.map Json.Value.str)
  -- L2869–2872: forced resume はクラッシュした全 run を閉じる(§13.5)
  let closedRuns := if !i.inFlight.isEmpty && i.force then i.inFlight else []
  -- 解放対象(L2874–2888)。pre 評価を通過した時点で items は list であることが
  -- 保証されている(gate_items の形状検査が state_unreadable に落とすため)
  let (blockers, _) := readJsonOrEmpty "blockers.json" i.blockersRaw
  let blockerItems := objectItems ((blockers.get? "items").getD (.arr []))
  let openBlockers := blockerItems.filter isOpenBlocker
  let (recs, _) := readJsonOrEmpty "recommendations.json" i.recsRaw
  let recItems := objectItems ((recs.get? "items").getD (.arr []))
  let openRecs := recItems.filter isOpenRec
  -- §13.3-4'': `--retract-approval` は選択面では `--resolve` と同じ「この ID を
  -- resolved にする」明示指定である(拒否と受理の分岐は selectionError? 側 —
  -- 遷移核は phase 認可と同様、選択の意味論だけを持つ)。
  --
  -- §13.3-4''': `--steer-only` の宣言(「1 件も解除しない」)は遷移核でも
  -- 独立に成立させる。selectionError? が同時指定を拒否するが、その preflight を
  -- 迂回した呼び出しでも gate 集合は動かない — 既存の phase 認可
  -- (`hasFrameworkPhaseGate` の独占)と同じ fail-closed の規律であり、S-T7 が
  -- この 2 行に依存して「steer-only resume は status を変更しない」を閉じる。
  let selected := if i.steerOnly then [] else i.resolveIds ++ i.retractIds
  let phaseDecision := if i.steerOnly then none else i.phaseDecision
  let selectedBlockers := openBlockers.filter fun b =>
    (itemId? b).map selected.contains |>.getD false
  let selectedRecs := openRecs.filter fun r =>
    ((itemId? r).map selected.contains |>.getD false)
      || (phaseDecision.isSome && isPhaseGateRec r)
  -- カウンタ(L2889–2895)。§13.1-12: infra streak も idle と同様に resume が
  -- ゼロ化する — 閾値未満の残滓が resume 直後の単発 infra 失敗で gate しない
  let (context0, _) := readJsonOrEmpty "context.json" i.contextRaw
  let context1 := Loop.setdefault context0 "progress" (.obj [])
  let progress0 := (context1.get? "progress").getD (.obj [])
  let (idleCleared, _) :=
    Predicates.progressCounter progress0 "idle_cycles_since_progress"
  let (infraCleared, _) :=
    Predicates.progressCounter progress0 "infra_fails_since_ok"
  -- L2897: raise-loop-gates が走る前にクラッシュした場合の直接述語フォールバック
  let frameworkPhaseGate := hasFrameworkPhaseGate i.stopPayload i.recsRaw
  let releasesGates := !selectedBlockers.isEmpty || !selectedRecs.isEmpty
    || idleCleared != 0 || infraCleared != 0
    || (frameworkPhaseGate && phaseDecision.isSome)
  -- noop(L2905–2928): projection drift は次サイクルの再投影事項なので
  -- 単独では resume を非冪等にしない。attestation の無い Essence
  -- (essence_unreviewed)だけは決して no-op にしない(§13.1-10)
  if !releasesGates && !essenceUnreviewed && i.worktree == some []
      && closedRuns.isEmpty then
    .noop (.obj [
      ("resumed", .bool false),
      ("mode", .str "noop"),
      ("message", .str ("No latched gates, no uncommitted changes, and no "
        ++ "unrecorded Essence change; nothing to release or record."))])
  else
    let note :=
      let supplied := Text.pyStrip (i.noteArg.getD "")
      if !supplied.isEmpty then supplied
      else if mode == "gate_release" then "Human review completed."
      else "Human mid-course update."
    -- crash recovery の end レコード(L2937–2946)
    let runRecords := closedRuns.map fun runId => Json.Value.obj [
      ("at", .str i.now),
      ("run_id", runId),
      ("event", .str "end"),
      ("status", .str "aborted_by_resume"),
      ("project", .str i.title)]
    -- 解決の in-place 更新(Python dict 代入: 既存キーは位置保持、新規は末尾)
    let resolveFields (item : Json.Value) : Json.Value :=
      (((item.set "status" (.str "resolved")).set
        "resolved_at" (.str i.now)).set
        "resolved_by" (.str "human")).set
        "resolution" (.str note)
    let resolveItems (payload : Json.Value) (isOpen : Json.Value → Bool) :
        Json.Value :=
      let items := match payload.get? "items" with
        | some (.arr items) => items.map fun item =>
            if (item matches .obj _) && isOpen item then resolveFields item
            else item
        | _ => []
      Loop.setdefault (payload.set "items" (.arr items))
        "schema_version" (.str Validate.schemaVersion)
    let resolvedBlockers := selectedBlockers.map fun b => (b.get? "id").getD .null
    let newBlockers := if resolvedBlockers.isEmpty then none
      else some (resolveItems blockers fun b =>
        isOpenBlocker b && ((itemId? b).map selected.contains |>.getD false))
    let resolvedRecs := selectedRecs.map fun r => (r.get? "id").getD .null
    -- §13.3-4' / §19.3 / §21.5-3: phase 境界 gate の解放 = should phase の承認。
    -- 認可は `hasFrameworkPhaseGate`(= stopPayload の直接述語 mustPhaseComplete
    -- ∧ phase==must の再計算)だけが与える。agent が gate/raised_by フィールドを
    -- 詐称した Recommendation を置いても、must が実際に未完了なら direct = false の
    -- ため phase は昇格しない(2026-07-27 の bypass 封止)。
    -- selectionError? is the user-facing refusal, but the transition kernel is
    -- independently fail-closed: even a caller that bypasses that preflight
    -- cannot change phase without a framework-observed boundary.
    let approvesShouldPhase := frameworkPhaseGate
      && phaseDecision == some "approve_should"
    let closesAtMust := frameworkPhaseGate
      && phaseDecision == some "close_at_must"
    let newRecs := if resolvedRecs.isEmpty then none
      else some (resolveItems recs fun r =>
        isOpenRec r && (((itemId? r).map selected.contains |>.getD false)
          || (phaseDecision.isSome && isPhaseGateRec r)))
    -- context(L2987–3010、`resumedContext` に分離 — S-T6 の証明対象)
    let rc := resumedContext i.contextRaw approvesShouldPhase closesAtMust
      (mode == "gate_release") i.now note
    let priorHandoff := rc.1
    let essenceShaJson := (i.essenceSha.map Json.Value.str).getD .null
    -- reflection(L3012–3032、informational — should-stop はこれを信頼しない)
    let reflection := Json.Value.obj [
      ("at", .str i.now),
      ("type", .str "human_resume"),
      ("mode", .str mode),
      ("summary", .str note),
      ("resolved_blockers", .arr resolvedBlockers),
      ("resolved_recommendations", .arr resolvedRecs),
      ("approved_should_phase", .bool approvesShouldPhase),
      ("closed_at_must", .bool closesAtMust),
      ("idle_cycles_cleared", .num idleCleared 0),
      ("infra_fails_cleared", .num infraCleared 0),
      ("prior_handoff", priorHandoff),
      ("essence_sha256", essenceShaJson),
      ("essence_projection_drift", .bool drift),
      ("projected_from_essence_sha256", recorded?.getD .null),
      ("worktree_changes", optListJson i.worktree),
      ("forced", .bool !i.inFlight.isEmpty),
      ("closed_runs", .arr closedRuns)]
    -- attestation(L3038–3048、§13.1-10): should-stop が信頼する唯一の
    -- essence-review 記録。project plane の外に置かれ agent は偽造できない
    let attestation := Json.Value.obj [
      ("at", .str i.now),
      ("project", .str i.title),
      ("project_root", .str i.projectRootRel),
      ("essence_sha256", essenceShaJson),
      ("essences", Predicates.assetsManifestJson i.essencesManifest),
      ("mode", .str mode),
      ("note", .str note)]
    .proceed {
      mode, note, runRecords, newBlockers, newRecs
      newContext := rc.2
      reflection, attestation
      resolvedBlockers
      resolvedRecommendations := resolvedRecs
      approvesShouldPhase, closesAtMust, idleCleared, drift
      worktree := i.worktree
      closedRuns
    }

/-- 完了時の stdout payload(L3055–3073、indent=2)。`should_stop_after_resume`
は全書き込み後の再評価 — 残る停止条件は次の loop を再 gate するだけで、完了
した resume は常に exit 0(解放済み latch を未コミットで漂流させない、
L3050–3054)。 -/
def finalPayload (plan : Plan) (postStop : Json.Value) : Json.Value :=
  .obj [
    ("resumed", .bool true),
    ("mode", .str plan.mode),
    ("note", .str plan.note),
    ("resolved_blockers", .arr plan.resolvedBlockers),
    ("resolved_recommendations", .arr plan.resolvedRecommendations),
    ("approved_should_phase", .bool plan.approvesShouldPhase),
    ("closed_at_must", .bool plan.closesAtMust),
    ("idle_cycles_cleared", .num plan.idleCleared 0),
    ("essence_projection_drift", .bool plan.drift),
    ("worktree_changes", optListJson plan.worktree),
    ("closed_runs", .arr plan.closedRuns),
    ("should_stop_after_resume", postStop)]

/-! ## コンパイル時テスト -/

-- unfinishedRunIds: dict 挿入順・end による除去・再 start の末尾再挿入・
-- falsy スキップ
private def openRunsOf (raw : RawFile) : Option (List Json.Value × Nat) :=
  match unfinishedRunIds raw with
  | .ok (ids, diags) => some (ids, diags.length)
  | .error _ => none

#guard openRunsOf (.text
    "{\"run_id\": \"A\", \"event\": \"start\"}\n{\"run_id\": \"B\", \"event\": \"start\"}\n{\"run_id\": \"A\", \"event\": \"end\"}\n")
  == some ([.str "B"], 0)
#guard openRunsOf (.text
    "{\"run_id\": \"A\", \"event\": \"start\"}\n{\"run_id\": \"A\", \"event\": \"end\"}\n{\"run_id\": \"A\", \"event\": \"start\"}\n{\"run_id\": \"B\", \"event\": \"start\"}\n{\"run_id\": \"B\", \"event\": \"end\"}\n")
  == some ([.str "A"], 0)
#guard openRunsOf (.text "{\"run_id\": \"\", \"event\": \"start\"}\n{\"event\": \"start\"}\n")
  == some ([], 0)
#guard openRunsOf (.text "{\"run_id\": \"A\", \"event\": \"start\"}\n{\"run_id\": \"A\", \"event\": \"start\"}\n")
  == some ([.str "A"], 0)
#guard openRunsOf (.text "not json\n") == some ([], 1)
#guard openRunsOf .absent == some ([], 0)
#guard openRunsOf (.text "[1, 2]\n") == none                    -- 非 dict レコード
#guard openRunsOf (.text "{\"run_id\": [\"x\"], \"event\": \"start\"}\n")
  == none                                                       -- unhashable
#guard openRunsOf (.text "{\"run_id\": {}, \"event\": \"start\"}\n")
  == some ([], 0)                                               -- falsy {} はスキップ

-- inFlightError: join の TypeError
#guard (inFlightError [.str "R-1", .str "R-2"]).isOk == true
#guard (inFlightError [.num 5 0]).isOk == false

-- gitStatusPaths: line[3:]・len>3・set 一意化・ソート
#guard gitStatusPaths " M b.txt\n?? a.txt\n M a.txt\n?? \n" == ["a.txt", "b.txt"]
#guard gitStatusPaths "" == []
#guard gitStatusPaths "?? \"a b\"\n" == ["\"a b\""]  -- 引用剥ぎしない(生 porcelain)

-- stateUnreadableError?: 非空 arr のみ
#guard stateUnreadableError? (.obj [("state_unreadable", .arr [])]) == none
#guard (stateUnreadableError? (.obj [("state_unreadable",
    .arr [.str "x.json: broken"])])).isSome

private def probeInputs : TransitionInputs := {
  stopPayload := .obj [
    ("reasons", .arr [.str "essence_blocking"]),
    ("essence_unreviewed_change", .bool false),
    ("must_complete_awaiting_phase_approval", .bool false)]
  blockersRaw := .text "{\"schema_version\": \"2.0.0\", \"items\": [{\"id\": \"B-001\", \"type\": \"essence_blocking\", \"status\": \"active\"}]}"
  recsRaw := .text "{\"items\": []}"
  contextRaw := .text "{\"progress\": {\"idle_cycles_since_progress\": 2}, \"handoff\": {\"summary\": \"old\"}}"
  specRaw := .absent
  essenceSha := some "abc"
  inFlight := []
  force := false
  noteArg := some "  reviewed  "
  resolveIds := ["B-001"]
  worktree := none
  now := "T0"
  title := "demo"
  projectRootRel := "../demo"
}

-- gate_release: blocker 解決・note strip・handoff 退避・カウンタゼロ化・
-- resume note 未消費マーカー(pending_cycle、§19.3)
#guard match transition probeInputs with
  | .proceed plan =>
    plan.mode == "gate_release" && plan.note == "reviewed"
      && plan.resolvedBlockers == [.str "B-001"]
      && plan.idleCleared == 2
      && plan.newRecs == none
      && (plan.newContext.getPath? ["progress", "idle_cycles_since_progress"]
          == some (.num 0 0))
      && (plan.newContext.getPath? ["handoff", "summary"]
          == some (.str "Human resume: reviewed"))
      && (plan.newContext.getPath? ["handoff", "pending_cycle"]
          == some (.bool true))
      && plan.reflection.get? "prior_handoff"
          == some (.obj [("summary", .str "old")])
      && plan.attestation.get? "essence_sha256" == some (.str "abc")
  | .noop _ => false

-- steering: latch なし + Essence 未 attest → noop にはならず handoff 保持
#guard match transition { probeInputs with
    stopPayload := .obj [
      ("reasons", .arr [.str "essence_unreviewed_change"]),
      ("essence_unreviewed_change", .bool true),
      ("must_complete_awaiting_phase_approval", .bool false)]
    blockersRaw := .text "{\"items\": []}"
    contextRaw := .text "{\"progress\": {}, \"handoff\": {\"summary\": \"keep\"}}"
    noteArg := none
    resolveIds := []
    worktree := some [] } with
  | .proceed plan =>
    plan.mode == "steering" && plan.note == "Human mid-course update."
      && plan.reflection.get? "prior_handoff" == some .null
      && (plan.newContext.getPath? ["handoff", "summary"] == some (.str "keep"))
  | .noop _ => false

-- noop: latch なし・attest 済み・clean worktree・closed runs なし
#guard match transition { probeInputs with
    stopPayload := .obj [
      ("reasons", .arr []),
      ("essence_unreviewed_change", .bool false),
      ("must_complete_awaiting_phase_approval", .bool false)]
    blockersRaw := .text "{\"items\": []}"
    contextRaw := .text "{\"progress\": {}}"
    resolveIds := []
    worktree := some [] } with
  | .noop payload => payload.get? "mode" == some (.str "noop")
  | .proceed _ => false

-- worktree 不明(none)は clean ではない → steering として記録する
#guard match transition { probeInputs with
    stopPayload := .obj [
      ("reasons", .arr []),
      ("essence_unreviewed_change", .bool false),
      ("must_complete_awaiting_phase_approval", .bool false)]
    blockersRaw := .text "{\"items\": []}"
    contextRaw := .text "{\"progress\": {}}"
    resolveIds := []
    worktree := none } with
  | .proceed plan => plan.mode == "steering"
      && plan.reflection.get? "worktree_changes" == some .null
  | .noop _ => false

-- forced crash recovery: end レコードと closed_runs、forced フラグ
#guard match transition { probeInputs with
    inFlight := [.str "R-1", .str "R-2"], force := true } with
  | .proceed plan =>
    plan.closedRuns == [.str "R-1", .str "R-2"]
      && plan.runRecords.length == 2
      && (plan.runRecords.head?.bind (·.get? "status"))
          == some (.str "aborted_by_resume")
      && plan.reflection.get? "forced" == some (.bool true)
  | .noop _ => false

-- phase 承認: framework-raised gate のみが phase を昇格させる
private def gateRec (raisedBy : Option String) : String :=
  "{\"items\": [{\"id\": \"R-LG-1\", \"type\": \"Human-input Recommendation\", "
    ++ "\"status\": \"proposed\", \"agent_action\": \"stop_until_human_review\", "
    ++ "\"gate\": \"must_complete_awaiting_phase_approval\""
    ++ (match raisedBy with
        | some rb => ", \"raised_by\": \"" ++ rb ++ "\"}]}"
        | none => "}]}")

-- 認可の権威は stopPayload の直接述語 must_complete_awaiting_phase_approval
-- (= should-stop が現在の todo/phase から再計算した実境界)。gateRec は
-- **選択**(resolved 対象)に使うだけで、認可には効かない。
private def phaseBoundaryPayload : Json.Value := .obj [
  ("reasons", .arr [.str "must_complete_awaiting_phase_approval"]),
  ("essence_unreviewed_change", .bool false),
  ("must_complete_awaiting_phase_approval", .bool true)]

#guard match transition { probeInputs with
    stopPayload := phaseBoundaryPayload
    blockersRaw := .text "{\"items\": []}"
    recsRaw := .text (gateRec (some "mercator-loop"))
    resolveIds := []
    phaseDecision := some "approve_should" } with
  | .proceed plan => plan.approvesShouldPhase
      && plan.newContext.get? "phase" == some (.str phaseExtendedApproved)
      && plan.resolvedRecommendations == [.str "R-LG-1"]
      && plan.newContext.getPath? ["handoff", "pending_cycle"]
          == some (.bool true)
  | .noop _ => false

-- --close-at-must は resume 自身が closure: pending_cycle は false で書かれ、
-- 即時の must-scope COMPLETE を妨げない(§19.3)
#guard match transition { probeInputs with
    stopPayload := phaseBoundaryPayload
    blockersRaw := .text "{\"items\": []}"
    recsRaw := .text (gateRec (some "mercator-loop"))
    resolveIds := []
    phaseDecision := some "close_at_must" } with
  | .proceed plan => plan.closesAtMust
      && plan.newContext.get? "phase" == some (.str phaseClosedAtMust)
      && plan.newContext.getPath? ["handoff", "pending_cycle"]
          == some (.bool false)
  | .noop _ => false

-- 認可 bypass 封止(2026-07-27): must が実際に未完了(direct = false)なら、
-- raised_by=mercator-loop を詐称した gate rec があっても --approve-should は
-- phase を昇格させない。probeInputs の stopPayload は must_complete=false。
#guard match transition { probeInputs with
    blockersRaw := .text "{\"items\": []}"
    recsRaw := .text (gateRec (some "mercator-loop"))
    resolveIds := []
    phaseDecision := some "approve_should" } with
  | .proceed plan => !plan.approvesShouldPhase
      && plan.newContext.get? "phase" == none
  -- selectionError? は「境界不在で phase flag」を拒否するため noop ではなく
  -- proceed に到達しない可能性がある。到達しても昇格しないことを確認。
  | .noop _ => true

#guard match transition { probeInputs with
    blockersRaw := .text "{\"items\": []}"
    recsRaw := .text (gateRec none)
    resolveIds := ["R-LG-1"] } with
  | .proceed plan => !plan.approvesShouldPhase
      && plan.newContext.get? "phase" == none
      && plan.resolvedRecommendations == [.str "R-LG-1"]
  | .noop _ => false

-- 境界が**現に立っている**間は、phase gate の `--resolve` 単独を拒否する
#guard selectionError? { probeInputs with
    stopPayload := phaseBoundaryPayload
    blockersRaw := .text "{\"items\": []}"
    recsRaw := .text (gateRec (some "mercator-loop"))
    resolveIds := ["R-LG-1"] } == some
      "a must phase gate requires --approve-should or --close-at-must; --resolve alone is insufficient"

-- 境界が消えた後に残る**陳腐化 phase gate** は `--resolve` で閉じられる。
-- ここを拒み続けると `--resolve` / phase flag / no-flag のすべてが拒否され、
-- loop も pre-gate で拒否する完全なデッドロックになる(I-017 破れ)。
#guard selectionError? { probeInputs with
    blockersRaw := .text "{\"items\": []}"
    recsRaw := .text (gateRec (some "mercator-loop"))
    resolveIds := ["R-LG-1"] } == none
-- 閉じても phase は昇格しない(認可は `hasFrameworkPhaseGate` が独占する)
#guard match transition { probeInputs with
    blockersRaw := .text "{\"items\": []}"
    recsRaw := .text (gateRec (some "mercator-loop"))
    resolveIds := ["R-LG-1"] } with
  | .proceed plan => !plan.approvesShouldPhase && !plan.closesAtMust
      && plan.newContext.get? "phase" == none
      && plan.resolvedRecommendations == [.str "R-LG-1"]
  | .noop _ => false

-- preconditionError?: 順序と文言プレフィクス
#guard match preconditionError? false "/x/state" .absent .absent with
  | .ok (some msg) => msg.startsWith "project state is not initialized"
  | _ => false
#guard match preconditionError? true "/x/state" .absent .absent with
  | .ok (some msg) => msg.startsWith "ESSENCE.md does not exist"
  | _ => false
#guard match preconditionError? true "/x/state"
    (.file "<!-- FILL: 目的 -->".toUTF8) .absent with
  | .ok (some msg) => msg.startsWith "ESSENCE.md is still the Mercator placeholder"
  | _ => false
-- 見出し契約(§13.1-15)を満たす実体 Essence だけが前提を通る
private def canonicalResumeEssence (motivation : String) : String :=
  "# ESSENCE — Resume Probe\n## モチベーション\n- " ++ motivation ++ "\n"
    ++ "## 思想\n- Determinism over cleverness.\n"
    ++ "## 前提事項\n- No external services.\n"
    ++ "## 成功条件\n- The build is green.\n"
    ++ "## 必須対応事項\n- Build the thing.\n"
    ++ "## 任意対応事項\n- Nothing optional.\n"
    ++ "## 非対応事項\n- No GUI.\n"
    ++ "## 遂行順序\n- As listed above.\n"
    ++ "## 用語\n- なし\n"
#guard match preconditionError? true "/x/state"
    (.file (String.toUTF8 (canonicalResumeEssence "real"))) .absent with
  | .ok none => true
  | _ => false
-- 見出し契約違反は attest 前に絶対拒否(§2.1.1'・§13.1-15)。placeholder 拒否の
-- 直後・essences/ 不整合拒否の直前に立つ
#guard match preconditionError? true "/x/state" (.file "# Why\nreal\n".toUTF8)
    .absent with
  | .ok (some msg) =>
    msg.startsWith ("ESSENCE.md heading structure violates the canonical section "
      ++ "contract (first heading must be `# ESSENCE — <title>`;")
      && (msg.splitOn "resume must not attest a malformed Essence.").length > 1
  | _ => false
-- essences/ の双方向不整合は attest 前に拒否(§2.1.5)
#guard match preconditionError? true "/x/state"
    (.file (String.toUTF8 (canonicalResumeEssence "real")))
    (.dir [("orphan.png", .file (String.toUTF8 "x"))] [] []) with
  | .ok (some msg) => msg.startsWith "ESSENCE.md and essences/ are out of sync"
  | _ => false
#guard match preconditionError? true "/x/state"
    (.file (String.toUTF8 (canonicalResumeEssence "see essences/logo.png")))
    (.dir [("logo.png", .file (String.toUTF8 "x"))] [] []) with
  | .ok none => true
  | _ => false

-- attestation は essences マニフェストを同一レコードで記録する(§13.1-10 拡張)
#guard match transition { probeInputs with
    essencesManifest := [("logo.png", "h1")] } with
  | .proceed plan => plan.attestation.get? "essences"
      == some (.obj [("logo.png", .str "h1")])
  | .noop _ => false

/-! ### supervise authorizing gate(§13.3-4''、2026-08-04 の実障害の再発防止) -/

private def authorizingTodoRaw : RawFile := .text
  ("{\"items\": [{\"id\": \"T-HR\", \"title\": \"instantiate\", "
    ++ "\"priority\": \"must\", \"status\": \"pending\", "
    ++ "\"executor\": {\"mode\": \"mercator\"}, \"risk_level\": \"high\", "
    ++ "\"risk_reason\": \"agent runtime\", \"target\": \"agent/**\"}]}")

private def authorizingRecsRaw : RawFile := .text
  ("{\"items\": [{\"id\": \"R-A\", \"type\": \"Human-input Recommendation\", "
    ++ "\"status\": \"proposed\", \"requires_human_approval\": true, "
    ++ "\"source\": [\"T-HR\"], \"target\": \"agent/**\"}]}")

private def authorizingProbe : TransitionInputs := { probeInputs with
  blockersRaw := .text "{\"items\": []}"
  recsRaw := authorizingRecsRaw
  todoRaw := authorizingTodoRaw
  resolveIds := [] }

-- authorizing gate の `--resolve` は拒否(閉じると preflight が恒久拒否になる)
#guard match selectionError? { authorizingProbe with resolveIds := ["R-A"] } with
  | some msg => msg.startsWith "R-A is the open supervise authorization"
      && (msg.splitOn "--retract-approval R-A").length > 1
      && (msg.splitOn "just supervise --todo T-HR --recommendation R-A").length > 1
  | none => false

-- authorizing gate だけが open のとき、素の resume は強制拒否されない
-- (gate 温存の途中 checkpoint — 2026-08-04 のデッドロックの解消)
#guard selectionError? authorizingProbe == none

-- 素の resume は gate を resolve しない(温存される)
#guard match transition authorizingProbe with
  | .proceed plan => plan.resolvedRecommendations == []
  | .noop _ => false

-- authorizing gate と通常 gate が併存すると、素の resume は通常 gate だけを
-- 名指しして拒否する(authorizing は forcing 集合から除外)
#guard match selectionError? { authorizingProbe with
    recsRaw := .text
      ("{\"items\": [{\"id\": \"R-A\", \"type\": \"Human-input Recommendation\", "
        ++ "\"status\": \"proposed\", \"requires_human_approval\": true, "
        ++ "\"source\": [\"T-HR\"], \"target\": \"agent/**\"}, "
        ++ "{\"id\": \"R-P\", \"type\": \"Human-input Recommendation\", "
        ++ "\"status\": \"proposed\", \"requires_human_approval\": true}]}") } with
  | some msg => msg.startsWith "open gates require explicit --resolve <ID>: R-P"
      && (msg.splitOn "R-A").length == 1
  | none => false

-- `--retract-approval` は明示の承認撤回として受理され、gate を resolved にする
#guard selectionError? { authorizingProbe with retractIds := ["R-A"] } == none
#guard match transition { authorizingProbe with retractIds := ["R-A"] } with
  | .proceed plan => plan.resolvedRecommendations == [.str "R-A"]
  | .noop _ => false

-- `--retract-approval` は authorizing gate 以外には使えない
#guard match selectionError? { authorizingProbe with
    recsRaw := .text
      ("{\"items\": [{\"id\": \"R-P\", \"type\": \"Human-input Recommendation\", "
        ++ "\"status\": \"proposed\", \"requires_human_approval\": true}]}")
    retractIds := ["R-P"] } with
  | some msg => msg.startsWith "--retract-approval names no open supervise authorization"
  | none => false

-- Todo が unfinished でなくなれば通常 gate に戻り、`--resolve` が受理される
-- (supervise 完了・diff レビュー後の正規の閉じ方)
#guard selectionError? { authorizingProbe with
    todoRaw := .text
      ("{\"items\": [{\"id\": \"T-HR\", \"title\": \"instantiate\", "
        ++ "\"priority\": \"must\", \"status\": \"done\", "
        ++ "\"executor\": {\"mode\": \"mercator\"}, \"risk_level\": \"high\", "
        ++ "\"risk_reason\": \"agent runtime\", \"target\": \"agent/**\"}]}")
    resolveIds := ["R-A"] } == none

-- target 不一致の rec は authorizing ではない(preflight も拒否する組は
-- 守らない — 単一定義 `Predicates.superviseAuthorizedTodo?` の帰結)
#guard selectionError? { authorizingProbe with
    recsRaw := .text
      ("{\"items\": [{\"id\": \"R-A\", \"type\": \"Human-input Recommendation\", "
        ++ "\"status\": \"proposed\", \"requires_human_approval\": true, "
        ++ "\"source\": [\"T-HR\"], \"target\": \"other/**\"}]}")
    resolveIds := ["R-A"] } == none

/-! ### `--steer-only`(§13.3-4'''、2026-08-05 の実障害の再発防止)

open gate を保ったまま人間所有入力の編集だけを記録する遷移。§19.3 が指示する
「要求そのものを昇格・追加して続行する」手順は must 境界から入るため、境界で
実体化された phase gate が open のまま残り、素の resume は必ず拒否されていた。 -/

private def openHumanRecRaw : RawFile := .text
  ("{\"items\": [{\"id\": \"R-H\", \"type\": \"Human-input Recommendation\", "
    ++ "\"status\": \"proposed\", \"requires_human_approval\": true}]}")

/-- 境界が現に立っている状態 + 未 attest の ESSENCE.md 編集(混線拒否と遷移核の
独立 fail-closed を、noop に落ちない観測の上で見るための payload)。 -/
private def phaseBoundaryUnreviewed : Json.Value := .obj [
  ("reasons", .arr [.str "essence_unreviewed_change",
    .str "must_complete_awaiting_phase_approval"]),
  ("essence_unreviewed_change", .bool true),
  ("must_complete_awaiting_phase_approval", .bool true)]

/-- 未 attest の ESSENCE.md 編集 + open な通常 gate(= 実障害の骨格)。
counter は 0 に置き、gate 非解除を counter のゼロ化と混同しない形にする。 -/
private def steerProbe : TransitionInputs := { probeInputs with
  stopPayload := .obj [
    ("reasons", .arr [.str "essence_unreviewed_change",
      .str "human_input_required"]),
    ("essence_unreviewed_change", .bool true),
    ("must_complete_awaiting_phase_approval", .bool false)]
  blockersRaw := .text "{\"items\": []}"
  recsRaw := openHumanRecRaw
  contextRaw := .text "{\"progress\": {}, \"handoff\": {\"summary\": \"keep\"}}"
  noteArg := none
  resolveIds := []
  worktree := some [] }

-- 過剰解除の禁止は不変: open gate 下の素の resume は拒否され、拒否文は
-- 受理される代替(`--steer-only`)を名指しする
#guard match selectionError? steerProbe with
  | some msg => msg.startsWith "open gates require explicit --resolve <ID>: R-H"
      && (msg.splitOn "--steer-only").length > 1
  | none => false

-- 同じ状態で意図を明示した resume は受理される
#guard selectionError? { steerProbe with steerOnly := true } == none

-- 受理された steer-only resume は gate を 1 件も動かさず、mode は steering に
-- 固定され(handoff 温存)、attestation だけが追記される
#guard match transition { steerProbe with steerOnly := true } with
  | .proceed plan => plan.mode == "steering"
      && plan.newBlockers == none && plan.newRecs == none
      && plan.resolvedBlockers == [] && plan.resolvedRecommendations == []
      && (plan.newContext.getPath? ["handoff", "summary"] == some (.str "keep"))
      && plan.attestation.get? "essence_sha256" == some (.str "abc")
      && plan.note == "Human mid-course update."
  | .noop _ => false

-- 意図の混線(何も解除しない ∧ これを解除する)は書き込み前に拒否する
#guard match selectionError? { steerProbe with
    steerOnly := true, resolveIds := ["R-H"] } with
  | some msg => msg.startsWith "--steer-only records the human's input edits"
  | none => false
#guard match selectionError? { steerProbe with
    stopPayload := phaseBoundaryUnreviewed
    recsRaw := .text (gateRec (some "mercator-loop"))
    steerOnly := true, phaseDecision := some "approve_should" } with
  | some msg => msg.startsWith "--steer-only records the human's input edits"
  | none => false

-- 遷移核は preflight から独立に fail-closed: 混線した入力が selectionError? を
-- 迂回して到達しても、gate 集合も phase も動かない(S-T7)
#guard match transition { steerProbe with
    stopPayload := phaseBoundaryUnreviewed
    recsRaw := .text (gateRec (some "mercator-loop"))
    steerOnly := true, resolveIds := ["R-LG-1"]
    phaseDecision := some "approve_should" } with
  | .proceed plan => plan.newRecs == none
      && plan.resolvedRecommendations == []
      && !plan.approvesShouldPhase && !plan.closesAtMust
      && plan.newContext.get? "phase" == none
      && plan.mode == "steering"
  | .noop _ => false

-- 実障害の形: 陳腐化 phase gate だけが open。`--resolve` で閉じる道(RS-055)に
-- 加えて、gate を保ったまま編集を記録する道が存在する
#guard selectionError? { steerProbe with
    recsRaw := .text (gateRec (some "mercator-loop"))
    steerOnly := true } == none

-- latch が無いときの `--steer-only` は通常の steering と同一(冗長指定は無害)
#guard match transition { steerProbe with
    stopPayload := .obj [
      ("reasons", .arr [.str "essence_unreviewed_change"]),
      ("essence_unreviewed_change", .bool true),
      ("must_complete_awaiting_phase_approval", .bool false)]
    recsRaw := .text "{\"items\": []}"
    steerOnly := true } with
  | .proceed plan => plan.mode == "steering" && plan.newRecs == none
  | .noop _ => false

-- 記録すべき編集も未コミット変更も無ければ、`--steer-only` でも no-op のまま
-- (gate を開けたまま空の checkpoint を作らない)
#guard match transition { steerProbe with
    stopPayload := .obj [
      ("reasons", .arr [.str "human_input_required"]),
      ("essence_unreviewed_change", .bool false),
      ("must_complete_awaiting_phase_approval", .bool false)]
    steerOnly := true } with
  | .noop payload => payload.get? "mode" == some (.str "noop")
  | .proceed _ => false

end Mercator.State.Resume
