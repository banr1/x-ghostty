import Mercator.Core.Classify
import Mercator.Core.Frag

/-!
`Mercator.Core.Classify.Bash` — guard の分類カタログ・第 2 部: Bash コマンド
生テキストへの分類群。旧 Python guard との等価性は差分ファザーで検証済み
(§31.2-15)。

凍結した意味論(旧 pre_tool_guard.py 由来。× `re.search(pat, command)`):

1. `DENIED_BASH`(git add/commit)/ `HUMAN_ONLY_BASH`(resume・loop・once・init・
   doctor・trust・triage・supervise・essence 系 + `_JUST_PREFIX` フラグ跨ぎ)/
   `LOOP_ONLY_BASH` / `ASK_BASH` / `DANGEROUS_BASH` / `SECRET_BASH` —
   `isDeniedBash` / `isHumanOnlyBash` / `isLoopOnlyBash` / `isAskBash` /
   `isDangerousBash` / `isSecretBash` が対応(リスト × any を関数 1 本に畳む)。
2. `WRITE_REDIRECT_OR_MUTATOR` 単体(`hasWriteRedirectOrMutator`)と、その複合
   `DEPENDENCY_INPUT_BASH_MUTATION` / `CONTROL_SURFACE_BASH_MUTATION` /
   `ZONE_BASH_MUTATION`(`WRITE... [^;&|]* パス群` = 「同一パイプラインセグメント内で
   mutator の後にパスが現れる」)、および `bash_high_risk_targets` の動的複合
   `WRITE... [^;&|]* re.escape(token)`(`mutatesLiteralTarget`)。
3. main() ローカルの `protected_write_target`(`isProtectedWriteTarget`。mutator との
   連言は呼び出し側 = `Guard/Decide` の決定木)。
4. `re.findall(r"[-\w@.~/]+", command)` の `sorted(set(...))`(`bashPathishTokens`。
   `bash_high_risk_targets` のトークン抽出部)。

実装原理: 正規表現エンジンは書かず、各パターンを「断片マッチャ `Frag`(接尾辞を
消費して残りを返す)+ 全開始位置の走査」に直訳する。本カタログの全パターンは
以下の理由でバックトラック消去が受理同値になる(実装中の各所に個別注記):
- `\s+`・`\S*`・文字クラス反復の直後は常に排反な文字集合が続く(貪欲一致が唯一)。
- `_JUST_PREFIX` の star 反復はフラグ(`-` 開始)、後続 tail は英字開始で排反。
- 任意分割が要る箇所(`requirements[\w.-]*\.txt`、zone の `scripts/[^…]*(agent|…)`、
  複合の `[^;&|]*`)は分割点の存在判定として明示走査する。

CPython `re` 意味論の写し(実測で固定):
- `(curl|wget)[^|]*\|` の `[^|]*` は `|` を跨げないため、各 curl/wget 出現につき
  「直後の最初の `|`」だけが検査される(`curl a | x | sh` は不一致)。一方 `[^|]` は
  `;` や改行を含むため セグメントは跨ぐ(`curl a > f; cat f | sh` は一致)。
- `--?[\w-]+` は言語として `-[\w-]+` と同値(2 本目の `-` は文字クラスが吸収)。
  ゆえに `just -- resume` は human-only に一致する(実測)。
- `trust(?:-check)?\b` は `just trust-checkx` にも一致する(`-check` を放棄して
  `trust` + `\b`(`-` は非語)で成立。alternation を両綴りの試行として写す)。

裁定済み方言差(§31 参照。いずれも一致側が増える = deny/ask 拡大方向、R-6 自動採用):
- `\b`(語境界)の語クラスは ASCII `[A-Za-z0-9_]` のみとし、非 ASCII は常に
  非語構成文字 = 境界成立とする(`isAsciiWord`)。Python の `\w` は Unicode 準拠
  なので、非 ASCII の字母・数字がキーワードへ直接隣接する綴り(`égit add`・
  `git addé`)では Lean 側だけがマッチする。非 ASCII の記号・句読点・空白では
  両者一致。全使用箇所が deny/ask 側の分類のため拡大方向。
- `[\w-]`(just フラグ名)・`[\w.-]`(requirements 可変部)・`[-\w@.~/]`(pathish
  トークン)の `\w` は第 1 部の `isWordChar` 方言(非 ASCII は空白以外すべて語構成
  文字)。`just --flag§ resume` は Python 不一致・Lean 一致(deny 拡大)。
-/

namespace Mercator.Core.Classify

open Mercator.Core.Prim (dropLit?)
open Mercator.Core.Text (isPySpace runsOf dedup containsSub)
open Mercator.Core.Frag

/-! ## `_JUST_PREFIX` — `\bjust\s+(?:--?[\w-]+(?:=\S*)?\s+)*` -/

/-- `[\w-]`(フラグ名の文字クラス。`isWordChar` 方言 — 頭注)。 -/
private def isFlagChar (c : Char) : Bool := isWordChar c || c == '-'

/-- フラグ 1 反復 `-[\w-]+(?:=\S*)?\s+`(`--?[\w-]+` の同値形 — 頭注)。
`=\S*` の貪欲消費は直後の `\s+` と排反で唯一の分割。 -/
private def flagOnce : Frag
  | '-' :: rest =>
    let (name, rest) := rest.span isFlagChar
    if name.isEmpty then none
    else
      ws1 (match rest with
        | '=' :: r => r.dropWhile (fun c => !isPySpace c)
        | _ => rest)
  | _ => none

