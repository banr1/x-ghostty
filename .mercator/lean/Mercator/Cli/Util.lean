import Mercator.Core.Json
import Mercator.Core.StaticConfig
import Mercator.Core.Stop
import Mercator.Core.Settings
import Mercator.Core.SettingsDoctor
import Mercator.Core.Path
import Mercator.Core.Render
import Mercator.Core.ProjectIndex
import Mercator.Core.Runs
import Mercator.Core.Classify.Profile
import Mercator.State.Model
import Mercator.Io.Fs
import Mercator.Io.Clock

/-!
`Mercator.Cli.Util` — シェルスクリプトが依存する小さな判定・抽出サブコマンド群
(R-7: シェル内に判定ロジックを書かず `mercator util <subcmd>` へ収容する)。

- `json-get <keypath> [--file <p>] [--default <s>] [--join <sep>] [--lenient]`
  JSON(stdin または `--file`)からドット区切りキーパスの値を 1 行で出力。
  欠落・null は `--default`(既定は空文字)。`--lenient` は読取不能・パース
  失敗・型不整合もすべて default へ倒す(fail-open。旧 `read_validation_status`
  の except-全捕捉に対応)。無指定時のエラーは stderr + exit 2(fail-closed)。
  Python の `dict.get(k, default)` は「キーはあるが null」を default に
  倒さないが、本実装は null も default に写す(state.py 出力に「null の
  status/message」は現れないため実挙動は同一。厳密には意図差として凍結)。
- `stop-status`  stdin の should-stop payload から Run-Status を 1 行出力
  (旧 `stop_run_status_from_json`。優先順の定義は `Core.Stop` の一箇所のみ
  = D-005 の複製消滅)。
- `token`  `/dev/urandom` の 32 バイトを 64 桁 hex で出力
  (旧 `secrets.token_hex(32)`)。
- `file-age-exceeds <path> <seconds>`  mtime からの経過が `<seconds>` を超えて
  いれば exit 0、さもなくば exit 1。stat 失敗(消滅)も exit 0(= stale 扱い、
  旧 `loop_lock_is_stale_by_age` の OSError 分岐)。比較は秒精度(旧実装は
  float 秒。用途はレース緩和ヒューリスティックで 1 秒未満の差は無害)。
- `read-only-settings <project> <control> <handoff> [essence-new]`  3 パスを
  実体解決して I-022/I-027 のセッション設定 JSON を 1 行出力(構築は
  `Core.Settings`)。第 4 引数 `essence-new` は new-Essence インタビューの
  variant(対象一括 Edit deny の代わりに ESSENCE.md を ask、§2.1.4)。
  旧 Python の `Path.resolve()`(strict=False)と違い不存在パスは解決できず
  exit 2 に倒す(厳格側)— 呼び出し元は 3 パスとも直前に存在を保証している。

init / bootstrap / doctor 向け:

- `relpath <path> <start>`  `os.path.relpath(path, start)` 互換。両引数を
  cwd 基準で `abspath`(字句正規化のみ・symlink 非解決)してから相対化。
- `render <src> <dst> <mode> --title T --rel R --abs A --control-abs C`
  init のバインドテンプレート描画。検証は書き込み前、置換はアトミック
  (`.render.<pid>.tmp` → rename)。json モードは描画結果の JSON 妥当性を
  検証してから置く。エラーは exit 2(旧 SystemExit の exit 1 と同じ die 側)。
- `seed <src> <dst> [--replace TOKEN=VALUE]...`  逐次トークン置換シード
  (bootstrap の seed / init の workspace README)。--replace なしは verbatim
  コピー。アトミック(`.seed.<pid>.tmp` → rename)。
- `project-index other|prune <index> <target> <control>`  §8.1 registry の
  1:1 ガード(`other` は target 以外の登録を `title:root` で出力、`prune` は
  それを明示 null に落として書き戻す)。index が読めない・パース不能は
  旧実装同様 no-op の exit 0(呼び出し元 ensure が上書き再構築する前段の
  ガードであり fail-open が仕様)。`project_root` が truthy 非文字列の
  壊れ形は exit 2(旧実装は TypeError で init ごと die。同じ停止側)。
  存在しない登録先パスは実体解決の代わりに字句解決へフォールバック
  (旧 `resolve(strict=False)` との差は「不一致 = other 扱い」の厳格側)。
