import Lake
open Lake DSL

package «atlas-builder»

lean_lib AtlasBuilder

@[default_target]
lean_exe «atlas-builder» where
  root := `AtlasBuilder.Cli.Main

/-- レシピ agentic-state-loop の別エントリポイント(R-8、共通コアを共有)。 -/
@[default_target]
lean_exe «asl-loop» where
  root := `AtlasBuilder.Cli.AslMain
