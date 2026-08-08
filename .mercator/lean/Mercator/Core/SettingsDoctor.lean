import Mercator.Core.Json
import Mercator.Core.Path
import Mercator.Core.Classify.Profile

/-!
`Mercator.Core.SettingsDoctor` — doctor の `.claude/settings.json` 安全配線検査の
純粋核。

launcher スクリプトのソース断片検査は JSON を介さない grep 相当なので
doctor.sh 側の `grep -qF` に残る — 本核は settings の構造検査だけを持つ。
control-plane Edit deny は §11.3 列挙が正で、一括 deny(`Edit(./**)` /
絶対綴りの等価形)は CLI >=2.1.216 で .agent/tmp の handoff/lock 書込みを
3 層で塞ぐため(§28.5)stale 配線として診断する。

パスルールは control-plane 側も含め**すべて解決済み絶対 `//<abs>` 綴り**
(§19.1-5): `../` 相対は黙ってどれにもマッチせず、cwd 相対
(`Edit(./README.md)` 等)は additionalDirectories 配下の同名ファイルへ
過剰マッチする(bound 配備で PROJECT_ROOT/README.md への全書込みを塞いだ
2026-07-31 の実障害)。旧配備に残る相対 control ルールはこの検査が
stale 配線として報告する。

旧インライン Python 実装(`SETTINGS_ISSUES`)との裁定済み意図差(いずれも
「診断が出る」厳格側。§4.1 一般原則):

- 旧実装は `PROJECT_ROOT` と `additionalDirectories` を `Path.resolve()`
  (symlink 解決)で突き合わせたが、本核は字句正規化(`Core.Path.abspath`)のみで
  比較する。`resolve_project` と init の描画は同一の解決済み絶対パスを共有する
  ため実運用で差は出ず、symlink を挟む手書き設定だけが不一致(= fail 報告)側に
  倒れる。
- 旧実装は配列内の非文字列エントリ等で TypeError を起こし、doctor が空出力
  (= 偽 ok)になった。本核は非文字列を無視して検査を続行する。
- `{x!r}` 埋め込みは常にシングルクォート囲みで再現する(Python の repr は
  値が `'` を含むと二重引用符へ切り替えるが、対象はパス・ルール文字列で
  `'` は現れない)。
-/

namespace Mercator.Core.SettingsDoctor

open Mercator.Core.Json (Value)
open Mercator.Core.Classify (Profile projectAskSurfaces)

/-- Python `{s!r}` の再現(シングルクォート固定。ヘッダの意図差参照)。 -/
private def reprStr (s : String) : String := "'" ++ s ++ "'"

/-- Python の `str` リスト repr(`['a', 'b']`)。 -/
private def reprStrList (items : List String) : String :=
  "[" ++ String.intercalate ", " (items.map reprStr) ++ "]"

/-- `sub` を部分文字列として含むか(Python `in`)。 -/
private def containsSubstr (s sub : String) : Bool :=
  (s.splitOn sub).length > 1

/-- 配列の文字列要素(非文字列は無視 — ヘッダの意図差参照)。非配列は `[]`。 -/
private def strItems : Value → List String
  | .arr items => items.filterMap Value.asStr?
  | _ => []

private def isList : Value → Bool
  | .arr _ => true
  | _ => false

/-- `^[A-Za-z]+\((.*)\)$` 相当: 先頭の英字列に `(` が続き `)` で終わる形から
括弧内(末尾 `)` の手前まで)を取り出す。 -/
private def rulePath? (rule : String) : Option String :=
  let chars := rule.toList
  let letters := chars.takeWhile fun c => ('A' ≤ c && c ≤ 'Z') || ('a' ≤ c && c ≤ 'z')
  if letters.isEmpty then none
  else
    match chars.drop letters.length with
    | '(' :: tail =>
      if tail.getLast? == some ')' then some (String.ofList tail.dropLast) else none
    | _ => none

/-- hooks のイベント値(group 配列)から `command` 文字列を列挙する。
非文字列 `command` は `""`(置換元の `hook.get("command", "")` と同じ既定)。 -/
private def groupCommands : Value → List String
  | .arr groups => groups.flatMap fun g =>
    match g.get? "hooks" with
    | some (.arr hs) => hs.map fun h => (h.get? "command" |>.bind Value.asStr?).getD ""
    | _ => []
  | _ => []

/-- 5 イベントの必須配線断片(META.md §31.2-42 の本切替後の姿)。 -/
private def expectedHooks : List (String × String) :=
  [("SessionStart", "/bin/mercator hook session-start"),
   ("PreToolUse", "/bin/mercator hook pre-tool"),
   ("PostToolUse", "/bin/mercator hook post-tool"),
   ("PreCompact", "/bin/mercator hook pre-compact"),
   ("Stop", "/bin/mercator hook stop")]

