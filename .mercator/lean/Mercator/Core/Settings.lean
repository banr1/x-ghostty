import Mercator.Core.Json

/-!
`Mercator.Core.Settings` — read-only セッション設定の純粋構築。

`_lib.sh` の `build_read_only_session_settings`(旧インライン Python)の判定核。
advisory triage と Essence インタビュー(I-022/I-027)が使う必須サンドボックス
設定を生成する: 対象全体を OS 境界で読み取り専用にし、書き込み可能なのは
wrapper が直前に用意した handoff ディレクトリのみ、機微入力面(§11.4)は
読み取りも拒否する。

入力の 3 パス(project / control / handoff)は解決済み絶対パスとして
IO シェル側(`mercator util read-only-settings`)から注入される(§3.3-2)。
Claude の permission ルールは絶対パスを `//` で綴る一方、sandbox のパスは
通常の 1 本スラッシュ — この差もここで固定する。
-/

namespace Mercator.Core.Settings

open Mercator.Core.Json

/-- `--settings` に渡す read-only セッション設定(JSON 値)。キー順・直列化は
旧 Python 実装の `json.dumps(..., separators=(",", ":"))` と同形
(`renderCompactAscii`)。denyWrite の control 面は §11.3 列挙 + bin / lean
(hook バイナリとその Lean ソース)。

`essenceNew` は new-Essence インタビュー(§2.1.4)の variant: 対象一括の
`Edit({project}/**)` deny を置かず、代わりに `Edit({project}/ESSENCE.md)` と
`Edit({project}/essences/**)` を ask に載せる — deny は hook の ask/allow より
常に優先されるため(§28.5)、一括 deny があると I-027 第二経路(人間が
permission prompt で承認する ESSENCE.md 直接設置 fallback と、その §2.1.5 面
= essences/ 資産設置)が成立しない。それ以外の対象書き込みは
hook が明示 deny し(G-T2 の ask 面列挙)、Bash は sandbox denyWrite が
対象全体を塞いだままなので、読み取り専用境界は縮まない。 -/
def readOnlySession (project control handoff : String)
    (essenceNew : Bool := false) : Value :=
  let permissionProject := "/" ++ project
  let secretPaths := [
    project ++ "/.env",
    project ++ "/.env.*",
    project ++ "/secrets",
    project ++ "/config/credentials.json",
    "~/.ssh",
    "~/.aws",
    "~/.config/gcloud",
    "~/.kube",
    "~/.docker/config.json",
    "~/.npmrc",
    "~/.pypirc",
    "~/.netrc",
    "~/.claude",
    "~/.claude.json"
  ]
  let controlDenyWrite := [
    "CLAUDE.md", ".claude", "scripts", "templates", "recipes",
    "META.md", "README.md", "justfile", ".agent/prompts", ".agent/state",
    "bin", "lean"
  ].map (fun name => control ++ "/" ++ name)
  .obj [
    ("permissions", .obj (
      (if essenceNew then
        [("ask", .arr [.str s!"Edit({permissionProject}/ESSENCE.md)",
                       .str s!"Edit({permissionProject}/essences/**)"])]
       else []) ++
      [("deny", .arr (([
        s!"Read({permissionProject}/.env)",
        s!"Read({permissionProject}/.env.*)",
        s!"Read({permissionProject}/secrets/**)",
        s!"Read({permissionProject}/config/credentials.json)"
      ] ++ (if essenceNew then [] else [s!"Edit({permissionProject}/**)"])
      ).map .str))])),
    ("sandbox", .obj [
      ("enabled", .bool true),
      ("failIfUnavailable", .bool true),
      ("autoAllowBashIfSandboxed", .bool false),
      ("allowUnsandboxedCommands", .bool false),
      -- advisory human sessions do not require subprocess network access
      ("network", .obj [("allowedDomains", .arr [])]),
      ("filesystem", .obj [
        ("allowWrite", .arr [.str handoff]),
        ("denyRead", .arr (secretPaths.map .str)),
        ("denyWrite", .arr ((project :: controlDenyWrite).map .str))
      ])
    ])
  ]

