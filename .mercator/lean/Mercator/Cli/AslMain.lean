import Mercator.Core.Version
import Mercator.Cli.Asl
import Mercator.Cli.AslHook
import Mercator.Cli.AslUtil
import Mercator.Cli.Trust

/-!
レシピ agentic-state-loop のマルチコールバイナリ `asl-loop` のエントリ
ポイント(LEAN_MIGRATION_PLAN.md §3.2 の「共通コアをパラメータ化した
別エントリポイント」)。live 版 `mercator` と同一パッケージからビルドされ、
共通判定コア(Core / Asl)を共有する(R-8)。

サブコマンドは `version`・`state`(vendored `files/loop/scripts/state.py`
の置換先)・`hook`(vendored `files/claude/hooks/*.py` の置換先: pre-tool /
post-tool / session-start)・`util`(`_lib.sh` / `loop.sh` のインライン
Python の置換先)・`trust`(`_lib.sh` の `require_claude_trust` の判定核。
live `mercator trust` と単一定義を共有)。
-/

def usage : String :=
  "usage: asl-loop <subcommand>\nimplemented subcommands: version, state <ensure|validate|raise-gate|should-stop|start-run|end-run|record-progress|resume|status|write-doc|append-log>, hook <pre-tool|post-tool|session-start>, util <stop-message|max-session-cycles|protected-match>, trust <status|ensure>"

def main (args : List String) : IO UInt32 := do
  match args with
  | ["version"] =>
    IO.println s!"asl-loop {Mercator.Core.versionString}"
    pure 0
  | "state" :: rest =>
    Mercator.Cli.Asl.run rest
  | "hook" :: rest =>
    Mercator.Cli.AslHook.run rest
  | "util" :: rest =>
    Mercator.Cli.AslUtil.run rest
  | "trust" :: rest =>
    Mercator.Cli.Trust.run rest (prog := "asl-loop")
  | [] =>
    IO.eprintln usage
    pure 2
  | subcommand :: _ =>
    IO.eprintln s!"asl-loop: unknown subcommand: {subcommand}"
    pure 2
