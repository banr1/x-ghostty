import Mercator.Guard.Types
import Mercator.Guard.Rules
import Mercator.Core.Classify
import Mercator.Core.Classify.Bash
import Mercator.Core.Classify.Install
import Mercator.Core.Classify.ReadOnly
import Mercator.Hook.PostTool

/-!
`Mercator.Guard.Decide` — PreToolUse guard の純粋決定核(META.md §16・§23、
§31.2-19)。

移行元: `.claude/hooks/pre_tool_guard.py` の `main()` と、そこからしか呼ばれ
ない判定補助(`path_candidates` / `bash_high_risk_targets` / `cd_targets` /
`cd_leaves_allowed_roots` / `install_allow_reason` の cd フェンス /
`read_only_session_bash_allow` の解決依存部)。分類プリミティブは
`Core.Classify` 4 部の単一定義をそのまま使う。

**決定木の順序が安全性の核**(G-T1 の対象): deny 群(保護パス書き込み →
secret → git stage/commit → human-only → loop-only → DANGEROUS_BASH →
Claude ネスト起動 → 制御プレーン面)が全 ask/allow に先行し、ask 化への
降格が起きない。この順序は Python `main()` の逐次 `decision()` と 1:1 で、
変更はシャドー検証の裁定事項。

**PostTool との共有定義**: パス表記代数(`pyPathStr` / `childPath` /
`relativeTo?`)と Bash 変異ターゲット抽出(`bashCandidateTokens`)は
`Hook.PostTool` 純粋核から import する。post の分類が pre の部分集合で
あること(D-002、将来の `theorem post_subset_pre`)は同一定義の共有で構成的に
成立する。`Hook.PostTool` は純粋名前空間であり、この import は IO への依存
ではない(純度ゲート対象内)。

**IO シェルの契約**(3 手、§3.3-3): (1) stdin JSON と環境・プロジェクト
インデックス・ESSENCE を読み、`familyARequests` / `familyBRequests` のキーを
解決して `GuardEnv` を組む → (2) `decide` を呼ぶ → (3) `highRiskPre` を
`record_high_risk_pre` 相当で stage し(best-effort、失敗は stderr)、
`decision?` を stdout へ出して exit 0。
-/

namespace Mercator.Guard

open Mercator.Core.Classify
open Mercator.Core.Prim (dropLit?)
open Mercator.Core.Text (isPySpace pyStrip)
open Mercator.Hook.PostTool (pyPathStr childPath relativeTo? bashCandidateTokens)
open Rules

/-! ## 解決表の適用(`resolve_target` / read-only 結合規約の純粋側) -/

/-- `resolve_target(raw, cwd)` の純粋側: 絶対パスは Python が**解決しない**
(`Path(raw)` のまま返す)ため表記正規化のみ、相対パスは family A の解決結果
(`(Path(cwd or ".") / raw).resolve()`、失敗 = none)。 -/
def GuardEnv.resolveTarget? (env : GuardEnv) (raw : String) : Option String :=
  if raw.startsWith "/" then some (pyPathStr raw)
  else env.resolved? raw

/-- read-only 面の結合キー: `Path(raw)` が絶対ならそのまま、相対なら
`base / raw`(family B は絶対キーも**解決する** — `resolve_target` との差)。 -/
def GuardEnv.handoffKey (env : GuardEnv) (raw : String) : String :=
  if raw.startsWith "/" then raw else childPath env.base raw

/-- `_inside(path, root)` 等価(両辺とも表記正規化済み前提の成分比較)。 -/
def insideOf (root path : String) : Bool :=
  (relativeTo? root path).isSome

/-! ## path_candidates(pre 版 — 登録プロジェクトルート列を使う) -/

/-- `path_candidates(raw, cwd)` 等価。判定(`any`)にのみ使うため set の
順序・重複除去は再現しない。解決失敗(try/except)は生表記の候補のみ。 -/
def pathCandidates (env : GuardEnv) (raw : String) : List String :=
  if raw.isEmpty then []
  else
    ((pyPathStr raw).replace "\\" "/")
      :: match env.resolveTarget? raw with
         | none => []
         | some resolved =>
           (resolved.replace "\\" "/")
             :: (env.projectRoots.filterMap fun root => relativeTo? root resolved)
             ++ (relativeTo? env.controlRoot resolved).toList

/-- 解決済みターゲットの制御プレーン面判定(CONTROL_ROOT 相対のみ、§11.3)。 -/
def isControlPlaneTarget (env : GuardEnv) (resolved : String) : Bool :=
  match relativeTo? env.controlRoot resolved with
  | some rel => isControlPlaneHighRisk rel
  | none => false

/-! ## bash_high_risk_targets(§20.4-3 の staging 対象抽出) -/

/-- `bash_high_risk_targets(command, cwd)` 等価: mutator の後方にリテラル出現
する pathish トークン(`bashCandidateTokens` — post と共有)を解決し、制御
プレーン面(§11.3)か High-Risk Zone(§12)に載る解決済みパスの列。解決不能
トークンはスキップ(ask ゲート自体はこの抽出に依存しない)。 -/
def bashHighRiskTargets (env : GuardEnv) (command : String) : List String :=
  (bashCandidateTokens command).filterMap fun tok =>
    match env.resolveTarget? tok with
    | none => none
    | some resolved =>
      if isControlPlaneTarget env resolved
          || (pathCandidates env tok).any isHighRiskPath then
        some resolved
      else none

/-! ## cd_targets / cd_leaves_allowed_roots(§11.2 の cd フェンス) -/

