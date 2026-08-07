import Lake
open Lake DSL

package mercator

lean_lib Mercator

@[default_target]
lean_exe mercator where
  root := `Mercator.Cli.Main

/-- レシピ agentic-state-loop の別エントリポイント(R-8、共通コアを共有)。 -/
@[default_target]
lean_exe «asl-loop» where
  root := `Mercator.Cli.AslMain