- `json-check <file>`  JSON として読めれば exit 0、さもなくば exit 1
  (述語。doctor の parse 診断)。
- `dangling-run <runs.jsonl>`  未終了 run の走査(`Core.Runs`)。
  `__UNREADABLE__` / 最後に開いた run_id / 空行のいずれかを出力し exit 0。

doctor の settings 検査:

- `settings-doctor <settings.json> <project> <control> [<profile>]`  doctor の
  `.claude/settings.json` 安全配線検査(検査本体は `Core.SettingsDoctor`)。
  第 4 引数は ESSENCE 宣言の実行 profile(§11.5。省略 = standard、
  閉集合外の値は usage + exit 2)。issue を 1 行ずつ stdout に出力し常に
  exit 0(空出力 = 検査全通過。doctor.sh の `report_issues` が集約する)。
  パース不能・読取不能も「is not valid JSON」の issue 1 行(置換元インライン
  Python の except 分岐と同じ扱い)。
- `essence-profile <essence-path>`  ESSENCE.md の `profile:` 宣言(§11.5)を
  読み、発効値(standard / auto-approve / unsandboxed)を 1 行出力する。
  不在・読取不能・不正 UTF-8・placeholder(§13.1-8 と同一判定)は
  `standard` + exit 0(最厳格への縮退)。invalid 値・conflict は stderr +
  exit 2 — init はこの拒否で緩和方向の誤発効を止める(§26)。

静的設定の Lean 昇格(META.md §8.1、D-008):

- `static-config {workspace|project-index-seed}`  静的設定 SSOT
  (`Core.StaticConfig`)の rendered バイト列を stdout へ出力するだけの
  純 render 面(`util render` / `util seed` の隣)。maintainer の
  `just render-static` と doctor の drift 検査が消費する。未知の名前は
  usage + exit 2。
-/

namespace Mercator.Cli.Util

open Mercator

private def usage : String :=
  "usage: mercator util {json-get|stop-status|token|file-age-exceeds|read-only-settings|relpath|render|seed|project-index|json-check|dangling-run|settings-doctor|essence-profile|static-config} ..."

/-! ## json-get -/

private structure JsonGetArgs where
  keypath : List String
  file? : Option String := none
  dflt : String := ""
  join? : Option String := none
  lenient : Bool := false

private def parseJsonGetArgs (args : List String) : Option JsonGetArgs :=
  go args none {keypath := []}
where
  go : List String → Option String → JsonGetArgs → Option JsonGetArgs
    | [], some keypath, acc => some { acc with keypath := keypath.splitOn "." }
    | [], none, _ => none
    | "--file" :: v :: rest, kp, acc => go rest kp { acc with file? := some v }
    | "--default" :: v :: rest, kp, acc => go rest kp { acc with dflt := v }
    | "--join" :: v :: rest, kp, acc => go rest kp { acc with join? := some v }
    | "--lenient" :: rest, kp, acc => go rest kp { acc with lenient := true }
    | positional :: rest, none, acc =>
      if positional.startsWith "--" then none else go rest (some positional) acc
    | _ :: _, some _, _ => none

/-- キーパスの値の 1 行文字列化(純粋核)。欠落・null → default、配列は
`--join` があるときだけ連結(要素は文字列のみ)、object は常にエラー。 -/
def jsonGetOutput (root : Core.Json.Value) (keypath : List String)
    (dflt : String) (join? : Option String) : Except String String :=
  match root.getPath? keypath with
  | none | some .null => .ok dflt
  | some (.str s) => .ok s
  | some (.bool b) => .ok (if b then "true" else "false")
  | some (.num m e) => .ok (Core.Json.Value.num m e).render
  | some (.arr items) =>
    match join? with
    | none => .error "value is an array; pass --join <sep>"
    | some sep => do
      let strs ← items.mapM fun v =>
        match v.asStr? with
        | some s => Except.ok s
        | none => Except.error "array contains a non-string element"
      pure (String.intercalate sep strs)
  | some (.obj _) => .error "value is an object, not a scalar"