/-- star 反復 + tail。tail の全代替は英字開始・フラグは `-` 開始で排反のため、
各位置で tail を先に試す決定的評価が CPython のバックトラックと受理一致する。
フラグ 1 反復は 3 文字以上消費するので fuel = 入力長で十分。 -/
private def flagsStar (tail : Frag) : Nat → Frag
  | 0 => tail
  | fuel + 1 => fun cs => tail cs <|> (flagOnce cs).bind (flagsStar tail fuel)

/-- `re.search(_JUST_PREFIX ++ tail, s)`。 -/
private def searchJustPrefix (tail : Frag) (s : String) : Bool :=
  searchAtBoundary
    (fun cs => ((lit "just" >=> ws1) cs).bind fun rest =>
      flagsStar tail (rest.length + 1) rest)
    s

/-! ## DENIED_BASH(I-015: agent は stage / commit しない) -/

/-- `DENIED_BASH` = `\bgit\s+add\b` / `\bgit\s+commit\b`。フラグ挟み
(`git -C x add`)は意図的に不一致(Python 同様、permissions 側が受ける)。 -/
def isDeniedBash (command : String) : Bool :=
  searchAtBoundary (lit "git" >=> ws1 >=> lit "add" >=> wordEnd) command
    || searchAtBoundary (lit "git" >=> ws1 >=> lit "commit" >=> wordEnd) command

/-! ## HUMAN_ONLY_BASH(I-011、META.md §13.3・§18.2) -/

/-- `(?:loop|once|init|doctor|trust(?:-check)?|triage|supervise|new-essence|update-essence)`
の展開(`trust(?:-check)?` は両綴りの代替として写す — 頭注)。 -/
private def humanOnlyJustRecipes : List String :=
  ["loop", "once", "init", "doctor", "trust-check", "trust", "triage",
   "supervise", "new-essence", "update-essence"]

/-- `HUMAN_ONLY_BASH` × `re.search`。`state\.py\s+resume` は綴りが隣接する形のみ
(フラグ先行綴りの遮断は `statePySubcommands` の責務 — 第 1 部)。 -/
def isHumanOnlyBash (command : String) : Bool :=
  search (lit "state.py" >=> ws1 >=> lit "resume" >=> wordEnd) command
    -- Lean マルチコール綴り(agent 向け配線面。trust ensure
    -- と同じく、バイナリ直接呼び出しがゲートを迂回できない形で deny)
    || searchAtBoundary
        (lit "mercator" >=> ws1 >=> lit "state" >=> ws1 >=> lit "resume" >=> wordEnd) command
    || containsSub command "mercator-resume.sh"
    || searchJustPrefix (lit "resume" >=> wordEnd) command
    || searchJustPrefix (lit "state" >=> ws1 >=> lit "resume" >=> wordEnd) command
    || ["mercator-loop.sh", "mercator-once.sh", "mercator-init.sh",
        "mercator-doctor.sh", "mercator-triage.sh", "mercator-essence.sh",
        "mercator-supervise.sh"].any (containsSub command)
    || searchJustPrefix (alts (humanOnlyJustRecipes.map fun w => lit w >=> wordEnd)) command
    || containsSub command "claude-trust.sh"
    || search (lit "claude_trust.py" >=> ws1 >=> lit "ensure" >=> wordEnd) command
    || searchAtBoundary
        (lit "mercator" >=> ws1 >=> lit "trust" >=> ws1 >=> lit "ensure" >=> wordEnd) command

/-! ## LOOP_ONLY_BASH(META.md §19.1) -/

/-- `LOOP_ONLY_STATE_SUBCOMMANDS`(`state_py_subcommands` との積にも使う集合)。 -/
def loopOnlyStateSubcommands : List String :=
  ["start-run", "end-run", "record-progress", "reset-context", "raise-loop-gates"]

private def loopOnlySubTail : Frag :=
  alts (loopOnlyStateSubcommands.map fun w => lit w >=> wordEnd)

/-- `LOOP_ONLY_BASH` × `re.search`。 -/
def isLoopOnlyBash (command : String) : Bool :=
  search (lit "state.py" >=> ws1 >=> loopOnlySubTail) command
    || searchAtBoundary
        (lit "mercator" >=> ws1 >=> lit "state" >=> ws1 >=> loopOnlySubTail) command
    || searchJustPrefix (lit "state" >=> ws1 >=> loopOnlySubTail) command

/-! ## ASK_BASH(bootstrap / build は明示承認) -/

/-- `ASK_BASH` × `re.search`。 -/
def isAskBash (command : String) : Bool :=
  containsSub command "mercator-bootstrap.sh"
    || searchJustPrefix (lit "bootstrap" >=> wordEnd) command
    || searchJustPrefix (lit "build" >=> wordEnd) command

/-! ## DANGEROUS_BASH(安全ルールの絶対 deny) -/

/-- `[^|]*\|\s*(ba)?sh\b` の断片: 直後の最初の `|` まで進み(`[^|]` は `|` を
跨げない — 頭注)、`\s*` を剥いで `bash\b` / `sh\b` を試す。 -/
private def pipeShTail : Frag := fun cs =>
  match cs.dropWhile (· != '|') with
  | '|' :: rest =>
    alts [lit "bash" >=> wordEnd, lit "sh" >=> wordEnd] (rest.dropWhile isPySpace)
  | _ => none