-- 実出力の凍結(旧 Python 実装の採取値に bin / lean の denyWrite 追加を反映)
#guard (readOnlySession "/w/proj" "/w/.mercator" "/w/.mercator/.agent/tmp/triage"
    ).renderCompactAscii
    == "{\"permissions\":{\"deny\":[\"Read(//w/proj/.env)\",\"Read(//w/proj/.env.*)\",\"Read(//w/proj/secrets/**)\",\"Read(//w/proj/config/credentials.json)\",\"Edit(//w/proj/**)\"]},\"sandbox\":{\"enabled\":true,\"failIfUnavailable\":true,\"autoAllowBashIfSandboxed\":false,\"allowUnsandboxedCommands\":false,\"network\":{\"allowedDomains\":[]},\"filesystem\":{\"allowWrite\":[\"/w/.mercator/.agent/tmp/triage\"],\"denyRead\":[\"/w/proj/.env\",\"/w/proj/.env.*\",\"/w/proj/secrets\",\"/w/proj/config/credentials.json\",\"~/.ssh\",\"~/.aws\",\"~/.config/gcloud\",\"~/.kube\",\"~/.docker/config.json\",\"~/.npmrc\",\"~/.pypirc\",\"~/.netrc\",\"~/.claude\",\"~/.claude.json\"],\"denyWrite\":[\"/w/proj\",\"/w/.mercator/CLAUDE.md\",\"/w/.mercator/.claude\",\"/w/.mercator/scripts\",\"/w/.mercator/templates\",\"/w/.mercator/recipes\",\"/w/.mercator/META.md\",\"/w/.mercator/README.md\",\"/w/.mercator/justfile\",\"/w/.mercator/.agent/prompts\",\"/w/.mercator/.agent/state\",\"/w/.mercator/bin\",\"/w/.mercator/lean\"]}}}"

-- essence-new variant の凍結: 一括 Edit deny を置かず、ESSENCE.md を ask に
-- 載せる(I-027 第二経路)。sandbox は不変(対象全体の denyWrite は Bash の
-- OS 境界として維持)。
#guard (readOnlySession "/w/proj" "/w/.mercator" "/w/.mercator/.agent/tmp/essence"
      (essenceNew := true)).renderCompactAscii
    == "{\"permissions\":{\"ask\":[\"Edit(//w/proj/ESSENCE.md)\",\"Edit(//w/proj/essences/**)\"],\"deny\":[\"Read(//w/proj/.env)\",\"Read(//w/proj/.env.*)\",\"Read(//w/proj/secrets/**)\",\"Read(//w/proj/config/credentials.json)\"]},\"sandbox\":{\"enabled\":true,\"failIfUnavailable\":true,\"autoAllowBashIfSandboxed\":false,\"allowUnsandboxedCommands\":false,\"network\":{\"allowedDomains\":[]},\"filesystem\":{\"allowWrite\":[\"/w/.mercator/.agent/tmp/essence\"],\"denyRead\":[\"/w/proj/.env\",\"/w/proj/.env.*\",\"/w/proj/secrets\",\"/w/proj/config/credentials.json\",\"~/.ssh\",\"~/.aws\",\"~/.config/gcloud\",\"~/.kube\",\"~/.docker/config.json\",\"~/.npmrc\",\"~/.pypirc\",\"~/.netrc\",\"~/.claude\",\"~/.claude.json\"],\"denyWrite\":[\"/w/proj\",\"/w/.mercator/CLAUDE.md\",\"/w/.mercator/.claude\",\"/w/.mercator/scripts\",\"/w/.mercator/templates\",\"/w/.mercator/recipes\",\"/w/.mercator/META.md\",\"/w/.mercator/README.md\",\"/w/.mercator/justfile\",\"/w/.mercator/.agent/prompts\",\"/w/.mercator/.agent/state\",\"/w/.mercator/bin\",\"/w/.mercator/lean\"]}}}"

end Mercator.Core.Settings
