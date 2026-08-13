import AtlasBuilder.Core.Json
import AtlasBuilder.Core.Classify.Profile

/-!
`AtlasBuilder.Core.Settings` — セッション設定 overlay の純粋構築。

Atlas Builder が起動する Claude セッションのマシン依存部(パス系 permission
ルールと sandbox)は、git 追跡の base(`.claude/settings.json` — マシン
非依存、§16.1)には置かず、launcher が起動毎にここから生成して `--settings`
で渡すインライン JSON 1 行(overlay)として供給する。ディスクには書かない。
sandbox キーを base に置かないのは、`--settings` と base の間の sandbox
マージ意味論が undocumented だからである — overlay を唯一の供給源にすれば
未定義挙動への依存が消える(§16.1)。

- `boundSession` — 自律 loop / supervise の overlay(§16.1、§19.1-5)。
  base の `_atlas_builder_profile` が指す profile で ask/sandbox が決まる。
- `readOnlySession` — advisory triage / Essence インタビュー(I-022/I-027)の
  overlay。対象全体を OS 境界で読み取り専用にする。

入力のパスは解決済み絶対パスとして IO シェル側(`atlas-builder util
bound-settings` / `read-only-settings`)から注入される(§3.3-2)。Claude の
permission ルールは絶対パスを `//` で綴る一方、sandbox のパスは通常の
1 本スラッシュ — この差もここで固定する。
-/

namespace AtlasBuilder.Core.Settings

open AtlasBuilder.Core.Json
open AtlasBuilder.Core.Classify (Profile projectAskSurfaces)

