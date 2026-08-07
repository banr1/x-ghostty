import Lake
open Lake DSL

/-!
agentic-state-loop の同梱エンジン(ゼロ依存の Lean 4 パッケージ)。

`Mercator/` 配下は Mercator runtime パッケージの共通判定コアの忠実複製
(バイト同一の vendored subset)であり、この instance では `asl-loop`
マルチコールバイナリ(state エンジン + hooks)だけをビルドする。

ビルド: このディレクトリで `lake build` し、成果物
`.lake/build/bin/asl-loop` を `../bin/asl-loop` へ配置する(justfile の
build レシピが行う)。ネットワークは elan のツールチェーン取得
(lean-toolchain 固定)以外不要。
-/

package «asl-loop»

lean_lib Mercator

@[default_target]
lean_exe «asl-loop» where
  root := `Mercator.Cli.AslMain