/-- `DANGEROUS_BASH` × `re.search` の最初に一致したパターン(Python の
リスト順・正規表現リテラルそのまま)。guard の deny 文言
`f"Forbidden Bash pattern (safety rule): {pat}"` がパターン文字列を含む
ため、判定と文言の単一定義としてここに置く(`curl`/`wget` に `\b` はない —
`mycurl x | sh` も一致する。Python の実挙動)。 -/
def dangerousBashReason? (command : String) : Option String :=
  if searchAtBoundary (lit "rm" >=> ws1 >=> lit "-rf" >=> wordEnd) command then
    some "\\brm\\s+-rf\\b"
  else if searchAtBoundary (lit "sudo" >=> wordEnd) command then
    some "\\bsudo\\b"
  else if searchAtBoundary (lit "git" >=> ws1 >=> lit "push" >=> wordEnd) command then
    some "\\bgit\\s+push\\b"
  else if searchAtBoundary
      (lit "git" >=> ws1 >=> lit "reset" >=> ws1 >=> lit "--hard" >=> wordEnd) command then
    some "\\bgit\\s+reset\\s+--hard\\b"
  else if searchAtBoundary
      (lit "git" >=> ws1 >=> lit "clean" >=> ws1 >=> lit "-fd" >=> wordEnd) command then
    some "\\bgit\\s+clean\\s+-fd\\b"
  else if search (alts [lit "curl", lit "wget"] >=> pipeShTail) command then
    some "(curl|wget)[^|]*\\|\\s*(ba)?sh\\b"
  else
    none

/-- `DANGEROUS_BASH` のいずれかに一致(`dangerousBashReason?` の Bool 面)。 -/
def isDangerousBash (command : String) : Bool :=
  (dangerousBashReason? command).isSome

/-! ## SECRET_BASH(META.md §11.4) -/

/-- `[\s\"'=/]`(相対パス参照が空白・クォート・`=` の後に座る前提の接頭辞クラス)。 -/
private def secretCls (c : Char) : Bool :=
  isPySpace c || c == '"' || c == '\'' || c == '=' || c == '/'

/-- `SECRET_BASH` × `re.search`。 -/
def isSecretBash (command : String) : Bool :=
  searchPrefixed secretCls (lit ".env" >=> wordEnd) command
    || searchPrefixed secretCls (lit "secrets/") command
    || searchPrefixed secretCls (lit "config/credentials.json" >=> wordEnd) command

/-! ## WRITE_REDIRECT_OR_MUTATOR と複合 mutation 群 -/

/-- `>>?`。1 個消費か 2 個消費かは後続の `[^;&|]*` が吸収するため受理に無関係。 -/
private def gt1or2 : Frag
  | '>' :: '>' :: rest => some rest
  | '>' :: rest => some rest
  | _ => none

/-- `\b(?:sed\s+-i|tee|mv|cp|rm)\b` の語部(先頭 `\b` は呼び出し側)。 -/
private def wordMutator : Frag :=
  alts [lit "sed" >=> ws1 >=> lit "-i", lit "tee", lit "mv", lit "cp", lit "rm"]
    >=> wordEnd

/-- `WRITE_REDIRECT_OR_MUTATOR` の 1 開始位置分
(`[0-9]?>>?` / `&>>?` / 語 mutator)。 -/
private def mutatorAt (prev : Option Char) : Frag := fun cs =>
  (match cs with
    | '&' :: rest => gt1or2 rest
    | c :: rest => if c.isDigit then gt1or2 rest else gt1or2 cs
    | [] => none)
  <|> (if boundaryBefore prev then wordMutator cs else none)

/-- `re.search(WRITE_REDIRECT_OR_MUTATOR, command)` 等価。 -/
def hasWriteRedirectOrMutator (command : String) : Bool :=
  (positions command).any fun (prev, sfx) => (mutatorAt prev sfx).isSome

/-- mutator 直後から `[^;&|]*` で届く各位置(セパレータ手前まで)で tail を試す。
tail は打ち切られていない実残余に適用するため、`\b` の先読みも Python と一致する。 -/
private def mutatedFrom (tail : Frag) : List Char → Bool
  | [] => (tail []).isSome
  | c :: rest =>
    (tail (c :: rest)).isSome
      || ((c != ';' && c != '&' && c != '|') && mutatedFrom tail rest)

/-- `re.search(WRITE_REDIRECT_OR_MUTATOR ++ "[^;&|]*" ++ tail, command)` 等価。 -/
private def searchMutated (tail : Frag) (command : String) : Bool :=
  (positions command).any fun (prev, sfx) =>
    match mutatorAt prev sfx with
    | some rest => mutatedFrom tail rest
    | none => false

/-- `bash_high_risk_targets` の動的複合
`WRITE_REDIRECT_OR_MUTATOR + [^;&|]* + re.escape(target)` 等価。 -/
def mutatesLiteralTarget (target command : String) : Bool :=
  searchMutated (lit target) command

/-! ### _DEPENDENCY_INPUT_PATH(ASK_PATTERNS の Bash 側補完、META.md §11.2) -/

/-- `requirements[\w.-]*\.txt\b` の可変部走査: 各位置で `.txt\b` を試し、失敗なら
`[\w.-]` を 1 文字進める(任意分割の存在判定)。 -/
private def reqTxtScan : List Char → Option (List Char)
  | [] => none
  | c :: rest =>
    (lit ".txt" >=> wordEnd) (c :: rest)
      <|> (if isReqChar c then reqTxtScan rest else none)

