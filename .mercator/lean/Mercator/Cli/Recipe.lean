import Mercator.Io.Fs
import Mercator.Io.Env

/-!
`Mercator.Cli.Recipe` — `mercator recipe hash <name>` の IO シェル
(`recipes/recipe_hash.py` と、`state.py` 内の同名複製 = D-004 の置換先)。

canonical recipe-original hash の定義(META.md §29.4): recipe ディレクトリ
配下の全ファイルをパスセグメント列の辞書式順に並べ、
`相対パス<TAB>ファイル SHA-256` の行を LF で連結(末尾改行なし)した
UTF-8 バイト列の SHA-256。Python `sorted(recipe_dir.rglob("*"))` の並びは
Path の parts タプル比較であり(黒箱突合で実測: `a/b` < `a.b`、単純な
文字列比較とは異なる)、相対パスの `/` 分割セグメント列の辞書式比較が
それと一致する(全体ソートとファイルのみのソートはフィルタと可換)。

契約(recipe_hash.py と同一): 引数はレシピ名 1 個。成功は stdout 1 行の
64 桁 hex + exit 0、引数不正・未知レシピは stderr + exit 2。
-/

namespace Mercator.Cli.Recipe

open Mercator

private def usage : String := "usage: mercator recipe hash <recipe-name>"

private def runHash (name : String) : IO UInt32 := do
  let some controlRoot ← Io.Env.controlRoot?
    | do
      IO.eprintln "mercator: cannot determine CONTROL_ROOT from the binary location"
      pure 2
  let recipeDir := controlRoot / "recipes" / name
  if !(← recipeDir.isDir) then
    IO.eprintln s!"unknown recipe: {name}"
    return 2
  -- 読む(バイト列、§4.4 ByteArray 規約)→ 純粋にハッシュ → 出力の 3 手。
  -- 定義本体は Io.Fs.recipeSourceHash(state validate と共有 = D-004)
  IO.println (← Io.Fs.recipeSourceHash recipeDir)
  return 0

def run (args : List String) : IO UInt32 := do
  match args with
  | ["hash", name] => runHash name
  | _ =>
    IO.eprintln usage
    pure 2

end Mercator.Cli.Recipe
