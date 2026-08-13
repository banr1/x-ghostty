import AtlasBuilder

/-!
マルチコールバイナリ `atlas-builder` のエントリポイント。サブコマンドをディスパッチする
IO シェルであり、判定ロジック自体は `AtlasBuilder.Core` / `AtlasBuilder.Hook` 側の
純粋定義に委譲する。
-/

def usage : String :=
  "usage: atlas-builder <subcommand>\nimplemented subcommands: version, hook stop, hook session-start, hook pre-compact, hook pre-tool, hook post-tool, recipe hash, trust status, trust ensure, state ensure, state validate, state should-stop, state should-complete, state should-reset, state record-progress, state raise-loop-gates, state start-run, state end-run, state reset-context, state resume, state status, state watch-render, util json-get, util stop-status, util token, util file-age-exceeds, util read-only-settings, util bound-settings, util loop-heartbeat, util relpath, util render, util seed, util project-index, util json-check, util dangling-run, util settings-doctor, util essence-profile, util static-config"

def main (args : List String) : IO UInt32 := do
  match args with
  | ["version"] =>
    IO.println s!"atlas-builder {AtlasBuilder.Core.versionString}"
    pure 0
  | ["hook", "stop"] =>
    AtlasBuilder.Cli.Hook.runStop
  | ["hook", "session-start"] =>
    AtlasBuilder.Cli.Hook.runSessionStart
  | ["hook", "pre-compact"] =>
    AtlasBuilder.Cli.Hook.runPreCompact
  | ["hook", "pre-tool"] =>
    AtlasBuilder.Cli.Hook.runPreTool
  | ["hook", "post-tool"] =>
    AtlasBuilder.Cli.Hook.runPostTool
  | "recipe" :: rest =>
    AtlasBuilder.Cli.Recipe.run rest
  | "trust" :: rest =>
    AtlasBuilder.Cli.Trust.run rest
  | "state" :: "watch-render" :: rest =>
    -- watch の単発描画面(§15.3)。`Cli.State.run` より前に受けることで、
    -- state.py 由来の凍結面(argparse / mutatingCommands)に触れない。
    AtlasBuilder.Cli.Watch.run rest
  | "state" :: rest =>
    AtlasBuilder.Cli.State.run rest
  | "util" :: rest =>
    AtlasBuilder.Cli.Util.run rest
  | "hook" :: rest =>
    -- 未知の hook イベントは配線ミス(運用者エラー)なので、hooks の
    -- fail-open 契約(常に exit 0)ではなく、他の未知サブコマンドと同じく
    -- exit 2 で大きく落とす。
    let event := String.intercalate " " rest
    IO.eprintln s!"atlas-builder: unknown hook event: {event}"
    pure 2
  | [] =>
    IO.eprintln usage
    pure 2
  | subcommand :: _ =>
    IO.eprintln s!"atlas-builder: unknown subcommand: {subcommand}"
    pure 2