/-- settings.json の安全配線検査。`project` は解決済み PROJECT_ROOT、
`control` は CONTROL_ROOT、`cwd` は `additionalDirectories` の相対エントリの
解決基準(doctor の CWD = CONTROL_ROOT)。issue を検出順に返す。

`profile` は ESSENCE 宣言の実行 profile(§11.5、`util essence-profile` の
出力。既定 standard = 後方互換)。検査は「宣言 → 期待される実態」の対称
3 分岐で照合する: standard は project 側 ask 3 面あり ∧ sandbox.enabled、
auto-approve は ask 3 面なし ∧ enabled、unsandboxed は ask 3 面なし ∧
enabled=false。他の sandbox 検査(failIfUnavailable / network / filesystem)
は全 profile 共通である。rendered settings への専用マーカー埋め込みは
置かない — 宣言の二重管理と mismatch の新クラスを生むだけである(§11.5)。 -/
def check (settings : Value) (project control cwd : String)
    (profile : Profile := .standard) : List String := Id.run do
  let mut issues : Array String := #[]

  let permissions := (settings.get? "permissions").getD (.obj [])
  if permissions.get? "defaultMode" != some (.str "dontAsk") then
    issues := issues.push "permissions.defaultMode must be 'dontAsk' (fail-closed baseline)"
  if permissions.get? "disableBypassPermissionsMode" != some (.str "disable") then
    issues := issues.push "permissions.disableBypassPermissionsMode must be 'disable'"
  let permissionDeny := strItems ((permissions.get? "deny").getD .null)
  if !permissionDeny.any (·.startsWith "Bash(claude ") then
    issues := issues.push "permissions.deny must block direct nested `claude` launches (§10)"
  -- §11.3 の control-plane 面の列挙 deny(+ bin / lean)。ルールは解決済み
  -- 絶対 `//<abs>` 綴り(§19.1-5): cwd 相対の `Edit(./README.md)` 等は
  -- additionalDirectories(= PROJECT_ROOT)配下の同名ファイルへ過剰マッチし、
  -- agent 所有の通常実装ファイル(§11.1)への全書込みを塞ぐ(2026-07-31 の
  -- 実障害)。一括 `Edit(<CONTROL_ROOT>/**)` は使えない: Claude Code
  -- >=2.1.216 では Edit deny が Write ツール・Bash の書込先解析・sandbox
  -- プロファイルの 3 層へ波及し、hook allow より常に優先されるため、
  -- .agent/tmp の handoff / single-flight lock 書込みをすべて塞ぐ(§28.5)。
  -- `.claude/**` も同じ理由で一括にできない: settings.json は read-only
  -- セッションの人間承認付き修復面(ask、§28.5-3)なので、`.claude` は
  -- サブ面の列挙 deny + settings.json の ask で書く。
  for surface in ["CLAUDE.md", ".claude/agents/**", ".claude/commands/**",
      ".claude/rules/**", ".claude/skills/**", "scripts/**",
      "templates/**", "recipes/**", "META.md",
      "README.md", "justfile", ".agent/prompts/**",
      ".agent/state/**", "bin/**", "lean/**"] do
    let rule := s!"Edit(/{control}/{surface})"
    if !permissionDeny.contains rule then
      issues := issues.push
        s!"permissions.deny must contain {reprStr rule} (immutable CONTROL_ROOT, §11.3)"
  for blanket in ["Edit(./**)", s!"Edit(/{control}/**)"] do
    if permissionDeny.contains blanket then
      issues := issues.push <|
        s!"permissions.deny must not blanket-deny CONTROL_ROOT ({reprStr blanket}): on " ++
        "Claude Code >=2.1.216 it also covers Write, Bash write targets, and the " ++
        "sandbox profile, overriding hook allows — it blocks every .agent/tmp " ++
        "handoff/lock write; enumerate the §11.3 surfaces instead (§28.5)"
  for blanket in ["Edit(./.claude/**)", s!"Edit(/{control}/.claude/**)"] do
    if permissionDeny.contains blanket then
      issues := issues.push <|
        s!"permissions.deny must not blanket-deny .claude ({reprStr blanket}): " ++
        "a deny always outranks the hook's ask, so it closes the human-approved " ++
        "settings repair surface (.claude/settings.json, §28.5-3); enumerate the " ++
        ".claude subsurfaces and keep settings.json on ask instead (§28.5)"

  let permissionAllow := strItems ((permissions.get? "allow").getD .null)
  let permissionAsk := strItems ((permissions.get? "ask").getD .null)
  -- §28.5-3: read-only セッションの人間承認付き settings 修復面。ask に無いと
  -- 対話 permission mode 依存になり、宣言的な床が失われる。
  let liveSettingsAsk := s!"Edit(/{control}/.claude/settings.json)"
  if !permissionAsk.contains liveSettingsAsk then
    issues := issues.push <|
      s!"permissions.ask must contain {reprStr liveSettingsAsk} (human-" ++
      "approved live-settings repair surface for read-only sessions, §28.5-3)"
  -- §11.5 の対称 3 分岐(project 側 ask 3 面): standard は存在が床、relaxed
  -- 2 態は不在が床 — settings の ask は hook の allow に常に勝つため、残すと
  -- profile が該当面で無効化される。面の列挙は derive と共有の単一定義点
  -- (`Classify.projectAskSurfaces`)。
  for surface in projectAskSurfaces do
    let rule := s!"Edit(/{project}/{surface})"
    if profile == .standard then
      if !permissionAsk.contains rule then
        issues := issues.push <|
          s!"permissions.ask must contain {reprStr rule} (project agent-" ++
          "runtime ask floor, §16.1; declared profile 'standard')"
    else
      if permissionAsk.contains rule then
        issues := issues.push <|
          s!"permissions.ask must not contain {reprStr rule} (declared " ++
          s!"profile '{profile.tag}' removes the project ask surfaces — a " ++
          "settings ask outranks the hook's allow, §11.5; re-run init)"
  -- §19.1-5 / §28.5: パスルールは control-plane 側も含めすべて解決済み絶対
  -- (`//<abs>` か `~`)。相対ルールは CLI 依存の基準で解決される — `../` 形は
  -- 黙ってどれにもマッチせず、cwd 相対形は additionalDirectories 配下の
  -- 同名ファイルへ過剰マッチする(2026-07-31 の実障害)。
  let relativePathRules :=
    (permissionAllow ++ permissionAsk ++ permissionDeny).filter fun rule =>
      !rule.startsWith "Bash(" &&
        (rulePath? rule).any fun inner =>
          !inner.startsWith "/" && !inner.startsWith "~"
  if !relativePathRules.isEmpty then
    issues := issues.push <|
      "permissions path rules must use the resolved-absolute `//<abs>` (or " ++
      "`~`) spelling; relative rules resolve against a CLI-dependent base — " ++
      "`../` forms silently never match, and cwd-relative forms over-match " ++
      "same-named files under additionalDirectories (§19.1-5, §28.5): " ++
      s!"{reprStrList relativePathRules}"
  let projectPerm := "/" ++ project
  if !permissionAllow.any (containsSubstr · projectPerm) then
    issues := issues.push <|
      "permissions.allow must grant project access via the absolute " ++
      s!"`//<abs>` spelling containing {reprStr projectPerm}; a relative " ++
      "`Edit(../PROJECT/**)` grants nothing (§19.1-5, §28.5)"

  let sandbox := (settings.get? "sandbox").getD (.obj [])
  -- §11.5 の対称 3 分岐(sandbox): unsandboxed だけが enabled=false を期待
  -- する。他の sandbox 検査(failIfUnavailable / network / filesystem)は
  -- 全 profile 共通 — sandbox を降ろした配備でも宣言の床は陳腐化させない。
  if profile == .unsandboxed then
    if sandbox.get? "enabled" != some (.bool false) then
      issues := issues.push
        "sandbox.enabled must be false (declared profile 'unsandboxed', §11.5; re-run init)"
  else
    if sandbox.get? "enabled" != some (.bool true) then
      issues := issues.push "sandbox.enabled must be true"
  if sandbox.get? "failIfUnavailable" != some (.bool true) then
    issues := issues.push "sandbox.failIfUnavailable must be true (never degrade to unsandboxed Bash)"
  if sandbox.get? "autoAllowBashIfSandboxed" != some (.bool false) then
    issues := issues.push "sandbox.autoAllowBashIfSandboxed must be false"
  if sandbox.get? "allowUnsandboxedCommands" != some (.bool false) then
    issues := issues.push "sandbox.allowUnsandboxedCommands must be false"
  let requiredNetworkDomains := [
    "github.com", "api.github.com", "raw.githubusercontent.com",
    "objects.githubusercontent.com", "registry.npmjs.org", "pypi.org",
    "files.pythonhosted.org", "crates.io", "static.crates.io",
    "index.crates.io", "proxy.golang.org", "sum.golang.org",
    "releases.lean-lang.org"]
  let network := (sandbox.get? "network").getD (.obj [])
  let allowedDomainsV := (network.get? "allowedDomains").getD (.arr [])
  let allowedDomains := strItems allowedDomainsV
  if !isList allowedDomainsV then
    issues := issues.push "sandbox.network.allowedDomains must be a list"
  else
    for domain in requiredNetworkDomains do
      if !allowedDomains.contains domain then
        issues := issues.push s!"sandbox.network.allowedDomains must include {domain}"
    if allowedDomains.any (· == "*") then
      issues := issues.push "sandbox.network.allowedDomains must not contain the global '*' wildcard"
  let filesystem := (sandbox.get? "filesystem").getD (.obj [])
  match filesystem with
  | .obj _ =>
    let allowWriteV := (filesystem.get? "allowWrite").getD (.arr [])
    if !isList allowWriteV then
      issues := issues.push "sandbox.filesystem.allowWrite must be a list"
    else
      -- state と single-flight ロックの唯一の可変制御プレーン面。
      if !(strItems allowWriteV).contains s!"{control}/.agent/tmp" then
        issues := issues.push <|
          "sandbox.filesystem.allowWrite must permit CONTROL_ROOT/.agent/tmp " ++
          s!"({control}/.agent/tmp) for state and single-flight locks"
    let denyReadV := (filesystem.get? "denyRead").getD (.arr [])
    let denyRead := strItems denyReadV
    if !isList denyReadV || !denyRead.any (·.endsWith "/.env") then
      issues := issues.push "sandbox.filesystem.denyRead must protect PROJECT_ROOT/.env"
    for prot in ["~/.ssh", "~/.aws", "~/.config/gcloud", "~/.kube", "~/.claude", "~/.claude.json"] do
      if !isList denyReadV || !denyRead.contains prot then
        issues := issues.push s!"sandbox.filesystem.denyRead must protect {prot}"
    let denyWriteV := (filesystem.get? "denyWrite").getD (.arr [])
    let denyWrite := strItems denyWriteV
    if !isList denyWriteV || !denyWrite.any (·.endsWith "/ESSENCE.md") then
      issues := issues.push "sandbox.filesystem.denyWrite must protect PROJECT_ROOT/ESSENCE.md"
    for prot in ["CLAUDE.md", ".claude", "scripts", "templates", "recipes", "META.md", ".agent/state", "bin", "lean"] do
      if !isList denyWriteV || !denyWrite.contains s!"{control}/{prot}" then
        issues := issues.push s!"sandbox.filesystem.denyWrite must protect CONTROL_ROOT/{prot}"
    -- §28.5: sandbox filesystem パスは解決済み絶対(または ~)でなければ、
    -- CLI 依存の基準に対して黙って誤った場所を allow/protect する。
    let relativeSandboxPaths :=
      ([allowWriteV, denyReadV, denyWriteV].filter isList).flatMap strItems
        |>.filter fun entry => !entry.startsWith "/" && !entry.startsWith "~"
    if !relativeSandboxPaths.isEmpty then
      issues := issues.push <|
        "sandbox.filesystem paths must be resolved absolute (or ~) paths; " ++
        "relative entries resolve against a CLI-dependent base and silently " ++
        s!"allow/protect the wrong directory (§28.5): {reprStrList relativeSandboxPaths}"
  | _ =>
    issues := issues.push "sandbox.filesystem must be an object"

  let dirsV := (permissions.get? "additionalDirectories").getD (.arr [])
  match dirsV with
  | .arr items =>
    -- ちょうど 1 エントリ = PROJECT_ROOT: 余分なディレクトリは束縛外への
    -- ファイルアクセスを与える(1 control plane = 1 project、§16.1, §26.1)。
    let resolved := items.map fun d =>
      match d.asStr? with
      | some s => Path.abspath cwd s
      | none => ""
    if resolved.length != 1 || !resolved.contains project then
      issues := issues.push <|
        s!"additionalDirectories must be exactly [PROJECT_ROOT] ({project}); " ++
        s!"got {reprStrList (strItems dirsV)}"
  | _ =>
    issues := issues.push "permissions.additionalDirectories must be a list"

  -- 本切替後の配線(META.md §31.2-42): 全 5 イベントが `bin/mercator hook <event>`。
  let hooks := (settings.get? "hooks").getD (.obj [])
  for (event, fragment) in expectedHooks do
    let commands := groupCommands ((hooks.get? event).getD .null)
    if !commands.any (containsSubstr · fragment) then
      issues := issues.push s!"hooks.{event} must invoke a command containing {reprStr fragment}"
  let hookEntries := match hooks with | .obj entries => entries | _ => []
  for (_, groupList) in hookEntries do
    for command in groupCommands groupList do
      if containsSubstr command "python3" || containsSubstr command "MERCATOR_GUARD_SHADOW" then
        issues := issues.push s!"stale pre-cutover hook wiring (META.md §31.2-42): {reprStr command}"

  return issues.toList

end Mercator.Core.SettingsDoctor