#guard (jsonGetOutput (.obj [("mode", .str "steering")]) ["mode"] "" none).toOption
    == some "steering"
#guard (jsonGetOutput (.obj [("mode", .null)]) ["mode"] "" none).toOption == some ""
#guard (jsonGetOutput (.obj []) ["status"] "unknown" none).toOption == some "unknown"
#guard (jsonGetOutput (.obj [("a", .obj [("b", .bool true)])])
    ["a", "b"] "" none).toOption == some "true"
#guard (jsonGetOutput (.obj [("runs", .arr [.str "R-1", .str "R-2"])])
    ["runs"] "" (some ",")).toOption == some "R-1,R-2"
#guard (jsonGetOutput (.obj [("runs", .arr [])]) ["runs"] "" (some ",")).toOption
    == some ""
#guard (jsonGetOutput (.obj []) ["runs"] "" (some ",")).toOption == some ""
#guard (jsonGetOutput (.obj [("a", .arr [.num 1 0])]) ["a"] "" (some ",")).isOk
    == false
#guard (jsonGetOutput (.obj [("a", .obj [])]) ["a"] "" none).isOk == false

private def runJsonGet (args : List String) : IO UInt32 := do
  let some parsed := parseJsonGetArgs args
    | do
      IO.eprintln "usage: mercator util json-get <keypath> [--file <path>] [--default <value>] [--join <sep>] [--lenient]"
      pure 2
  let text? : Option String ← match parsed.file? with
    | some f => Io.Fs.readFile? f
    | none =>
      try
        pure (some (← (← IO.getStdin).readToEnd))
      catch _ =>
        pure none
  let result : Except String String := do
    let some text := text?
      | .error (match parsed.file? with
          | some f => s!"cannot read {f}"
          | none => "cannot read stdin")
    let root ← Core.Json.parse text
    jsonGetOutput root parsed.keypath parsed.dflt parsed.join?
  match result with
  | .ok s =>
    IO.println s
    pure 0
  | .error e =>
    if parsed.lenient then
      IO.println parsed.dflt
      pure 0
    else
      IO.eprintln s!"mercator: json-get: {e}"
      pure 2

/-! ## stop-status -/

private def runStopStatus : IO UInt32 := do
  let text ←
    try
      (← IO.getStdin).readToEnd
    catch _ =>
      IO.eprintln "mercator: stop-status: cannot read stdin"
      return 2
  match Core.Json.parse text |>.bind Core.Stop.runStatusFromJson with
  | .ok status =>
    IO.println status
    pure 0
  | .error e =>
    IO.eprintln s!"mercator: stop-status: {e}"
    pure 2

/-! ## token -/

private def bytesToHex (bs : ByteArray) : String :=
  bs.foldl (init := "") fun acc b =>
    (acc.push (Core.Prim.hexDigit (b.toNat / 16))).push (Core.Prim.hexDigit (b.toNat % 16))

private def runToken : IO UInt32 := do
  let bytes ←
    try
      let handle ← IO.FS.Handle.mk "/dev/urandom" .read
      handle.read 32
    catch e =>
      IO.eprintln s!"mercator: token: cannot read /dev/urandom: {e}"
      return 2
  if bytes.size != 32 then
    IO.eprintln s!"mercator: token: short read from /dev/urandom ({bytes.size} bytes)"
    return 2
  IO.println (bytesToHex bytes)
  pure 0

/-! ## file-age-exceeds -/

private def runFileAgeExceeds (path maxAgeStr : String) : IO UInt32 := do
  let some maxAge := maxAgeStr.toNat?
    | do
      IO.eprintln "usage: mercator util file-age-exceeds <path> <seconds>"
      pure 2
  let mtime? : Option Int ←
    try
      pure (some (← System.FilePath.metadata path).modified.sec)
    catch _ =>
      pure none
  match mtime? with
  | none => pure 0  -- 消滅・stat 失敗は stale 扱い(次の mkdir が決める)
  | some mtime =>
    let now ← Io.Clock.epochSeconds
    pure (if now - mtime > Int.ofNat maxAge then 0 else 1)

/-! ## read-only-settings -/