private def isCdSep (c : Char) : Bool :=
  c == ';' || c == '&' || c == '|' || c == '\n'

/-- セグメント頭での `cd\s+([^;&|\n]+)` 照合。成功時は (捕獲生文字列, 残り)。 -/
private def cdAt? (cs : List Char) : Option (String × List Char) := do
  let r ← dropLit? cs "cd".toList
  let r' := r.dropWhile isPySpace
  if r.length == r'.length then none  -- `\s+` は 1 文字以上
  else
    let content := r'.takeWhile fun c => !isCdSep c
    if content.isEmpty then none
    else some (String.ofList content, r'.drop content.length)

/-- `[;&|\n]\s*` 先行の代替を左から走査(finditer の非重複再開位置 = 捕獲
直後)。fuel は毎歩 1 文字以上進むため入力長で足りる。 -/
private def cdScan : Nat → List Char → List String
  | 0, _ => []
  | _, [] => []
  | fuel + 1, c :: rest =>
    if isCdSep c then
      match cdAt? (rest.dropWhile isPySpace) with
      | some (raw, after) => raw :: cdScan fuel after
      | none => cdScan fuel rest
    else cdScan fuel rest

/-- `re.finditer(r"(^|[;&|\n]\s*)cd\s+([^;&|\n]+)", command)` の捕獲列。
`^` 代替は位置 0 の `cd` 直置きのみ(MULTILINE なし・`\s*` なし — 行頭の
`\n` は separator クラスが受ける)。 -/
def cdRawCaptures (command : String) : List String :=
  let cs := command.toList
  match cdAt? cs with
  | some (raw, after) => raw :: cdScan (cs.length + 1) after
  | none => cdScan (cs.length + 1) cs

/-- 各捕獲の strip → shlex → 先頭トークン(`ValueError` / 空 argv はスキップ)。
family A の解決要求キーでもある。 -/
def cdFirstTokens (command : String) : List String :=
  (cdRawCaptures command).filterMap fun rawCap =>
    match Mercator.Core.ShellLex.split (pyStrip rawCap) with
    | .ok (first :: _) => some first
    | _ => none

/-- `cd_targets(command, cwd)` 等価: 絶対パスは未解決のまま、相対パスは解決
(失敗時は生綴りを保持 — 許可ルートに一致せず ask 側へ落ちる fail-safe)。 -/
def cdTargets (env : GuardEnv) (command : String) : List String :=
  (cdFirstTokens command).map fun first =>
    if first.startsWith "/" then pyPathStr first
    else (env.resolved? first).getD (pyPathStr first)

/-- `cd_leaves_allowed_roots(command, cwd)` 等価: 許可ルート(CONTROL_ROOT ∪
登録 PROJECT_ROOT)の外へ出る最初の cd 先。 -/
def cdLeavesAllowedRoots? (env : GuardEnv) (command : String) : Option String :=
  let roots := env.controlRoot :: env.projectRoots
  (cdTargets env command).find? fun target =>
    !(roots.any fun root => insideOf root target)

/-! ## install_allow_reason(§11.2 依存ゲートの allow 面) -/

/-- `install_allow_reason(command, cwd)` 等価: 形状判定と 1 セグメント判定は
`Core.Classify.Install`、`cd <dir> &&` 前置の許可ルート照合(絶対 cd 先は
未解決比較・相対は解決必須)のみここで行う。 -/
def installAllowReason? (env : GuardEnv) (command : String) : Option String :=
  match installGateShape command with
  | .notGate => none
  | .bare seg => installAllowSegReason? env.declared seg
  | .withCd cdRaw seg =>
    let resolvedCd? :=
      if cdRaw.startsWith "/" then some (pyPathStr cdRaw)
      else env.resolved? cdRaw
    match resolvedCd? with
    | none => none
    | some p =>
      if (env.controlRoot :: env.projectRoots).any fun root => insideOf root p then
        installAllowSegReason? env.declared seg
      else none

/-! ## read_only_session_bash_allow(I-022/I-027) -/

/-- `resolves_into_handoff(raw, strict_inside)` 等価。 -/
def resolvesIntoHandoff (env : GuardEnv) (raw : String)
    (strictInside : Bool) : Bool :=
  match env.resolved? (env.handoffKey raw) with
  | none => false
  | some resolved =>
    if strictInside && resolved == env.handoffRoot then false
    else insideOf env.handoffRoot resolved

/-- read-only セッションの live settings 修復 ask 面(§28.5-3): 書き込み先が
`CONTROL_ROOT/.claude/settings.json` の解決済みパスへ一致するか。 -/
def resolvesToLiveSettings (env : GuardEnv) (raw : String) : Bool :=
  env.settingsFile != ""
    && env.resolved? (env.handoffKey raw) == some env.settingsFile

/-- essence(new)セッションの ESSENCE.md 直接設置 fallback(I-027 第二経路)の
照合先: `expectedProject?/ESSENCE.md`。new モード以外・対象未解決は none。 -/
def essenceInstallTarget? (env : GuardEnv) : Option String :=
  if env.sessionMode == "essence" && env.essenceMode == "new" then
    env.expectedProject?.map (childPath · "ESSENCE.md")
  else none

/-- 書き込み先が essence-new の ESSENCE.md fallback 面へ解決されるか。 -/
def resolvesToEssenceInstall (env : GuardEnv) (raw : String) : Bool :=
  match essenceInstallTarget? env with
  | some target => env.resolved? (env.handoffKey raw) == some target
  | none => false

/-- essence(new)セッションの essences/ 資産設置面(I-027 第二経路の §2.1.5
面)の照合ルート: `expectedProject?/essences`。new モード以外・対象未解決は
none。 -/
def essenceAssetInstallRoot? (env : GuardEnv) : Option String :=
  if env.sessionMode == "essence" && env.essenceMode == "new" then
    env.expectedProject?.map (childPath · "essences")
  else none

/-- 書き込み先が essence-new の essences/ 資産面へ解決されるか。root からの
相対パスが `Text.validAssetPath`(1..3 セグメント・各セグメントが許容名)を
満たすときのみ成立 — root 自身(`"."`)・上限より深いパス・不正名は不成立
であり、§2.1.5 の階層制約を設置面でも守る。 -/
def resolvesToEssenceAssetInstall (env : GuardEnv) (raw : String) : Bool :=
  match essenceAssetInstallRoot? env with
  | some root =>
    match env.resolved? (env.handoffKey raw) with
    | some resolved =>
      match relativeTo? root resolved with
      | some rel => Mercator.Core.Text.validAssetPath rel
      | none => false
    | none => false
  | none => false

/-- `read_only_session_bash_allow(command, mode, cwd)` 等価(mode は
`env.sessionMode`)。heredoc → (シェルメタなしの)mkdir -p → triage 限定の
state 読み取り、の順で allow 理由を探す。 -/
def readOnlySessionBashAllow? (env : GuardEnv) (command : String) :
    Option String :=
  let heredoc? :=
    match heredocForm? command with
    | some form =>
      if (form.mkdirRaw.all fun r => resolvesIntoHandoff env r false)
          && resolvesIntoHandoff env form.targetRaw true then
        some (handoffWriteReason env.sessionMode)
      else none
    | none => none
  heredoc? <|>
    if hasReadOnlyShellMeta command then none
    else match strictArgv? command with
    | none => none
    | some argv =>
      let mkdir? :=
        match mkdirHandoffArg? argv with
        | some p =>
          if resolvesIntoHandoff env p false then
            some (handoffMkdirReason env.sessionMode)
          else none
        | none => none
      mkdir? <|>
        if env.sessionMode != "triage" then none
        else match env.expectedProject?, triageStateShape? argv with
        | some expected, some (scriptRaw, projRaw) =>
          if env.resolved? (env.handoffKey scriptRaw) == some env.stateScript
              && env.resolved? (env.handoffKey projRaw) == some expected
              && triageStateSubcommandsOk command then
            some (stateInspectionReason env.sessionMode)
          else none
        | _, _ => none

/-! ## 解決要求の列挙(IO シェルが GuardEnv.resolved を組むための純粋仕様) -/

/-- family A(相対キー、`(cwd or ".") / key` 結合): write ターゲット
(空文字列含む — Python は `(cwd/"").resolve()` を計算する)、Bash 変異
ターゲット候補、cd 先頭トークン、install cd 前置。重複キーは IO 側で
自然に単一化してよい(lookup は先頭一致)。 -/
def familyARequests : ToolCall → List String
  | .write targetRaw =>
    if targetRaw.startsWith "/" then [] else [targetRaw]
  | .bash command =>
    (bashCandidateTokens command
        ++ cdFirstTokens command
        ++ match installGateShape command with
           | .withCd cdRaw _ => [cdRaw]
           | _ => []).filter
      fun raw => !raw.startsWith "/"
  | .other => []

/-- family B(read-only セッション面の結合済みキー — 絶対キーも解決する)。
`base` / `sessionMode` は `GuardEnv` と同じ値を渡す。WRITE_TOOLS は read-only
セッションのときだけ handoff 内包判定用にターゲットの結合キーを要求する
(§13.6-3 の Write 面)。 -/
def familyBRequests (base sessionMode : String) : ToolCall → List String
  | .bash command =>
    if sessionMode == "triage" || sessionMode == "essence" then
      let key (raw : String) : String :=
        if raw.startsWith "/" then raw else childPath base raw
      (match heredocForm? command with
       | some form => (form.mkdirRaw.toList ++ [form.targetRaw]).map key
       | none => [])
        ++ if hasReadOnlyShellMeta command then []
           else match strictArgv? command with
           | none => []
           | some argv =>
             (match mkdirHandoffArg? argv with
              | some p => [key p]
              | none => [])
               ++ if sessionMode == "triage" then
                    match triageStateShape? argv with
                    | some (scriptRaw, projRaw) => [key scriptRaw, key projRaw]
                    | none => []
                  else []
    else []
  | .write targetRaw =>
    if sessionMode == "triage" || sessionMode == "essence" then
      [if targetRaw.startsWith "/" then targetRaw else childPath base targetRaw]
    else []
  | .other => []

/-! ## 決定木 -/

private def decided (staged : List String) (p : Permission) (reason : String) :
    GuardOutput :=
  ⟨staged, some ⟨p, reason⟩⟩

/-- WRITE_TOOLS 経路。read-only セッション(I-022/I-027)は Bash 面
(`decideBash`)と対称に**最上段**で分岐し、handoff root の内側へ解決される
書き込みだけを allow、ask 面 3 種 — live settings 修復
(`resolvesToLiveSettings`、§28.5-3)、essence-new の ESSENCE.md 直接設置
fallback(`resolvesToEssenceInstall`、I-027 第二経路)、essence-new の
essences/ 資産設置(`resolvesToEssenceAssetInstall`、同経路の §2.1.5 面)—
を ask、それ以外は
教示付き deny にする(限定許可 + 既定拒否。§13.6-3/§2.1.4-2 — Write ツールが
handoff の第一の出口。ask 面の完全列挙は G-T2 write 面)。staging なし:
handoff は wrapper が消す一時領域で High-Risk 記録対象でなく、post 側の
監査 hook も read-only セッションでは無条件に無作用(§20.4)。

通常セッションは deny(DENY_PATTERNS)→ high-risk 分類と staging →
deny(制御プレーン面)→ ask(マニフェスト)→ ask(High-Risk Zone)。
high-risk 分類が ask 群に**先行**するのは、ask 理由が別ルール由来でも
before-hash を stage するため(§20.4-3。Python の実順序)。

制御プレーン面の deny がマニフェスト ask に**先行**するのは §11.3 の
「bound Agent session では常時 deny」を Edit 経路でも保つためである。両者は
実際に重なる — 配布物の `recipes/agentic-state-loop/files/loop/lean/`
(`lakefile.lean` / `lean-toolchain` / `lake-manifest.json`)がその実例であり、
旧順序ではレシピ原本(§29.2 の immutable surface)への Edit が ask へ降格し、
同じ対象を Bash mutator で触ったときの deny(`decideBash` は controlSurface が
先)と食い違っていた。deny 群が ask 群に先行するという決定木の順序不変量
(頭注・G-T1)を Bash 面と揃える。ask→deny は R-6 の「deny 拡大方向」。 -/
def decideWrite (env : GuardEnv) (targetRaw : String) : GuardOutput :=
  if env.sessionMode == "triage" || env.sessionMode == "essence" then
    if resolvesIntoHandoff env targetRaw true then
      decided [] .allow (handoffWriteReason env.sessionMode)
    else if resolvesToLiveSettings env targetRaw then
      decided [] .ask (liveSettingsAskReason env.sessionMode)
    else if resolvesToEssenceInstall env targetRaw then
      decided [] .ask essenceDirectInstallAskReason
    else if resolvesToEssenceAssetInstall env targetRaw then
      decided [] .ask essenceAssetInstallAskReason
    else
      let handoffDir := childPath env.controlRoot (".agent/tmp/" ++ env.sessionMode)
      decided [] .deny (readOnlyWriteDenyReason env.sessionMode handoffDir
        (env.sessionMode == "essence" && env.essenceMode == "new"))
  else
    let candidates := pathCandidates env targetRaw
    if candidates.any isDenyPath then
      decided [] .deny (writeDenyReason targetRaw)
    else
      let controlHighRisk :=
        match env.resolveTarget? targetRaw with
        | some resolved => isControlPlaneTarget env resolved
        | none => false
      let zoneHighRisk := candidates.any isHighRiskPath
      let staged := if zoneHighRisk && !controlHighRisk then [targetRaw] else []
      if controlHighRisk then
        decided staged .deny (controlPlaneDenyReason targetRaw)
      else if candidates.any isAskPath then
        decided staged .ask (manifestAskReason targetRaw)
      else if zoneHighRisk then
        decided staged .ask (zoneAskReason targetRaw)
      else
        ⟨staged, none⟩

/-- Bash 経路の決定木(頭注の順序不変量)。

control surface 段のテキスト検査(`isControlSurfaceBashMutation`)は
CONTROL_ROOT-cwd の相対綴り(素の `README.md` / `./scripts/...`)を写した
保守的過剰近似であり、cwd が登録 PROJECT_ROOT 配下のセッションでは同じ綴りが
agent 所有の通常実装ファイル(§11.1)を指す。そのため cwd(`env.base`)が
登録 project 配下に**ある**ときはテキスト検査を適用せず、解決済みパス判定
(`bashHighRiskTargets` → `isControlPlaneTarget`)だけに委ねる — project cwd
から CONTROL_ROOT へ届く綴り(`../<control>/README.md` / 絶対パス)はそちらが
deny する。cwd 不明・許可ルート外は従来どおりテキスト検査が生きる
(fail-closed)。project cwd の `cp .tmp-readme.md README.md` が control-plane
README 変異として deny された 2026-07-31 の過剰遮断(R-006)の是正。 -/
def decideBash (env : GuardEnv) (command : String) : GuardOutput :=
  if env.sessionMode == "triage" || env.sessionMode == "essence" then
    match readOnlySessionBashAllow? env command with
    | some reason => decided [] .allow reason
    | none =>
      let handoffDir := childPath env.controlRoot (".agent/tmp/" ++ env.sessionMode)
      decided [] .deny (readOnlyDenyReason env.sessionMode handoffDir)
  else if isProtectedWriteTarget command && hasWriteRedirectOrMutator command then
    decided [] .deny protectedWriteDenyReason
  else if isSecretBash command then
    decided [] .deny secretDenyReason
  else if isDeniedBash command then
    decided [] .deny commitDenyReason
  else
    let stateSubs := statePySubcommands command
    if isHumanOnlyBash command || stateSubs.contains "resume" then
      decided [] .deny humanOnlyDenyReason
    else if isLoopOnlyBash command
        || stateSubs.any (loopOnlyStateSubcommands.contains ·) then
      decided [] .deny loopOnlyDenyReason
    else match dangerousBashReason? command with
    | some pat => decided [] .deny (dangerousDenyReason pat)
    | none =>
      if commandLaunchesClaude command then
        decided [] .deny claudeLaunchDenyReason
      else if isAskBash command then
        decided [] .ask bootstrapAskReason
      else
        let highRiskTargets := bashHighRiskTargets env command
        let projectCwd := env.projectRoots.any (insideOf · env.base)
        let controlSurface := (!projectCwd && isControlSurfaceBashMutation command)
          || highRiskTargets.any (isControlPlaneTarget env)
        let zone := isZoneBashMutation command
        let staged := if zone && !controlSurface then highRiskTargets else []
        if controlSurface then
          decided staged .deny controlSurfaceBashDenyReason
        else if zone then
          decided staged .ask zoneBashAskReason
        else if isDependencyInputBashMutation command then
          decided staged .ask dependencyInputAskReason
        else match cdLeavesAllowedRoots? env command with
        | some target => decided staged .ask (unsafeCdAskReason target)
        | none =>
          match installAllowReason? env command with
          | some reason => decided staged .allow reason
          | none =>
            if commandInstallsDependencies command then
              decided staged .ask installAskReason
            else
              ⟨staged, none⟩

/-- `main()` 等価の純粋決定核(§3.3-2 の `GuardEnv → 入力 → 判定`)。 -/
def decide (env : GuardEnv) : ToolCall → GuardOutput
  | .write targetRaw => decideWrite env targetRaw
  | .bash command => decideBash env command
  | .other => ⟨[], none⟩

/-! ## コンパイル時検査(期待値は pre_tool_guard.py の実関数を CPython 3.14
実測。端到端の等価性は差分ファザー + 併走検証で担保済み — §31.2-19) -/

