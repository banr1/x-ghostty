import Mercator

/-!
マルチコールバイナリ `mercator` のエントリポイント。サブコマンドをディスパッチする
IO シェルであり、判定ロジック自体は `Mercator.Core` / `Mercator.Hook` 側の
純粋定義に委譲する。
-/

def usage : String :=
  "usage: mercator <subcommand>\nimplemented subcommands: version, hook stop, hook session-start, hook pre-compact, hook pre-tool, hook post-tool, recipe hash, trust status, trust ensure, state ensure, state validate, state should-stop, state should-complete, state should-reset, state record-progress, state raise-loop-gates, state start-run, state end-run, state reset-context, state resume, state status, util json-get, util stop-status, util token, util file-age-exceeds, util read-only-settings, util relpath, util render, util seed, util project-index, util json-check, util dangling-run, util settings-doctor, util essence-profile, util static-config"

def main (args : List String) : IO UInt32 := do
  match args with
  | ["version"] =>
    IO.println s!"mercator {Mercator.Core.versionString}"
    pure 0
  | ["hook", "stop"] =>
    Mercator.Cli.Hook.runStop
  | ["hook", "session-start"] =>
    Mercator.Cli.Hook.runSessionStart
  | ["hook", "pre-compact"] =>
    Mercator.Cli.Hook.runPreCompact
  | ["hook", "pre-tool"] =>
    Mercator.Cli.Hook.runPreTool
  | ["hook", "post-tool"] =>
    Mercator.Cli.Hook.runPostTool
  | "recipe" :: rest =>
    Mercator.Cli.Recipe.run rest
  | "trust" :: rest =>
    Mercator.Cli.Trust.run rest
  | "state" :: rest =>
    Mercator.Cli.State.run rest
  | "util" :: rest =>
    Mercator.Cli.Util.run rest
  | "hook" :: rest =>
    -- 未知の hook イベントは配線ミス(運用者エラー)なので、hooks の
    -- fail-open 契約(常に exit 0)ではなく、他の未知サブコマンドと同じく
    -- exit 2 で大きく落とす。
    let event := String.intercalate " " rest
    IO.eprintln s!"mercator: unknown hook event: {event}"
    pure 2
  | [] =>
    IO.eprintln usage
    pure 2
  | subcommand :: _ =>
    IO.eprintln s!"mercator: unknown subcommand: {subcommand}"
    pure 2