private def runReadOnlySettings (project control handoff : String)
    (essenceNew : Bool) : IO UInt32 := do
  let resolve (label p : String) : IO (Option String) := do
    match ← Io.Fs.realPath? p with
    | some rp => pure (some rp.toString)
    | none => do
      IO.eprintln s!"mercator: read-only-settings: cannot resolve {label}: {p}"
      pure none
  let some projectR ← resolve "project root" project | pure 2
  let some controlR ← resolve "control root" control | pure 2
  let some handoffR ← resolve "handoff root" handoff | pure 2
  IO.println (Core.Settings.readOnlySession projectR controlR handoffR
    essenceNew).renderCompactAscii
  pure 0

/-! ## relpath -/

private def runRelpath (path start : String) : IO UInt32 := do
  let cwd := (← IO.currentDir).toString
  IO.println (Core.Path.relpath (Core.Path.abspath cwd start) (Core.Path.abspath cwd path))
  pure 0

/-! ## render -/

private structure RenderArgs where
  title : Option String := none
  rel : Option String := none
  abs : Option String := none
  controlAbs : Option String := none
  profile : Option String := none

private def parseRenderFlags : List String → RenderArgs →
    Option (Core.Render.Binding × Option String)
  | [], acc => do
    pure ({ title := ← acc.title, rel := ← acc.rel,
            abs := ← acc.abs, controlAbs := ← acc.controlAbs }, acc.profile)
  | "--title" :: v :: rest, acc => parseRenderFlags rest { acc with title := some v }
  | "--rel" :: v :: rest, acc => parseRenderFlags rest { acc with rel := some v }
  | "--abs" :: v :: rest, acc => parseRenderFlags rest { acc with abs := some v }
  | "--control-abs" :: v :: rest, acc =>
    parseRenderFlags rest { acc with controlAbs := some v }
  | "--profile" :: v :: rest, acc =>
    parseRenderFlags rest { acc with profile := some v }
  | _, _ => none

private def renderUsage : String :=
  "usage: mercator util render <src> <dst> {json|just|raw} --title <t> --rel <r> --abs <a> --control-abs <c> [--profile standard|auto-approve|unsandboxed]"

private def runRender (src dst mode : String) (flags : List String) : IO UInt32 := do
  let some mode := Core.Render.Mode.parse? mode
    | do IO.eprintln renderUsage; pure 2
  let some (binding, profileStr?) := parseRenderFlags flags {}
    | do IO.eprintln renderUsage; pure 2
  -- `--profile` は settings.json.tmpl(json モード)専用(§11.5、§16.1)。
  -- 他モードのテンプレは profile で派生しないため、指定自体を配線ミスとして
  -- 拒否する。
  let profile ← match profileStr? with
    | none => pure Core.Classify.Profile.standard
    | some s =>
      match Core.Classify.Profile.parse? s with
      | some p =>
        if mode != .json then
          IO.eprintln
            "mercator: render: --profile applies only to the json mode (settings.json.tmpl, §16.1)"
          return 2
        pure p
      | none => do
        IO.eprintln s!"mercator: render: unknown profile '{s}' (standard|auto-approve|unsandboxed)"
        return 2
  let some text ← Io.Fs.readFile? src
    | do IO.eprintln s!"mercator: render: cannot read {src}"; pure 2
  -- §11.5: profile 派生はレンダ(トークン置換)前のテンプレテキストへ適用
  -- する。パターン不一致 = テンプレが期待の形から動いた、なので描画自体を
  -- 拒否する(fail-closed — 壊れた/中途半端な live settings を作らない)。
  let some text := Core.Classify.deriveProfileTemplate profile text
    | do
      IO.eprintln <|
        s!"mercator: render: template does not match the profile derivation " ++
        s!"patterns (profile '{profile.tag}', §11.5); refusing to render"
      pure 2
  match Core.Render.renderBind mode binding text with
  | .error e =>
    IO.eprintln s!"mercator: render: {e}"
    pure 2
  | .ok out =>
    try
      Io.Fs.writeFileAtomicTagged dst "render" out
      pure 0
    catch e =>
      IO.eprintln s!"mercator: render: cannot write {dst}: {e}"
      pure 2

/-! ## seed -/