private def env0 : GuardEnv :=
  { controlRoot := "/ws/.mercator"
    projectRoots := ["/ws/proj"]
    sessionMode := ""
    base := "/ws/.mercator"
    handoffRoot := "/ws/.mercator/.agent/tmp/triage"
    expectedProject? := some "/ws/proj"
    stateScript := "/ws/.mercator/bin/mercator"
    declared := {}
    resolved :=
      [ ("", some "/ws/proj"),
        ("src/app.ts", some "/ws/proj/src/app.ts"),
        ("ESSENCE.md", some "/ws/proj/ESSENCE.md"),
        ("package.json", some "/ws/proj/package.json"),
        ("prompts/x.md", some "/ws/proj/prompts/x.md"),
        ("scripts/state.py", some "/ws/.mercator/scripts/state.py"),
        ("recipes/asl/files/loop/lean/lakefile.lean",
         some "/ws/.mercator/recipes/asl/files/loop/lean/lakefile.lean"),
        ("templates/project/package.json",
         some "/ws/.mercator/templates/project/package.json"),
        ("../proj", some "/ws/proj"),
        ("sub", some "/opt/elsewhere/sub") ] }

private def projectCwdEnv : GuardEnv :=
  { env0 with
    base := "/ws/proj"
    resolved := env0.resolved ++
      [ ("README.md", some "/ws/proj/README.md"),
        (".tmp-readme.md", some "/ws/proj/.tmp-readme.md"),
        ("note.md", some "/ws/proj/note.md"),
        ("../.mercator/README.md", some "/ws/.mercator/README.md") ] }