/-- 機微入力面(§11.4)の sandbox パス列: 対象の秘密 4 面 + home の資格情報
ストア 10 面。read-only / bound 両 overlay の denyRead が共有する。 -/
private def secretInputPaths (project : String) : List String := [
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

/-- §11.3 列挙の control-plane 面(+ bin / lean = hook バイナリとその Lean
ソース)の sandbox denyWrite パス列。read-only / bound 両 overlay が共有する。 -/
private def controlDenyWritePaths (control : String) : List String :=
  [
    "CLAUDE.md", ".claude", "scripts", "templates", "recipes",
    "META.md", "README.md", "justfile", ".agent/prompts", ".agent/state",
    "bin", "lean"
  ].map (fun name => control ++ "/" ++ name)

/-- §11.3 列挙の control-plane 面の permission `Edit` deny ルール列
(`.claude` は修復 ask 面 `settings.json` を潰さないサブ面列挙 — §28.5-3)。
read-only / bound 両 overlay が共有する: CLI >=2.1.216 の Edit deny は
Write ツール・Bash 書込先解析・sandbox 合成の 3 層へ波及するため(§28.5)、
Write を有効に保つ read-only セッションでもこの settings 層は多層防御の
1 層として実働する。 -/
private def controlDenyEditRules (permissionControl : String) : List String :=
  [
    "CLAUDE.md", ".claude/agents/**", ".claude/commands/**",
    ".claude/rules/**", ".claude/skills/**", "scripts/**",
    "templates/**", "recipes/**", "META.md",
    "README.md", "justfile", ".agent/prompts/**",
    ".agent/state/**", "bin/**", "lean/**"
  ].map (s!"Edit({permissionControl}/{·})")

/-- §28.5-3 の人間承認付き live-settings 修復面(permission ask ルール)。
base にはパスルールを置かないため、この宣言的 ask 床は全 overlay が担う。 -/
private def liveSettingsRepairAsk (permissionControl : String) : String :=
  s!"Edit({permissionControl}/.claude/settings.json)"

/-- `--settings` に渡す read-only セッション設定(JSON 値)。キー順・直列化は
旧 Python 実装の `json.dumps(..., separators=(",", ":"))` と同形
(`renderCompactAscii`)。書き込み可能なのは wrapper が直前に用意した
handoff ディレクトリのみ、機微入力面(§11.4)は読み取りも拒否する。

ask は両 variant で常設: 末尾の live-settings 修復面(§28.5-3)は base が
パスルールを持たなくなったため overlay が唯一の宣言点である。deny は
§11.3 の control 面列挙(`controlDenyEditRules` — 分割前は bound base が
供給していた settings 層。base がパスルールを失った後も read-only
セッションの多層防御 1 層として overlay が保持する)+ 対象の秘密 4 面。
`essenceNew` は new-Essence インタビュー(§2.1.4)の variant: 対象一括の
`Edit({project}/**)` deny を置かず、代わりに `Edit({project}/ESSENCE.md)` と
`Edit({project}/essences/**)` を ask の先頭に載せる — deny は hook の
ask/allow より常に優先されるため(§28.5)、一括 deny があると I-027 第二経路
(人間が permission prompt で承認する ESSENCE.md 直接設置 fallback と、その
§2.1.5 面 = essences/ 資産設置)が成立しない。それ以外の対象書き込みは
hook が明示 deny し(G-T2 の ask 面列挙)、Bash は sandbox denyWrite が
対象全体を塞いだままなので、読み取り専用境界は縮まない。 -/
def readOnlySession (project control handoff : String)
    (essenceNew : Bool := false) : Value :=
  let permissionProject := "/" ++ project
  let permissionControl := "/" ++ control
  .obj [
    ("permissions", .obj [
      ("ask", .arr ((
        (if essenceNew then
          [s!"Edit({permissionProject}/ESSENCE.md)",
           s!"Edit({permissionProject}/essences/**)"]
         else []) ++
        [liveSettingsRepairAsk permissionControl]).map .str)),
      ("deny", .arr ((
        controlDenyEditRules permissionControl ++ [
        s!"Read({permissionProject}/.env)",
        s!"Read({permissionProject}/.env.*)",
        s!"Read({permissionProject}/secrets/**)",
        s!"Read({permissionProject}/config/credentials.json)"
      ] ++ (if essenceNew then [] else [s!"Edit({permissionProject}/**)"])
      ).map .str))]),
    ("sandbox", .obj [
      ("enabled", .bool true),
      ("failIfUnavailable", .bool true),
      ("autoAllowBashIfSandboxed", .bool false),
      ("allowUnsandboxedCommands", .bool false),
      -- advisory human sessions do not require subprocess network access
      ("network", .obj [("allowedDomains", .arr [])]),
      ("filesystem", .obj [
        ("allowWrite", .arr [.str handoff]),
        ("denyRead", .arr ((secretInputPaths project).map .str)),
        ("denyWrite", .arr ((project :: controlDenyWritePaths control).map .str))
      ])
    ])
  ]

/-- 自律 loop / supervise セッションの bound overlay(§16.1)。launcher が
lock 取得後に `atlas-builder util bound-settings` で invocation につき 1 回生成し
`--settings` で渡す — lock 後生成なので、init を含むどの framework 遷移も
invocation 中に base(profile)を書き換えられない(I-018)。

- allow: headless(`claude -p`)では unmatched → deny が床(§19.1-5)なので、
  project の Read/Edit と control の Read は明示 allow が必須。
- ask: standard は project 側 agent-runtime 3 面(`projectAskSurfaces` — 定義
  共有)+ 修復面。relaxed 2 態は 3 面を落とす(settings の ask は hook の
  allow に常に勝つため、残すと profile が該当面で無効化される、§11.5)。
  修復面(§28.5-3)は全 profile 常設。
- deny: §11.3 列挙の control 面 Edit(一括 deny は CLI >=2.1.216 で
  .agent/tmp の handoff/lock 書込みを塞ぐため列挙、§28.5)+ 人間所有入力
  (I-004)+ 秘密面 Read(I-024)。
- sandbox: 完全体。unsandboxed は `enabled` の反転のみで filesystem/network
  は保持する — sandbox を降ろした配備でも宣言の床を陳腐化させない(§11.5)。 -/
def boundSession (project control : String) (profile : Profile) : Value :=
  let permissionProject := "/" ++ project
  let permissionControl := "/" ++ control
  .obj [
    ("permissions", .obj [
      ("additionalDirectories", .arr [.str project]),
      ("allow", .arr ([
        s!"Read({permissionControl}/**)",
        s!"Read({permissionProject}/**)",
        s!"Edit({permissionProject}/**)"].map .str)),
      ("ask", .arr ((
        (if profile == .standard then
          projectAskSurfaces.map (s!"Edit({permissionProject}/{·})")
         else []) ++
        [liveSettingsRepairAsk permissionControl]).map .str)),
      ("deny", .arr ((
        controlDenyEditRules permissionControl ++
        [
          s!"Edit({permissionProject}/ESSENCE.md)",
          s!"Edit({permissionProject}/essences/**)",
          s!"Read({permissionProject}/.env)",
          s!"Read({permissionProject}/.env.*)",
          s!"Read({permissionProject}/secrets/**)",
          s!"Read({permissionProject}/config/credentials.json)"
        ]).map .str))
    ]),
    ("sandbox", .obj [
      ("enabled", .bool (profile != .unsandboxed)),
      ("failIfUnavailable", .bool true),
      ("autoAllowBashIfSandboxed", .bool false),
      ("allowUnsandboxedCommands", .bool false),
      ("network", .obj [("allowedDomains", .arr ([
        "github.com", "api.github.com", "raw.githubusercontent.com",
        "objects.githubusercontent.com", "registry.npmjs.org", "pypi.org",
        "files.pythonhosted.org", "crates.io", "static.crates.io",
        "index.crates.io", "proxy.golang.org", "sum.golang.org",
        "releases.lean-lang.org"].map .str))]),
      ("filesystem", .obj [
        ("allowWrite", .arr ([project, control ++ "/.agent/tmp"].map .str)),
        ("denyRead", .arr ((secretInputPaths project).map .str)),
        ("denyWrite", .arr ((
          [
            project ++ "/ESSENCE.md",
            project ++ "/essences",
            project ++ "/.env",
            project ++ "/.env.*",
            project ++ "/secrets",
            project ++ "/config/credentials.json",
            project ++ "/.atlas-builder/state/project.json"
          ] ++ controlDenyWritePaths control).map .str))
      ])
    ])
  ]

/-- base settings(パース済み)から `_atlas_builder_profile` を読む。欠落・非文字列
・閉集合外は none — unbound / 旧形式の base であり、呼び出し側
(`util bound-settings` / doctor)が `just init` へ誘導する(§16.1、§11.5)。
profile は init 経由でのみ発効する、の読み手側の実体。 -/
def baseProfile? (settings : Value) : Option Profile :=
  ((settings.get? "_atlas_builder_profile").bind Value.asStr?).bind Profile.parse?

#guard baseProfile? (.obj [("_atlas_builder_profile", .str "auto-approve")])
  == some .autoApprove
#guard baseProfile? (.obj [("_atlas_builder_profile", .str "poc")]) == none
#guard baseProfile? (.obj [("_atlas_builder_profile", .bool true)]) == none
#guard baseProfile? (.obj [("model", .str "best")]) == none

-- 実出力の凍結(read-only: 修復 ask 面が両 variant の ask 末尾に常設)
#guard (readOnlySession "/w/proj" "/w/.atlas-builder" "/w/.atlas-builder/.agent/tmp/triage"
    ).renderCompactAscii
    == "{\"permissions\":{\"ask\":[\"Edit(//w/.atlas-builder/.claude/settings.json)\"],\"deny\":[\"Edit(//w/.atlas-builder/CLAUDE.md)\",\"Edit(//w/.atlas-builder/.claude/agents/**)\",\"Edit(//w/.atlas-builder/.claude/commands/**)\",\"Edit(//w/.atlas-builder/.claude/rules/**)\",\"Edit(//w/.atlas-builder/.claude/skills/**)\",\"Edit(//w/.atlas-builder/scripts/**)\",\"Edit(//w/.atlas-builder/templates/**)\",\"Edit(//w/.atlas-builder/recipes/**)\",\"Edit(//w/.atlas-builder/META.md)\",\"Edit(//w/.atlas-builder/README.md)\",\"Edit(//w/.atlas-builder/justfile)\",\"Edit(//w/.atlas-builder/.agent/prompts/**)\",\"Edit(//w/.atlas-builder/.agent/state/**)\",\"Edit(//w/.atlas-builder/bin/**)\",\"Edit(//w/.atlas-builder/lean/**)\",\"Read(//w/proj/.env)\",\"Read(//w/proj/.env.*)\",\"Read(//w/proj/secrets/**)\",\"Read(//w/proj/config/credentials.json)\",\"Edit(//w/proj/**)\"]},\"sandbox\":{\"enabled\":true,\"failIfUnavailable\":true,\"autoAllowBashIfSandboxed\":false,\"allowUnsandboxedCommands\":false,\"network\":{\"allowedDomains\":[]},\"filesystem\":{\"allowWrite\":[\"/w/.atlas-builder/.agent/tmp/triage\"],\"denyRead\":[\"/w/proj/.env\",\"/w/proj/.env.*\",\"/w/proj/secrets\",\"/w/proj/config/credentials.json\",\"~/.ssh\",\"~/.aws\",\"~/.config/gcloud\",\"~/.kube\",\"~/.docker/config.json\",\"~/.npmrc\",\"~/.pypirc\",\"~/.netrc\",\"~/.claude\",\"~/.claude.json\"],\"denyWrite\":[\"/w/proj\",\"/w/.atlas-builder/CLAUDE.md\",\"/w/.atlas-builder/.claude\",\"/w/.atlas-builder/scripts\",\"/w/.atlas-builder/templates\",\"/w/.atlas-builder/recipes\",\"/w/.atlas-builder/META.md\",\"/w/.atlas-builder/README.md\",\"/w/.atlas-builder/justfile\",\"/w/.atlas-builder/.agent/prompts\",\"/w/.atlas-builder/.agent/state\",\"/w/.atlas-builder/bin\",\"/w/.atlas-builder/lean\"]}}}"