/-- 依存解決入力の固定名(`bun\.lockb?`・`\.yarnrc(?:\.yml)?` は選択肢を展開。
Edit 経路 `isAskPath` と対で保守する — SyncPairs D-006)。 -/
private def depLiterals : List String :=
  ["package.json", "package-lock.json", "npm-shrinkwrap.json", "pnpm-lock.yaml",
   "yarn.lock", "bun.lockb", "bun.lock", "bunfig.toml",
   ".npmrc", ".yarnrc.yml", ".yarnrc",
   ".pnpmfile.cjs", "pyproject.toml", "uv.lock", "poetry.lock", "Pipfile.lock",
   "Pipfile", "pip.conf",
   "Cargo.toml", "Cargo.lock", ".cargo/config.toml", ".cargo/config",
   "go.mod", "go.sum",
   "lakefile.lean", "lakefile.toml", "lake-manifest.json", "lean-toolchain"]

private def dependencyInputTail : Frag :=
  alts ((depLiterals.map fun w => lit w >=> wordEnd)
    ++ [lit "requirements" >=> fun cs => reqTxtScan cs])

/-- `re.search(DEPENDENCY_INPUT_BASH_MUTATION, command)` 等価(接頭辞アンカーは
なく、`> mypackage.json` も一致する — Python の実挙動)。 -/
def isDependencyInputBashMutation (command : String) : Bool :=
  searchMutated dependencyInputTail command

/-! ### _CONTROL_SURFACE_PATH(CONTROL_PLANE_HIGH_RISK の Bash 側補完、META.md §11.3) -/

/-- `[\s\"'=]`(`/` を含まない — zone との差)。 -/
private def ctlCls (c : Char) : Bool :=
  isPySpace c || c == '"' || c == '\'' || c == '='

/-- `mercator-[A-Za-z-]+\.sh`。クラスに `.` が無いため貪欲一致が唯一の分割。 -/
private def mercatorShFrag : Frag := fun cs =>
  (dropLit? cs "mercator-".toList).bind fun rest =>
    let (run, rest) := rest.span fun c =>
      ('A' ≤ c && c ≤ 'Z') || ('a' ≤ c && c ≤ 'z') || c == '-'
    if run.isEmpty then none else lit ".sh" rest

/-- `claude[-_]trust\.(py|sh)`。 -/
private def claudeTrustFrag : Frag :=
  lit "claude" >=> cls (fun c => c == '-' || c == '_') >=> lit "trust."
    >=> alts [lit "py", lit "sh"]

/-- `(\./)?`。後続(`scripts/` / `README.md`)は `.` で始まらないため決定的。 -/
private def optDotSlash : Frag := fun cs =>
  match dropLit? cs "./".toList with
  | some rest => some rest
  | none => some cs

/-- `[^\s\"';&|]`。 -/
private def isBashWordChar (c : Char) : Bool :=
  !isPySpace c && c != '"' && c != '\'' && c != ';' && c != '&' && c != '|'

/-- `[^\s\"';&|]+`。 -/
private def some1BashWord : Frag := fun cs =>
  let (run, rest) := cs.span isBashWordChar
  if run.isEmpty then none else some rest

/-- `_CONTROL_SURFACE_PATH` の代替(複合内では `^` 分岐は発火し得ない —
mutator が 1 文字以上消費するため。tail は接頭辞クラス消費形のみで写す)。 -/
private def controlSurfaceTail : Frag :=
  alts
    [ lit "scripts/"
        >=> alts [lit "state.py", lit "_lib.sh", mercatorShFrag, claudeTrustFrag],
      cls ctlCls >=> optDotSlash >=> lit "scripts/" >=> some1BashWord,
      lit "templates/control/", lit "templates/project/", lit "templates/workspace/",
      lit "recipes/",
      lit ".agent/prompts/",
      lit "META.md",
      cls ctlCls >=> optDotSlash >=> lit "README.md" >=> wordEnd,
      lit "justfile" >=> wordEnd ]

/-- `re.search(CONTROL_SURFACE_BASH_MUTATION, command)` 等価。 -/
def isControlSurfaceBashMutation (command : String) : Bool :=
  searchMutated controlSurfaceTail command

/-! ### _ZONE_BASH_PATH(HIGH_RISK_PATTERNS の Bash 側補完、META.md §12) -/

/-- `scripts/[^\s\"';&|]*(agent|claude|loop|autonomous)` の可変部走査
(`[^/]*` ではないため `scripts/sub/agent` も一致する — パス分類版との差)。 -/
private def zoneScriptsScan : List Char → Option (List Char)
  | [] => none
  | c :: rest =>
    alts [lit "agent", lit "claude", lit "loop", lit "autonomous"] (c :: rest)
      <|> (if isBashWordChar c then zoneScriptsScan rest else none)

private def zoneDotCls (c : Char) : Bool := secretCls c || c == '.'

/-- `_ZONE_BASH_PATH` の代替(`^` 分岐は複合内で発火し得ない)。接頭辞クラスは
`[\s\"'=/]`(= `secretCls`)、ドットファイルのみ `.` を加えた `[\s\"'=/.]`。 -/
private def zoneTail : Frag :=
  alts
    [ cls secretCls >=> lit "CLAUDE.md" >=> wordEnd,
      cls zoneDotCls >=> lit ".claude/",
      cls secretCls >=> lit ".mcp.json" >=> wordEnd,
      cls zoneDotCls >=> lit ".cursor/",
      cls secretCls >=> lit "AGENTS.md" >=> wordEnd,
      lit ".github/workflows/",
      cls secretCls >=> lit "agent-runtime/",
      cls secretCls >=> lit "agents/",
      cls secretCls >=> lit "prompts/",
      cls secretCls >=> lit "skills/",
      cls secretCls >=> lit "hooks/",
      lit "scripts/" >=> fun cs => zoneScriptsScan cs,
      cls secretCls >=> lit "settings.json" >=> wordEnd ]