private def parseSeedReplacements : List String → List (String × String) →
    Option (List (String × String))
  | [], acc => some acc.reverse
  | "--replace" :: v :: rest, acc =>
    match v.splitOn "=" with
    | token :: valueParts =>
      if token.isEmpty || valueParts.isEmpty then none
      else parseSeedReplacements rest ((token, String.intercalate "=" valueParts) :: acc)
    | [] => none
  | _, _ => none

private def runSeed (src dst : String) (flags : List String) : IO UInt32 := do
  let some replacements := parseSeedReplacements flags []
    | do
      IO.eprintln "usage: mercator util seed <src> <dst> [--replace TOKEN=VALUE]..."
      pure 2
  let some text ← Io.Fs.readFile? src
    | do IO.eprintln s!"mercator: seed: cannot read {src}"; pure 2
  try
    Io.Fs.writeFileAtomicTagged dst "seed" (Core.Render.substitute text replacements)
    pure 0
  catch e =>
    IO.eprintln s!"mercator: seed: cannot write {dst}: {e}"
    pure 2

/-! ## project-index -/

/-- 登録 rel を照合用の絶対パスへ解決する。実体解決(realPath)を優先し、
不存在なら字句解決(`abspath`)へフォールバック — 旧 `resolve(strict=False)`
との差は docstring のとおり厳格側(不一致 = other)に倒れる。 -/
private def resolveRegisteredRoot (controlResolved rel : String) : IO String := do
  let candidate := Core.Path.abspath controlResolved rel
  match ← Io.Fs.realPath? candidate with
  | some r => pure r.toString
  | none => pure candidate

private def runProjectIndex (action index target control : String) : IO UInt32 := do
  -- target / control は呼び出し元(resolve_project / assert_control_root)が
  -- 実在を保証している。解決不能はここでは想定外のハード失敗。
  let some targetR ← Io.Fs.realPath? target
    | do IO.eprintln s!"mercator: project-index: cannot resolve target: {target}"; pure 2
  let some controlR ← Io.Fs.realPath? control
    | do IO.eprintln s!"mercator: project-index: cannot resolve control root: {control}"; pure 2
  -- 読めない・パース不能な index は旧実装同様 no-op(exit 0、fail-open)。
  let some idx ← Io.Fs.readJson? index
    | pure 0
  match Core.ProjectIndex.shape idx with
  | .absent => pure 0
  | .malformed =>
    IO.eprintln "mercator: project-index: project.project_root has a non-string shape; repair project_index.json (§8.1)"
    pure 2
  | .registered title rel? =>
    let pointsAtTarget ← match rel? with
      | none => pure false
      | some rel => do
        let root ← resolveRegisteredRoot controlR.toString rel
        pure (root == targetR.toString)
    if pointsAtTarget then
      pure 0
    else
      match action with
      | "other" =>
        match rel? with
        | none => pure 0  -- 照合するパスなし = other なし(truthiness の写し)
        | some rel =>
          IO.println s!"{title}:{← resolveRegisteredRoot controlR.toString rel}"
          pure 0
      | _ => do  -- prune
        Io.Fs.writeFileAtomic index ((Core.ProjectIndex.pruned idx).renderPretty ++ "\n")
        IO.eprintln s!"[mercator] pruned stale project_index entries: {title}"
        pure 0

/-! ## json-check -/

private def runJsonCheck (path : String) : IO UInt32 := do
  let some text ← Io.Fs.readFile? path
    | do IO.eprintln s!"mercator: json-check: cannot read {path}"; pure 1
  match Core.Json.parse text with
  | .ok _ => pure 0
  | .error e =>
    IO.eprintln s!"mercator: json-check: {path}: {e}"
    pure 1

/-! ## dangling-run -/

private def runDanglingRun (path : String) : IO UInt32 := do
  let scanned := match ← Io.Fs.readFile? path with
    | none => Core.Runs.Scan.unreadable  -- OSError → unreadable(旧実装と同一)
    | some text => Core.Runs.scan text
  match scanned with
  | .unreadable => IO.println "__UNREADABLE__"
  | .dangling rid => IO.println rid
  | .clean => IO.println ""
  pure 0

/-! ## settings-doctor -/