-- essence-new variant の凍結: 一括 Edit deny を置かず、ESSENCE.md /
-- essences/** を ask の先頭に載せる(I-027 第二経路)。sandbox は不変。
#guard (readOnlySession "/w/proj" "/w/.atlas-builder" "/w/.atlas-builder/.agent/tmp/essence"
      (essenceNew := true)).renderCompactAscii
    == "{\"permissions\":{\"ask\":[\"Edit(//w/proj/ESSENCE.md)\",\"Edit(//w/proj/essences/**)\",\"Edit(//w/.atlas-builder/.claude/settings.json)\"],\"deny\":[\"Edit(//w/.atlas-builder/CLAUDE.md)\",\"Edit(//w/.atlas-builder/.claude/agents/**)\",\"Edit(//w/.atlas-builder/.claude/commands/**)\",\"Edit(//w/.atlas-builder/.claude/rules/**)\",\"Edit(//w/.atlas-builder/.claude/skills/**)\",\"Edit(//w/.atlas-builder/scripts/**)\",\"Edit(//w/.atlas-builder/templates/**)\",\"Edit(//w/.atlas-builder/recipes/**)\",\"Edit(//w/.atlas-builder/META.md)\",\"Edit(//w/.atlas-builder/README.md)\",\"Edit(//w/.atlas-builder/justfile)\",\"Edit(//w/.atlas-builder/.agent/prompts/**)\",\"Edit(//w/.atlas-builder/.agent/state/**)\",\"Edit(//w/.atlas-builder/bin/**)\",\"Edit(//w/.atlas-builder/lean/**)\",\"Read(//w/proj/.env)\",\"Read(//w/proj/.env.*)\",\"Read(//w/proj/secrets/**)\",\"Read(//w/proj/config/credentials.json)\"]},\"sandbox\":{\"enabled\":true,\"failIfUnavailable\":true,\"autoAllowBashIfSandboxed\":false,\"allowUnsandboxedCommands\":false,\"network\":{\"allowedDomains\":[]},\"filesystem\":{\"allowWrite\":[\"/w/.atlas-builder/.agent/tmp/essence\"],\"denyRead\":[\"/w/proj/.env\",\"/w/proj/.env.*\",\"/w/proj/secrets\",\"/w/proj/config/credentials.json\",\"~/.ssh\",\"~/.aws\",\"~/.config/gcloud\",\"~/.kube\",\"~/.docker/config.json\",\"~/.npmrc\",\"~/.pypirc\",\"~/.netrc\",\"~/.claude\",\"~/.claude.json\"],\"denyWrite\":[\"/w/proj\",\"/w/.atlas-builder/CLAUDE.md\",\"/w/.atlas-builder/.claude\",\"/w/.atlas-builder/scripts\",\"/w/.atlas-builder/templates\",\"/w/.atlas-builder/recipes\",\"/w/.atlas-builder/META.md\",\"/w/.atlas-builder/README.md\",\"/w/.atlas-builder/justfile\",\"/w/.atlas-builder/.agent/prompts\",\"/w/.atlas-builder/.agent/state\",\"/w/.atlas-builder/bin\",\"/w/.atlas-builder/lean\"]}}}"

-- 実出力の凍結(bound overlay、3 profile)。standard は project 側 ask 3 面
-- + 修復面。
#guard (boundSession "/w/proj" "/w/.atlas-builder" Profile.standard).renderCompactAscii
    == "{\"permissions\":{\"additionalDirectories\":[\"/w/proj\"],\"allow\":[\"Read(//w/.atlas-builder/**)\",\"Read(//w/proj/**)\",\"Edit(//w/proj/**)\"],\"ask\":[\"Edit(//w/proj/CLAUDE.md)\",\"Edit(//w/proj/.claude/**)\",\"Edit(//w/proj/.mcp.json)\",\"Edit(//w/.atlas-builder/.claude/settings.json)\"],\"deny\":[\"Edit(//w/.atlas-builder/CLAUDE.md)\",\"Edit(//w/.atlas-builder/.claude/agents/**)\",\"Edit(//w/.atlas-builder/.claude/commands/**)\",\"Edit(//w/.atlas-builder/.claude/rules/**)\",\"Edit(//w/.atlas-builder/.claude/skills/**)\",\"Edit(//w/.atlas-builder/scripts/**)\",\"Edit(//w/.atlas-builder/templates/**)\",\"Edit(//w/.atlas-builder/recipes/**)\",\"Edit(//w/.atlas-builder/META.md)\",\"Edit(//w/.atlas-builder/README.md)\",\"Edit(//w/.atlas-builder/justfile)\",\"Edit(//w/.atlas-builder/.agent/prompts/**)\",\"Edit(//w/.atlas-builder/.agent/state/**)\",\"Edit(//w/.atlas-builder/bin/**)\",\"Edit(//w/.atlas-builder/lean/**)\",\"Edit(//w/proj/ESSENCE.md)\",\"Edit(//w/proj/essences/**)\",\"Read(//w/proj/.env)\",\"Read(//w/proj/.env.*)\",\"Read(//w/proj/secrets/**)\",\"Read(//w/proj/config/credentials.json)\"]},\"sandbox\":{\"enabled\":true,\"failIfUnavailable\":true,\"autoAllowBashIfSandboxed\":false,\"allowUnsandboxedCommands\":false,\"network\":{\"allowedDomains\":[\"github.com\",\"api.github.com\",\"raw.githubusercontent.com\",\"objects.githubusercontent.com\",\"registry.npmjs.org\",\"pypi.org\",\"files.pythonhosted.org\",\"crates.io\",\"static.crates.io\",\"index.crates.io\",\"proxy.golang.org\",\"sum.golang.org\",\"releases.lean-lang.org\"]},\"filesystem\":{\"allowWrite\":[\"/w/proj\",\"/w/.atlas-builder/.agent/tmp\"],\"denyRead\":[\"/w/proj/.env\",\"/w/proj/.env.*\",\"/w/proj/secrets\",\"/w/proj/config/credentials.json\",\"~/.ssh\",\"~/.aws\",\"~/.config/gcloud\",\"~/.kube\",\"~/.docker/config.json\",\"~/.npmrc\",\"~/.pypirc\",\"~/.netrc\",\"~/.claude\",\"~/.claude.json\"],\"denyWrite\":[\"/w/proj/ESSENCE.md\",\"/w/proj/essences\",\"/w/proj/.env\",\"/w/proj/.env.*\",\"/w/proj/secrets\",\"/w/proj/config/credentials.json\",\"/w/proj/.atlas-builder/state/project.json\",\"/w/.atlas-builder/CLAUDE.md\",\"/w/.atlas-builder/.claude\",\"/w/.atlas-builder/scripts\",\"/w/.atlas-builder/templates\",\"/w/.atlas-builder/recipes\",\"/w/.atlas-builder/META.md\",\"/w/.atlas-builder/README.md\",\"/w/.atlas-builder/justfile\",\"/w/.atlas-builder/.agent/prompts\",\"/w/.atlas-builder/.agent/state\",\"/w/.atlas-builder/bin\",\"/w/.atlas-builder/lean\"]}}}"

-- auto-approve: project 側 ask 3 面のみ不在(修復面・deny・allow・sandbox は
-- standard と同一)。
#guard (boundSession "/w/proj" "/w/.atlas-builder" Profile.autoApprove).renderCompactAscii
    == "{\"permissions\":{\"additionalDirectories\":[\"/w/proj\"],\"allow\":[\"Read(//w/.atlas-builder/**)\",\"Read(//w/proj/**)\",\"Edit(//w/proj/**)\"],\"ask\":[\"Edit(//w/.atlas-builder/.claude/settings.json)\"],\"deny\":[\"Edit(//w/.atlas-builder/CLAUDE.md)\",\"Edit(//w/.atlas-builder/.claude/agents/**)\",\"Edit(//w/.atlas-builder/.claude/commands/**)\",\"Edit(//w/.atlas-builder/.claude/rules/**)\",\"Edit(//w/.atlas-builder/.claude/skills/**)\",\"Edit(//w/.atlas-builder/scripts/**)\",\"Edit(//w/.atlas-builder/templates/**)\",\"Edit(//w/.atlas-builder/recipes/**)\",\"Edit(//w/.atlas-builder/META.md)\",\"Edit(//w/.atlas-builder/README.md)\",\"Edit(//w/.atlas-builder/justfile)\",\"Edit(//w/.atlas-builder/.agent/prompts/**)\",\"Edit(//w/.atlas-builder/.agent/state/**)\",\"Edit(//w/.atlas-builder/bin/**)\",\"Edit(//w/.atlas-builder/lean/**)\",\"Edit(//w/proj/ESSENCE.md)\",\"Edit(//w/proj/essences/**)\",\"Read(//w/proj/.env)\",\"Read(//w/proj/.env.*)\",\"Read(//w/proj/secrets/**)\",\"Read(//w/proj/config/credentials.json)\"]},\"sandbox\":{\"enabled\":true,\"failIfUnavailable\":true,\"autoAllowBashIfSandboxed\":false,\"allowUnsandboxedCommands\":false,\"network\":{\"allowedDomains\":[\"github.com\",\"api.github.com\",\"raw.githubusercontent.com\",\"objects.githubusercontent.com\",\"registry.npmjs.org\",\"pypi.org\",\"files.pythonhosted.org\",\"crates.io\",\"static.crates.io\",\"index.crates.io\",\"proxy.golang.org\",\"sum.golang.org\",\"releases.lean-lang.org\"]},\"filesystem\":{\"allowWrite\":[\"/w/proj\",\"/w/.atlas-builder/.agent/tmp\"],\"denyRead\":[\"/w/proj/.env\",\"/w/proj/.env.*\",\"/w/proj/secrets\",\"/w/proj/config/credentials.json\",\"~/.ssh\",\"~/.aws\",\"~/.config/gcloud\",\"~/.kube\",\"~/.docker/config.json\",\"~/.npmrc\",\"~/.pypirc\",\"~/.netrc\",\"~/.claude\",\"~/.claude.json\"],\"denyWrite\":[\"/w/proj/ESSENCE.md\",\"/w/proj/essences\",\"/w/proj/.env\",\"/w/proj/.env.*\",\"/w/proj/secrets\",\"/w/proj/config/credentials.json\",\"/w/proj/.atlas-builder/state/project.json\",\"/w/.atlas-builder/CLAUDE.md\",\"/w/.atlas-builder/.claude\",\"/w/.atlas-builder/scripts\",\"/w/.atlas-builder/templates\",\"/w/.atlas-builder/recipes\",\"/w/.atlas-builder/META.md\",\"/w/.atlas-builder/README.md\",\"/w/.atlas-builder/justfile\",\"/w/.atlas-builder/.agent/prompts\",\"/w/.atlas-builder/.agent/state\",\"/w/.atlas-builder/bin\",\"/w/.atlas-builder/lean\"]}}}"

-- unsandboxed: さらに sandbox.enabled=false のみが追加差分
-- (filesystem/network は保持 — §11.5)。
#guard (boundSession "/w/proj" "/w/.atlas-builder" Profile.unsandboxed).renderCompactAscii
    == "{\"permissions\":{\"additionalDirectories\":[\"/w/proj\"],\"allow\":[\"Read(//w/.atlas-builder/**)\",\"Read(//w/proj/**)\",\"Edit(//w/proj/**)\"],\"ask\":[\"Edit(//w/.atlas-builder/.claude/settings.json)\"],\"deny\":[\"Edit(//w/.atlas-builder/CLAUDE.md)\",\"Edit(//w/.atlas-builder/.claude/agents/**)\",\"Edit(//w/.atlas-builder/.claude/commands/**)\",\"Edit(//w/.atlas-builder/.claude/rules/**)\",\"Edit(//w/.atlas-builder/.claude/skills/**)\",\"Edit(//w/.atlas-builder/scripts/**)\",\"Edit(//w/.atlas-builder/templates/**)\",\"Edit(//w/.atlas-builder/recipes/**)\",\"Edit(//w/.atlas-builder/META.md)\",\"Edit(//w/.atlas-builder/README.md)\",\"Edit(//w/.atlas-builder/justfile)\",\"Edit(//w/.atlas-builder/.agent/prompts/**)\",\"Edit(//w/.atlas-builder/.agent/state/**)\",\"Edit(//w/.atlas-builder/bin/**)\",\"Edit(//w/.atlas-builder/lean/**)\",\"Edit(//w/proj/ESSENCE.md)\",\"Edit(//w/proj/essences/**)\",\"Read(//w/proj/.env)\",\"Read(//w/proj/.env.*)\",\"Read(//w/proj/secrets/**)\",\"Read(//w/proj/config/credentials.json)\"]},\"sandbox\":{\"enabled\":false,\"failIfUnavailable\":true,\"autoAllowBashIfSandboxed\":false,\"allowUnsandboxedCommands\":false,\"network\":{\"allowedDomains\":[\"github.com\",\"api.github.com\",\"raw.githubusercontent.com\",\"objects.githubusercontent.com\",\"registry.npmjs.org\",\"pypi.org\",\"files.pythonhosted.org\",\"crates.io\",\"static.crates.io\",\"index.crates.io\",\"proxy.golang.org\",\"sum.golang.org\",\"releases.lean-lang.org\"]},\"filesystem\":{\"allowWrite\":[\"/w/proj\",\"/w/.atlas-builder/.agent/tmp\"],\"denyRead\":[\"/w/proj/.env\",\"/w/proj/.env.*\",\"/w/proj/secrets\",\"/w/proj/config/credentials.json\",\"~/.ssh\",\"~/.aws\",\"~/.config/gcloud\",\"~/.kube\",\"~/.docker/config.json\",\"~/.npmrc\",\"~/.pypirc\",\"~/.netrc\",\"~/.claude\",\"~/.claude.json\"],\"denyWrite\":[\"/w/proj/ESSENCE.md\",\"/w/proj/essences\",\"/w/proj/.env\",\"/w/proj/.env.*\",\"/w/proj/secrets\",\"/w/proj/config/credentials.json\",\"/w/proj/.atlas-builder/state/project.json\",\"/w/.atlas-builder/CLAUDE.md\",\"/w/.atlas-builder/.claude\",\"/w/.atlas-builder/scripts\",\"/w/.atlas-builder/templates\",\"/w/.atlas-builder/recipes\",\"/w/.atlas-builder/META.md\",\"/w/.atlas-builder/README.md\",\"/w/.atlas-builder/justfile\",\"/w/.atlas-builder/.agent/prompts\",\"/w/.atlas-builder/.agent/state\",\"/w/.atlas-builder/bin\",\"/w/.atlas-builder/lean\"]}}}"

end AtlasBuilder.Core.Settings