/-- `re.search(ZONE_BASH_MUTATION, command)` 等価。 -/
def isZoneBashMutation (command : String) : Bool :=
  searchMutated zoneTail command

/-! ## protected_write_target(main() ローカル、canonical/secret 直接書換の deny) -/

/-- `ESSENCE\.md|essences/|\.mercator/state/|\.env($|\.|\s)|secrets/|config/credentials\.json|essence_attestations\.jsonl|\.agent/state/`
× `re.search`(接頭辞クラスなしの生部分一致 — `x.env` も一致する。mutator との
連言は呼び出し側)。`essences/` は ESSENCE.md と同格の human-only 資産面
(§2.1.5)。`$` の「末尾 1 個の `\n` 直前」特例は `\s` の `\n` が吸収する
ため、真の末尾のみで写す。 -/
def isProtectedWriteTarget (command : String) : Bool :=
  containsSub command "ESSENCE.md"
    || containsSub command "essences/"
    || containsSub command ".mercator/state/"
    || search
        (lit ".env"
          >=> alts [fun cs => if cs.isEmpty then some [] else none,
                    cls fun c => c == '.' || isPySpace c])
        command
    || containsSub command "secrets/"
    || containsSub command "config/credentials.json"
    || containsSub command "essence_attestations.jsonl"
    || containsSub command ".agent/state/"

/-! ## bash_high_risk_targets のトークン抽出部 -/

/-- `[-\w@.~/]`(`\w` は `isWordChar` 方言 — 頭注)。 -/
private def isPathishChar (c : Char) : Bool :=
  isWordChar c || c == '@' || c == '.' || c == '~' || c == '/' || c == '-'

/-- `sorted(set(re.findall(r"[-\w@.~/]+", command)))` 等価(コードポイント昇順)。 -/
def bashPathishTokens (command : String) : List String :=
  (dedup ((runsOf isPathishChar command).map String.ofList)).mergeSort
    fun a b => decide (a < b) || a == b

/-! ## コンパイル時検査(期待値は pre_tool_guard.py の実パターンの CPython 3.14
実測。方言差はその旨を注記) -/

-- isSecretBash
#guard isSecretBash ".env" == true
#guard isSecretBash "cat .env" == true
#guard isSecretBash "cat .envx" == false
#guard isSecretBash "cat .env.local" == true
#guard isSecretBash "x.env" == false
#guard isSecretBash "a/.env" == true
#guard isSecretBash "FOO=.env" == true
#guard isSecretBash "cat 'secrets/k'" == true
#guard isSecretBash "mysecrets/x" == false
#guard isSecretBash "cat config/credentials.json" == true
#guard isSecretBash "config/credentials.json" == true
#guard isSecretBash "xconfig/credentials.json" == false
#guard isSecretBash "cat .env\n" == true
#guard isSecretBash "cat .env2" == false
#guard isSecretBash "cat .env-x" == true
#guard isSecretBash "echo \".env\"" == true
#guard isSecretBash "secrets/" == true
#guard isSecretBash "cat\tsecrets/k" == true

-- isDeniedBash
#guard isDeniedBash "git add ." == true
#guard isDeniedBash "git commit -m x" == true
#guard isDeniedBash "git  add" == true
#guard isDeniedBash "gitadd" == false
#guard isDeniedBash "mygit add" == false
#guard isDeniedBash "git\tadd" == true
#guard isDeniedBash "git addx" == false
#guard isDeniedBash "git add;" == true
#guard isDeniedBash "git push" == false
#guard isDeniedBash "git status" == false
#guard isDeniedBash "x && git commit" == true
#guard isDeniedBash "git\ncommit" == true
#guard isDeniedBash "git -C x add" == false
-- 方言差(頭注): Python は false(é は \w)、Lean は境界 ASCII 方言で true(deny 拡大)
#guard isDeniedBash "égit add" == true
#guard isDeniedBash "git addé" == true
-- 非 ASCII でも記号・空白は両実装一致
#guard isDeniedBash "git add§" == true