private def runSettingsDoctor (path project control profileStr : String) :
    IO UInt32 := do
  -- 第 4 引数は `util essence-profile` の出力(閉集合の正値)を渡す契約。
  -- 閉集合外は配線ミスなので usage 側の exit 2 で大きく落とす(fail-closed)。
  let some profile := Core.Classify.Profile.parse? profileStr
    | do
      IO.eprintln s!"mercator: settings-doctor: unknown profile '{profileStr}' (standard|auto-approve|unsandboxed)"
      pure 2
  let some text ← Io.Fs.readFile? path
    | do IO.println s!".claude/settings.json is not valid JSON: cannot read {path}"; pure 0
  match Core.Json.parse text with
  | .error e =>
    IO.println s!".claude/settings.json is not valid JSON: {e}"
    pure 0
  | .ok settings =>
    let cwd := (← IO.currentDir).toString
    for issue in Core.SettingsDoctor.check settings project control cwd profile do
      IO.println issue
    pure 0

/-! ## essence-profile -/

private def runEssenceProfile (path : String) : IO UInt32 := do
  match ← Io.Fs.readFile? path with
  | none =>
    -- 不在・読取不能・不正 UTF-8 は standard(§11.5 — 最厳格への縮退)。
    -- 欠損 Essence 自体の停止は bootstrap 後の validate / loop が担う。
    IO.println Core.Classify.Profile.standard.tag
    pure 0
  | some text =>
    -- placeholder(§13.1-8 と同一判定: ガイドブロック残存・空白のみ・未消化
    -- FILL マーカー)は standard — テンプレ由来のテキストから profile を
    -- 発効させない。
    if Core.Text.containsSub text State.Model.placeholderMarker
        || (Core.Text.pyStrip text).isEmpty
        || Core.Text.containsSub text State.Model.fillMarker then
      IO.println Core.Classify.Profile.standard.tag
      pure 0
    else
      match Core.Classify.scanProfile text with
      | .invalid raw =>
        IO.eprintln <|
          s!"mercator: essence-profile: invalid profile value '{raw}' — " ++
          "the closed set is standard | auto-approve | unsandboxed (§11.5)"
        pure 2
      | .conflict =>
        IO.eprintln <|
          "mercator: essence-profile: conflicting profile declarations — " ++
          "declare exactly one (§11.5)"
        pure 2
      | scan =>
        IO.println scan.effective.tag
        pure 0

/-! ## static-config -/

private def runStaticConfig (name : String) : IO UInt32 := do
  match Core.StaticConfig.rendered? name with
  | some rendered =>
    -- rendered は末尾 LF 込みの正確な配布バイト列(println は使わない)
    IO.print rendered
    pure 0
  | none =>
    IO.eprintln "usage: mercator util static-config {workspace|project-index-seed}"
    pure 2

/-! ## ディスパッチ -/

def run : List String → IO UInt32
  | "json-get" :: rest => runJsonGet rest
  | ["stop-status"] => runStopStatus
  | ["token"] => runToken
  | ["file-age-exceeds", path, maxAge] => runFileAgeExceeds path maxAge
  | ["read-only-settings", project, control, handoff] =>
    runReadOnlySettings project control handoff false
  | ["read-only-settings", project, control, handoff, "essence-new"] =>
    runReadOnlySettings project control handoff true
  | ["relpath", path, start] => runRelpath path start
  | "render" :: src :: dst :: mode :: flags => runRender src dst mode flags
  | "seed" :: src :: dst :: flags => runSeed src dst flags
  | ["project-index", action, index, target, control] =>
    if action == "other" || action == "prune" then
      runProjectIndex action index target control
    else do
      IO.eprintln usage
      pure 2
  | ["json-check", path] => runJsonCheck path
  | ["dangling-run", path] => runDanglingRun path
  | ["settings-doctor", path, project, control] =>
    runSettingsDoctor path project control "standard"
  | ["settings-doctor", path, project, control, profile] =>
    runSettingsDoctor path project control profile
  | ["essence-profile", path] => runEssenceProfile path
  | ["static-config", name] => runStaticConfig name
  | _ => do
    IO.eprintln usage
    pure 2

end Mercator.Cli.Util