private def triageEnv : GuardEnv :=
  { env0 with
    sessionMode := "triage"
    settingsFile := "/ws/.mercator/.claude/settings.json"
    resolved := env0.resolved ++
      [ ("/ws/.mercator/.agent/tmp/triage/resume_note.txt",
         some "/ws/.mercator/.agent/tmp/triage/resume_note.txt"),
        ("/ws/.mercator/.agent/tmp/triage",
         some "/ws/.mercator/.agent/tmp/triage"),
        ("/ws/.mercator/bin/mercator",
         some "/ws/.mercator/bin/mercator"),
        ("/ws/.mercator/.claude/settings.json",
         some "/ws/.mercator/.claude/settings.json"),
        ("/ws/.mercator/../proj", some "/ws/proj") ] }

private def essenceNewEnv : GuardEnv :=
  { env0 with
    sessionMode := "essence"
    essenceMode := "new"
    settingsFile := "/ws/.mercator/.claude/settings.json"
    handoffRoot := "/ws/.mercator/.agent/tmp/essence"
    resolved := env0.resolved ++
      [ ("/ws/.mercator/.agent/tmp/essence/ESSENCE.draft.md",
         some "/ws/.mercator/.agent/tmp/essence/ESSENCE.draft.md"),
        ("/ws/.mercator/.claude/settings.json",
         some "/ws/.mercator/.claude/settings.json"),
        ("/ws/proj/ESSENCE.md", some "/ws/proj/ESSENCE.md"),
        ("/ws/proj/essences/brand-guide.pdf",
         some "/ws/proj/essences/brand-guide.pdf"),
        ("/ws/proj/essences", some "/ws/proj/essences"),
        ("/ws/proj/essences/sub/logo.png",
         some "/ws/proj/essences/sub/logo.png"),
        ("/ws/proj/essences/a/b/c/deep.png",
         some "/ws/proj/essences/a/b/c/deep.png") ] }