-- isHumanOnlyBash
#guard isHumanOnlyBash "python3 scripts/state.py resume" == true
#guard isHumanOnlyBash "state.py --project X resume" == false
#guard isHumanOnlyBash "just resume" == true
#guard isHumanOnlyBash "just --unstable resume" == true
#guard isHumanOnlyBash "just -f X resume" == false
#guard isHumanOnlyBash "just -- resume" == true
#guard isHumanOnlyBash "just - resume" == false
#guard isHumanOnlyBash "just state resume" == true
#guard isHumanOnlyBash "just --flag=v state resume" == true
#guard isHumanOnlyBash "justx resume" == false
#guard isHumanOnlyBash "xjust resume" == false
#guard isHumanOnlyBash "just  resume" == true
#guard isHumanOnlyBash "just resumex" == false
#guard isHumanOnlyBash "just triage" == true
#guard isHumanOnlyBash "just trust" == true
#guard isHumanOnlyBash "just trust-check" == true
#guard isHumanOnlyBash "just trust-checkx" == true
#guard isHumanOnlyBash "just trustx" == false
#guard isHumanOnlyBash "just new-essence" == true
#guard isHumanOnlyBash "just update-essence" == true
#guard isHumanOnlyBash "mercator-loop.sh" == true
#guard isHumanOnlyBash "bash mercator-loop.sh" == true
#guard isHumanOnlyBash "amercator-loop.sh" == true
#guard isHumanOnlyBash "mercator-loopx.sh" == false
#guard isHumanOnlyBash "claude_trust.py ensure" == true
#guard isHumanOnlyBash "claude_trust.py status" == false
#guard isHumanOnlyBash "mercator trust ensure" == true
#guard isHumanOnlyBash "bin/mercator trust ensure" == true
#guard isHumanOnlyBash "xmercator trust ensure" == false
#guard isHumanOnlyBash "mercator trust status" == false
#guard isHumanOnlyBash "just doctor" == true
#guard isHumanOnlyBash "mercator-doctor.sh" == true
#guard isHumanOnlyBash "just supervise" == true
#guard isHumanOnlyBash "just loop" == true
#guard isHumanOnlyBash "just once" == true
#guard isHumanOnlyBash "just init" == true
#guard isHumanOnlyBash "claude-trust.sh" == true
#guard isHumanOnlyBash "state.py resume" == true
#guard isHumanOnlyBash "state.py resumex" == false
#guard isHumanOnlyBash "mercator state resume" == true
#guard isHumanOnlyBash "bin/mercator state resume" == true
#guard isHumanOnlyBash "./bin/mercator state resume --project ../p" == true
#guard isHumanOnlyBash "xmercator state resume" == false
#guard isHumanOnlyBash "mercator state resumex" == false
#guard isHumanOnlyBash "mercator state validate" == false
#guard isHumanOnlyBash "just --flag= resume" == true
#guard isHumanOnlyBash "just ---x resume" == true
#guard isHumanOnlyBash "state.py\tresume" == true
-- 方言差(頭注): Python は false(§ は \w 外でフラグ反復が壊れる)、Lean は true(deny 拡大)
#guard isHumanOnlyBash "just --flag§ resume" == true

-- isLoopOnlyBash
#guard isLoopOnlyBash "state.py start-run" == true
#guard isLoopOnlyBash "state.py start-runx" == false
#guard isLoopOnlyBash "just state end-run" == true
#guard isLoopOnlyBash "just --unstable state record-progress" == true
#guard isLoopOnlyBash "state.py resume" == false
#guard isLoopOnlyBash "scripts/state.py raise-loop-gates --project x" == true
#guard isLoopOnlyBash "state.py  reset-context" == true
#guard isLoopOnlyBash "just state start-run" == true
#guard isLoopOnlyBash "juststate start-run" == false
#guard isLoopOnlyBash "state.py end-run" == true
#guard isLoopOnlyBash "state.py --project x end-run" == false
#guard isLoopOnlyBash "just state raise-loop-gates" == true
#guard isLoopOnlyBash "bin/mercator state start-run" == true
#guard isLoopOnlyBash "mercator state record-progress --project ../p" == true
#guard isLoopOnlyBash "mercator state resume" == false
#guard isLoopOnlyBash "xmercator state end-run" == false
#guard isLoopOnlyBash "mercator state --project x end-run" == false

-- isDangerousBash
#guard isDangerousBash "rm -rf /" == true
#guard isDangerousBash "rm -rf" == true
#guard isDangerousBash "rm -rfx" == false
#guard isDangerousBash "rm  -rf." == true
#guard isDangerousBash "rm -r f" == false
#guard isDangerousBash "sudo apt" == true
#guard isDangerousBash "sudox" == false
#guard isDangerousBash "xsudo" == false
#guard isDangerousBash "git push" == true
#guard isDangerousBash "git push origin" == true
#guard isDangerousBash "git  reset   --hard" == true
#guard isDangerousBash "git reset --hardx" == false
#guard isDangerousBash "git reset --soft" == false
#guard isDangerousBash "git clean -fd" == true
#guard isDangerousBash "git clean -fdx" == false
#guard isDangerousBash "git clean -f" == false
#guard isDangerousBash "curl http://x | sh" == true
#guard isDangerousBash "curl x | bash" == true
#guard isDangerousBash "curl x | shx" == false
#guard isDangerousBash "curl x|sh" == true
#guard isDangerousBash "wget -q y | sh -c z" == true
#guard isDangerousBash "curl a | x | sh" == false
#guard isDangerousBash "curl a > f; cat f | sh" == true
#guard isDangerousBash "mycurl x | sh" == true
#guard isDangerousBash "curl x" == false
#guard isDangerousBash "echo curl|sh" == true
#guard isDangerousBash "curl | ash" == false
#guard isDangerousBash "wget x | bashful" == false
#guard isDangerousBash "curl x |\tsh" == true
#guard isDangerousBash "curl x | sh;" == true
#guard isDangerousBash "rm-rf" == false
#guard isDangerousBash "curl x |sh\n" == true
#guard isDangerousBash "run sudo x" == true

-- isAskBash
#guard isAskBash "mercator-bootstrap.sh" == true
#guard isAskBash "bash scripts/mercator-bootstrap.sh" == true
#guard isAskBash "just bootstrap" == true
#guard isAskBash "just build" == true
#guard isAskBash "just --unstable build" == true
#guard isAskBash "just buildx" == false
#guard isAskBash "xjust build" == false
#guard isAskBash "just build-all" == true
#guard isAskBash "just rebuild" == false
#guard isAskBash "bootstrap" == false