-- Decision.render(json.dumps 既定セパレータ・ensure_ascii=True と突合)
#guard (Decision.mk .deny "x").render
  == "{\"hookSpecificOutput\": {\"hookEventName\": \"PreToolUse\", \"permissionDecision\": \"deny\", \"permissionDecisionReason\": \"x\"}}"

-- WRITE_TOOLS: deny → ask(manifest)→ deny(control plane)→ ask(zone)→ 無意見
#guard decide env0 (.write "ESSENCE.md")
  == ⟨[], some ⟨.deny, writeDenyReason "ESSENCE.md"⟩⟩
#guard decide env0 (.write "essences/logo.png")
  == ⟨[], some ⟨.deny, writeDenyReason "essences/logo.png"⟩⟩
#guard decide env0 (.bash "cp x.png essences/x.png")
  == ⟨[], some ⟨.deny, protectedWriteDenyReason⟩⟩
#guard decide env0 (.write "package.json")
  == ⟨[], some ⟨.ask, manifestAskReason "package.json"⟩⟩
#guard decide env0 (.write "scripts/state.py")   -- 解決先が CONTROL_ROOT 配下
  == ⟨[], some ⟨.deny, controlPlaneDenyReason "scripts/state.py"⟩⟩
-- 制御プレーン面 ∩ 依存マニフェスト名: deny が ask に**先行**する(§11.3 /
-- §29.2 — レシピ原本の `lakefile.lean` は配布物に実在する重なりであり、
-- 旧順序では Edit だけが ask へ降格して Bash 面の deny と食い違っていた)
#guard decide env0 (.write "recipes/asl/files/loop/lean/lakefile.lean")
  == ⟨[], some ⟨.deny,
    controlPlaneDenyReason "recipes/asl/files/loop/lean/lakefile.lean"⟩⟩