-- hasWriteRedirectOrMutator
#guard hasWriteRedirectOrMutator "echo hi > f" == true
#guard hasWriteRedirectOrMutator "echo" == false
#guard hasWriteRedirectOrMutator "a>>b" == true
#guard hasWriteRedirectOrMutator "2> e" == true
#guard hasWriteRedirectOrMutator "&> f" == true
#guard hasWriteRedirectOrMutator "x &>> f" == true
#guard hasWriteRedirectOrMutator "sed -i s/a/b/ f" == true
#guard hasWriteRedirectOrMutator "sed -in" == false
#guard hasWriteRedirectOrMutator "sed -i.bak" == true
#guard hasWriteRedirectOrMutator "sed -i''" == true
#guard hasWriteRedirectOrMutator "tee f" == true
#guard hasWriteRedirectOrMutator "steep f" == false
#guard hasWriteRedirectOrMutator "mv a b" == true
#guard hasWriteRedirectOrMutator "cp a b" == true
#guard hasWriteRedirectOrMutator "rm f" == true
#guard hasWriteRedirectOrMutator "arm f" == false
#guard hasWriteRedirectOrMutator "rm" == true
#guard hasWriteRedirectOrMutator "rmx" == false
#guard hasWriteRedirectOrMutator "form" == false
#guard hasWriteRedirectOrMutator "9>>" == true
#guard hasWriteRedirectOrMutator "a > b" == true
#guard hasWriteRedirectOrMutator "->" == true
#guard hasWriteRedirectOrMutator "cat < f" == false
#guard hasWriteRedirectOrMutator "a 12> b" == true
#guard hasWriteRedirectOrMutator "sed  -i x" == true

-- isProtectedWriteTarget
#guard isProtectedWriteTarget "echo x > ESSENCE.md" == true
#guard isProtectedWriteTarget "cat ESSENCE.md" == true
#guard isProtectedWriteTarget "cp new.png essences/logo.png" == true
#guard isProtectedWriteTarget "cat essences/logo.png" == true
#guard isProtectedWriteTarget "essencesx" == false
#guard isProtectedWriteTarget "ESSENCE.mdx" == true
#guard isProtectedWriteTarget ".mercator/state/x" == true
#guard isProtectedWriteTarget "cat .env" == true
#guard isProtectedWriteTarget "cat .envx" == false
#guard isProtectedWriteTarget ".env.local" == true
#guard isProtectedWriteTarget ".env" == true
#guard isProtectedWriteTarget "x.env" == true
#guard isProtectedWriteTarget "secrets/" == true
#guard isProtectedWriteTarget "essence_attestations.jsonl" == true
#guard isProtectedWriteTarget ".agent/state/" == true
#guard isProtectedWriteTarget ".agent/statex" == false
#guard isProtectedWriteTarget "cat .env\n" == true
#guard isProtectedWriteTarget "echo .env | x" == true
#guard isProtectedWriteTarget "ESSENCE_md" == false

-- isDependencyInputBashMutation
#guard isDependencyInputBashMutation "echo x > package.json" == true
#guard isDependencyInputBashMutation "cat package.json" == false
#guard isDependencyInputBashMutation "echo > mypackage.json" == true
#guard isDependencyInputBashMutation "rm go.sum" == true
#guard isDependencyInputBashMutation "rm go.sumx" == false
#guard isDependencyInputBashMutation "echo a > x; echo b > package.json" == true
#guard isDependencyInputBashMutation "echo package.json > log" == false
#guard isDependencyInputBashMutation "mv requirements-dev.txt bak" == true
#guard isDependencyInputBashMutation "echo x > lakefile.lean" == true
#guard isDependencyInputBashMutation "sed -i s/a/b/ lakefile.toml" == true
#guard isDependencyInputBashMutation "echo x > lake-manifest.json" == true
#guard isDependencyInputBashMutation "echo leanprover/lean4:v4.15.0 > lean-toolchain" == true
#guard isDependencyInputBashMutation "echo x > Pipfile" == true
#guard isDependencyInputBashMutation "echo x > bunfig.toml" == true
#guard isDependencyInputBashMutation "tee .cargo/config.toml" == true
#guard isDependencyInputBashMutation "cat lakefile.lean" == false
#guard isDependencyInputBashMutation "lake build" == false
#guard isDependencyInputBashMutation "tee uv.lock" == true
#guard isDependencyInputBashMutation "cp a bun.lockb" == true
#guard isDependencyInputBashMutation "cp a bun.lock" == true
#guard isDependencyInputBashMutation "cp a bun.lockbb" == false
#guard isDependencyInputBashMutation "sed -i x pyproject.toml" == true
#guard isDependencyInputBashMutation "echo > f.txt" == false
#guard isDependencyInputBashMutation "rm x; echo package.json" == false
#guard isDependencyInputBashMutation "echo x | tee .npmrc" == true
#guard isDependencyInputBashMutation "> yarn.lock" == true
#guard isDependencyInputBashMutation "echo hi > a && rm Cargo.toml" == true
#guard isDependencyInputBashMutation "rm x; echo b > requirements.txt" == true
#guard isDependencyInputBashMutation "tee .yarnrc.yml" == true
#guard isDependencyInputBashMutation "tee .yarnrc" == true
#guard isDependencyInputBashMutation "rm requirements..txt" == true
#guard isDependencyInputBashMutation "rm requirementsX.txt2" == false
#guard isDependencyInputBashMutation "rm Pipfile.lock" == true
#guard isDependencyInputBashMutation "echo >> .pnpmfile.cjs" == true
#guard isDependencyInputBashMutation "rm go.mod" == true