#guard decide env0 (.write "templates/project/package.json")
  == ⟨[], some ⟨.deny, controlPlaneDenyReason "templates/project/package.json"⟩⟩
#guard decide env0 (.write "prompts/x.md")       -- zone は staging + ask
  == ⟨["prompts/x.md"], some ⟨.ask, zoneAskReason "prompts/x.md"⟩⟩
#guard decide env0 (.write "src/app.ts") == ⟨[], none⟩
#guard decide env0 .other == ⟨[], none⟩

-- Bash deny 群の順序(G-T1: dangerous は zone ask に降格しない)
#guard decide env0 (.bash "rm -rf prompts/")
  == ⟨[], some ⟨.deny, dangerousDenyReason "\\brm\\s+-rf\\b"⟩⟩
#guard decide env0 (.bash "echo x > .mercator/state/todo.json")
  == ⟨[], some ⟨.deny, protectedWriteDenyReason⟩⟩
#guard decide env0 (.bash "cat .env")
  == ⟨[], some ⟨.deny, secretDenyReason⟩⟩
#guard decide env0 (.bash "git add .")
  == ⟨[], some ⟨.deny, commitDenyReason⟩⟩
-- G-T3: フラグ先行綴りの resume / loop-only も deny(旧 python3 綴りの
-- 遮断も継続する — 緩和しない)
#guard decide env0 (.bash "python3 scripts/state.py --project ../proj resume")
  == ⟨[], some ⟨.deny, humanOnlyDenyReason⟩⟩
#guard decide env0 (.bash "bin/mercator state --project ../proj resume")
  == ⟨[], some ⟨.deny, humanOnlyDenyReason⟩⟩
#guard decide env0 (.bash "bin/mercator state resume --project ../proj")
  == ⟨[], some ⟨.deny, humanOnlyDenyReason⟩⟩
#guard decide env0 (.bash "just state --project x record-progress")
  == ⟨[], some ⟨.deny, loopOnlyDenyReason⟩⟩
#guard decide env0 (.bash "bin/mercator state --project x record-progress")
  == ⟨[], some ⟨.deny, loopOnlyDenyReason⟩⟩
#guard decide env0 (.bash "bash -c 'claude -p hi'")
  == ⟨[], some ⟨.deny, claudeLaunchDenyReason⟩⟩
#guard decide env0 (.bash "just bootstrap")
  == ⟨[], some ⟨.ask, bootstrapAskReason⟩⟩

-- Bash 変異の分類: 制御プレーン面は deny(staging なし)、zone は staging + ask
#guard decide env0 (.bash "tee scripts/state.py")
  == ⟨[], some ⟨.deny, controlSurfaceBashDenyReason⟩⟩
-- cwd = CONTROL_ROOT(env0.base)では素の README.md 綴りはテキスト検査が deny
#guard decide env0 (.bash "cp note.md README.md")
  == ⟨[], some ⟨.deny, controlSurfaceBashDenyReason⟩⟩
#guard decide env0 (.bash "tee prompts/x.md")
  == ⟨["/ws/proj/prompts/x.md"], some ⟨.ask, zoneBashAskReason⟩⟩
#guard decide env0 (.bash "echo x > package.json")
  == ⟨[], some ⟨.ask, dependencyInputAskReason⟩⟩

-- cwd = PROJECT_ROOT では同じ相対綴りが agent 所有の project ファイル(§11.1)を
-- 指すため、テキスト検査は適用されない(2026-07-31 の R-006 過剰遮断の是正)。
-- CONTROL_ROOT へ解決される綴りは解決済みパス判定が引き続き deny する。
#guard decide projectCwdEnv (.bash "cp .tmp-readme.md README.md") == ⟨[], none⟩
#guard decide projectCwdEnv (.bash "cp note.md ../.mercator/README.md")
  == ⟨[], some ⟨.deny, controlSurfaceBashDenyReason⟩⟩

-- cd フェンス(§11.2): 許可ルート外は ask、絶対 cd 先は未解決比較
#guard decide env0 (.bash "cd /opt && ls")
  == ⟨[], some ⟨.ask, unsafeCdAskReason "/opt"⟩⟩
#guard decide env0 (.bash "cd sub && ls")
  == ⟨[], some ⟨.ask, unsafeCdAskReason "/opt/elsewhere/sub"⟩⟩
#guard decide env0 (.bash "cd ../proj && ls") == ⟨[], none⟩

-- 依存ゲート(§11.2): materialization / 信頼済み install は allow、残りは ask
#guard (decide env0 (.bash "cd ../proj && pnpm install --frozen-lockfile")).decision?
  == some ⟨.allow, "Materialization (META.md §11.2): installs the manifest/lockfile already in the repository, naming no package of its own. The dependency set it expands was already gated when the manifest was written (manifest edits ask)."⟩
#guard (decide env0 (.bash "npm install typescript")).decision?
  == some ⟨.allow, "Trusted dependency install (META.md §11.2): typescript (npm) are all on the curated list or declared in the project's ESSENCE.md; anything else still requires the human."⟩
#guard decide env0 (.bash "npm install left-pad")
  == ⟨[], some ⟨.ask, installAskReason⟩⟩
#guard decide env0 (.bash "ls -la") == ⟨[], none⟩

-- read-only セッション(I-022/I-027): 許可 3 面と deny 文言
#guard decide triageEnv
    (.bash "cat > '/ws/.mercator/.agent/tmp/triage/resume_note.txt' <<'EOF'\nhi\nEOF")
  == ⟨[], some ⟨.allow, "triage read-only handoff write (I-022/I-027)"⟩⟩
#guard decide triageEnv (.bash "mkdir -p .agent/tmp/triage")
  == ⟨[], some ⟨.allow, "triage handoff directory creation (I-022/I-027)"⟩⟩
#guard decide triageEnv
    (.bash "bin/mercator state status --project ../proj")
  == ⟨[], some ⟨.allow, "triage read-only state inspection (I-022/I-027)"⟩⟩
#guard decide triageEnv (.bash "ls")
  == ⟨[], some ⟨.deny, readOnlyDenyReason "triage" "/ws/.mercator/.agent/tmp/triage"⟩⟩
#guard (readOnlyDenyReason "triage" "/cr/.agent/tmp/triage")
  == "triage is a read-only human session (I-022/I-027). Bash is limited to exact state inspection (bin/mercator state status|should-stop --project <bound-project>) and one single-command quoted heredoc into the wrapper-owned handoff directory — nothing chained before or after it (an optional `mkdir -p /cr/.agent/tmp/triage && ` prefix is the sole exception). To write the handoff, use the Write tool on /cr/.agent/tmp/triage/resume_note.txt, or run exactly:\ncat > '/cr/.agent/tmp/triage/resume_note.txt' <<'MERCATOR_HANDOFF'\n<content>\nMERCATOR_HANDOFF"

-- read-only セッションの WRITE_TOOLS 面(§13.6-3): handoff 内のみ allow、
-- それ以外(project・deny-pattern 該当を含む)は教示付き deny が deny 群に先行
#guard decide triageEnv
    (.write "/ws/.mercator/.agent/tmp/triage/resume_note.txt")
  == ⟨[], some ⟨.allow, "triage read-only handoff write (I-022/I-027)"⟩⟩
#guard decide triageEnv (.write "src/app.ts")
  == ⟨[], some ⟨.deny,
    readOnlyWriteDenyReason "triage" "/ws/.mercator/.agent/tmp/triage"⟩⟩
#guard decide triageEnv (.write "ESSENCE.md")
  == ⟨[], some ⟨.deny,
    readOnlyWriteDenyReason "triage" "/ws/.mercator/.agent/tmp/triage"⟩⟩
#guard decide triageEnv (.write "/ws/.mercator/.agent/tmp/triage")  -- root 自身は不可
  == ⟨[], some ⟨.deny,
    readOnlyWriteDenyReason "triage" "/ws/.mercator/.agent/tmp/triage"⟩⟩
#guard (readOnlyWriteDenyReason "triage" "/cr/.agent/tmp/triage")
  == "triage is a read-only human session (I-022/I-027): the only freely writable path is the wrapper-owned handoff directory /cr/.agent/tmp/triage/. Write the handoff with the Write tool to /cr/.agent/tmp/triage/resume_note.txt (supporting drafts may use other names inside the same directory). Beyond the handoff, the only human-approvable (ask) write surface is the live settings file .claude/settings.json (deployment repair, META.md §28.5-3); everything else is denied."
#guard (readOnlyWriteDenyReason "essence" "/cr/.agent/tmp/essence" true)
  == "essence is a read-only human session (I-022/I-027): the only freely writable path is the wrapper-owned handoff directory /cr/.agent/tmp/essence/. Write the handoff with the Write tool to /cr/.agent/tmp/essence/ESSENCE.draft.md (supporting drafts may use other names inside the same directory). Beyond the handoff, the only human-approvable (ask) write surfaces are the live settings file .claude/settings.json (deployment repair, META.md §28.5-3), PROJECT_ROOT/ESSENCE.md (interview fallback install, I-027 second path), and files under PROJECT_ROOT/essences/ up to 3 path segments deep (asset fallback install, same path — §2.1.5); everything else is denied."

-- read-only セッションの ask 面(§28.5-3 / I-027 第二経路): live settings は
-- 両モード ask、ESSENCE.md 直接設置は essence-new のみ ask。handoff allow が
-- ask 面に先行する。
#guard decide triageEnv (.write "/ws/.mercator/.claude/settings.json")
  == ⟨[], some ⟨.ask, liveSettingsAskReason "triage"⟩⟩
#guard decide essenceNewEnv (.write "/ws/.mercator/.claude/settings.json")
  == ⟨[], some ⟨.ask, liveSettingsAskReason "essence"⟩⟩