-- isControlSurfaceBashMutation
#guard isControlSurfaceBashMutation "echo x > scripts/state.py" == true
#guard isControlSurfaceBashMutation "rm scripts/foo" == true
#guard isControlSurfaceBashMutation "python3 scripts/state.py validate > /dev/null" == false
#guard isControlSurfaceBashMutation "echo > ./scripts/new.sh" == true
#guard isControlSurfaceBashMutation "echo > /x/scripts/foo" == false
#guard isControlSurfaceBashMutation "mv templates/control/a b" == true
#guard isControlSurfaceBashMutation "mv templates/other/a b" == false
#guard isControlSurfaceBashMutation "rm recipes/x" == true
#guard isControlSurfaceBashMutation "echo > .agent/prompts/p" == true
#guard isControlSurfaceBashMutation "echo x >> META.md" == true
#guard isControlSurfaceBashMutation "echo >> META.mdx" == true
#guard isControlSurfaceBashMutation "echo > README.md" == true
#guard isControlSurfaceBashMutation "echo > README.mdx" == false
#guard isControlSurfaceBashMutation "echo > ./README.md" == true
#guard isControlSurfaceBashMutation "echo > x/README.md" == false
#guard isControlSurfaceBashMutation "echo > justfile" == true
#guard isControlSurfaceBashMutation "echo > justfilex" == false
#guard isControlSurfaceBashMutation "echo > myjustfile" == true
#guard isControlSurfaceBashMutation "rm scripts/mercator-foo.sh" == true
#guard isControlSurfaceBashMutation "rm scripts/mercator-foo2.sh" == true
#guard isControlSurfaceBashMutation "rm scripts/claude-trust.py" == true
#guard isControlSurfaceBashMutation "rm scripts/claude_trust.sh" == true
#guard isControlSurfaceBashMutation "cat scripts/state.py" == false
#guard isControlSurfaceBashMutation "cat scripts/state.py > /tmp/x" == false
#guard isControlSurfaceBashMutation "rm x; echo > scripts/a" == true
#guard isControlSurfaceBashMutation "echo > \"scripts/x\"" == true
#guard isControlSurfaceBashMutation "tee scripts/_lib.sh" == true
#guard isControlSurfaceBashMutation "rm 'recipes/y'" == true

-- isZoneBashMutation
#guard isZoneBashMutation "echo x > CLAUDE.md" == true
#guard isZoneBashMutation "echo x >CLAUDE.md" == false
#guard isZoneBashMutation "cat CLAUDE.md" == false
#guard isZoneBashMutation "echo > .claude/settings.json" == true
#guard isZoneBashMutation "rm -r x/.claude/y" == true
#guard isZoneBashMutation "echo > prompts/p" == true
#guard isZoneBashMutation "echo > myprompts/p" == false
#guard isZoneBashMutation "mv a agents/b" == true
#guard isZoneBashMutation "rm hooks/h" == true
#guard isZoneBashMutation "echo >> .github/workflows/ci.yml" == true
#guard isZoneBashMutation "echo > x.github/workflows/" == true
#guard isZoneBashMutation "rm scripts/myagent.sh" == true
#guard isZoneBashMutation "rm scripts/sub/agent" == true
#guard isZoneBashMutation "echo > settings.json" == true
#guard isZoneBashMutation "rm x/settings.json" == true
#guard isZoneBashMutation "rm xsettings.json" == false
#guard isZoneBashMutation "sed -i s/x/y/ AGENTS.md" == true
#guard isZoneBashMutation "tee .mcp.json" == true
#guard isZoneBashMutation "> agent-runtime/x" == true
#guard isZoneBashMutation "rm x/.cursor/rules" == true
#guard isZoneBashMutation "echo > skills/s" == true
#guard isZoneBashMutation "echo > CLAUDE.mdx" == false
#guard isZoneBashMutation "rm scripts/autonomous-x" == true
#guard isZoneBashMutation "rm scripts/x" == false
#guard isZoneBashMutation "echo hi > 'CLAUDE.md'" == true
#guard isZoneBashMutation "echo hi >= CLAUDE.md" == true

-- mutatesLiteralTarget
#guard mutatesLiteralTarget "CLAUDE.md" "echo hi > CLAUDE.md" == true
#guard mutatesLiteralTarget "CLAUDE.md" "cat CLAUDE.md" == false
#guard mutatesLiteralTarget "a.b" "rm x; echo a.b" == false
#guard mutatesLiteralTarget "a.b" "rm a.b" == true
#guard mutatesLiteralTarget "x" "echo > yxz" == true
#guard mutatesLiteralTarget "f" "tee f" == true
#guard mutatesLiteralTarget "f" "f > g" == false

-- bashPathishTokens
#guard bashPathishTokens "echo hi > .claude/settings.json 2>err"
  == [".claude/settings.json", "2", "echo", "err", "hi"]
#guard bashPathishTokens "mv a~b @scope/pkg" == ["@scope/pkg", "a~b", "mv"]
#guard bashPathishTokens "rm a a" == ["a", "rm"]
#guard bashPathishTokens "x; y | z" == ["x", "y", "z"]
#guard bashPathishTokens "curl -o f.tgz http://e.com/p"
  == ["-o", "//e.com/p", "curl", "f.tgz", "http"]

end Mercator.Core.Classify