#guard decide essenceNewEnv (.write "/ws/proj/ESSENCE.md")
  == ⟨[], some ⟨.ask, essenceDirectInstallAskReason⟩⟩
#guard decide essenceNewEnv
    (.write "/ws/.mercator/.agent/tmp/essence/ESSENCE.draft.md")
  == ⟨[], some ⟨.allow, "essence read-only handoff write (I-022/I-027)"⟩⟩
-- essences/ 資産設置面(I-027 第二経路の §2.1.5 面): essence-new のみ、
-- 最大 3 階層までのファイルが ask。root 自身・上限超過・update/triage は
-- 教示付き deny
#guard decide essenceNewEnv (.write "/ws/proj/essences/brand-guide.pdf")
  == ⟨[], some ⟨.ask, essenceAssetInstallAskReason⟩⟩
#guard decide essenceNewEnv (.write "/ws/proj/essences/sub/logo.png")
  == ⟨[], some ⟨.ask, essenceAssetInstallAskReason⟩⟩
#guard decide essenceNewEnv (.write "/ws/proj/essences")
  == ⟨[], some ⟨.deny,
    readOnlyWriteDenyReason "essence" "/ws/.mercator/.agent/tmp/essence" true⟩⟩
#guard decide essenceNewEnv (.write "/ws/proj/essences/a/b/c/deep.png")
  == ⟨[], some ⟨.deny,
    readOnlyWriteDenyReason "essence" "/ws/.mercator/.agent/tmp/essence" true⟩⟩
#guard decide { essenceNewEnv with essenceMode := "update" }
    (.write "/ws/proj/essences/brand-guide.pdf")
  == ⟨[], some ⟨.deny,
    readOnlyWriteDenyReason "essence" "/ws/.mercator/.agent/tmp/essence"⟩⟩
-- update モード(essenceMode ≠ "new")では ESSENCE.md 直接設置 fallback は
-- 立たず、教示付き deny(ask 面の列挙は settings のみ)。
#guard decide { essenceNewEnv with essenceMode := "update" }
    (.write "/ws/proj/ESSENCE.md")
  == ⟨[], some ⟨.deny,
    readOnlyWriteDenyReason "essence" "/ws/.mercator/.agent/tmp/essence"⟩⟩
-- triage では ESSENCE.md は従来どおり deny(fallback は essence-new 限定)。
#guard decide triageEnv (.write "/ws/proj/ESSENCE.md")
  == ⟨[], some ⟨.deny,
    readOnlyWriteDenyReason "triage" "/ws/.mercator/.agent/tmp/triage"⟩⟩
-- settingsFile 未設定(旧 shadow 互換の GuardEnv)では settings ask 面は
-- 立たない(空文字列ガード)。
#guard decide { triageEnv with settingsFile := "" }
    (.write "/ws/.mercator/.claude/settings.json")
  == ⟨[], some ⟨.deny,
    readOnlyWriteDenyReason "triage" "/ws/.mercator/.agent/tmp/triage"⟩⟩
-- resume は read-only の state 読み取り面をすり抜けない
#guard (decide triageEnv
    (.bash "bin/mercator state resume --project ../proj")).decision?
  == some ⟨.deny, readOnlyDenyReason "triage" "/ws/.mercator/.agent/tmp/triage"⟩
-- 旧 python3 綴りは triage の受理形に含まれない(deny 側)
#guard (decide triageEnv
    (.bash "python3 scripts/state.py status --project ../proj")).decision?
  == some ⟨.deny, readOnlyDenyReason "triage" "/ws/.mercator/.agent/tmp/triage"⟩

-- cd_targets の finditer 意味論(^ 直置きのみ・separator 再開・shlex 先頭)
#guard cdRawCaptures "cd /opt && ls" == ["/opt "]
#guard cdRawCaptures " cd /opt" == []        -- ^ 代替に \s* はない
#guard cdRawCaptures "ls; cd a; cd 'b c'" == ["a", "'b c'"]
#guard cdFirstTokens "ls; cd a; cd 'b c'" == ["a", "b c"]
#guard cdRawCaptures "echo cd x" == []       -- セグメント頭でない cd
#guard cdRawCaptures "ls\ncd sub" == ["sub"]

-- 解決要求の列挙(IO シェルの契約面)
#guard familyARequests (.write "src/app.ts") == ["src/app.ts"]
#guard familyARequests (.write "/abs/p.md") == []
#guard familyARequests (.bash "tee prompts/x.md; cd sub")
  == ["prompts/x.md", "sub"]
#guard familyARequests (.bash "cd ../proj && npm install typescript")
  == ["../proj", "../proj"]
#guard familyBRequests "/cr" "" (.bash "cat > x <<'EOF'\nhi\nEOF") == []
#guard familyBRequests "/cr" "essence" (.bash "cat > x <<'EOF'\nhi\nEOF")
  == ["/cr/x"]
#guard familyBRequests "/cr" "triage"
    (.bash "bin/mercator state status --project ../proj")
  == ["/cr/bin/mercator", "/cr/../proj"]
#guard familyBRequests "/cr" "triage"
    (.bash "python3 scripts/state.py status --project ../proj") == []
#guard familyBRequests "/cr" "triage" (.write "note.txt") == ["/cr/note.txt"]
#guard familyBRequests "/cr" "essence" (.write "/abs/x.md") == ["/abs/x.md"]
#guard familyBRequests "/cr" "" (.write "note.txt") == []

end Mercator.Guard
