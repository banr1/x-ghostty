import Std.Time
import Mercator.Core.Time

/-!
`Mercator.Io.Clock` — 現在時刻取得の薄い IO シェル。

暦変換と整形は `Mercator.Core.Time` の純粋関数が行い、ここは epoch 秒の
取得と env 注入だけを持つ(§3.3-2 の注入原則)。`Std.Time` は Lean
toolchain 同梱であり、ゼロ依存(R-9)を破らない。
-/

namespace Mercator.Io.Clock

/-- 現在時刻の Unix epoch 秒。 -/
def epochSeconds : IO Int := do
  let ts ← Std.Time.Timestamp.now
  pure ts.toSecondsSinceUnixEpoch.val

/-- ローカル ISO タイムスタンプ。TZ オフセットは `envVar`(UTC 固定
オフセット方言、`Core.Time.parseTzOffset?`)から読み、不正・不在は
既定オフセットに倒す。 -/
def nowLocal (envVar : String) : IO String := do
  let offsetMinutes := (((← IO.getEnv envVar).getD "")
    |> Mercator.Core.Time.parseTzOffset?).getD
      Mercator.Core.Time.defaultOffsetMinutes
  pure (Mercator.Core.Time.isoTimestamp (← epochSeconds) offsetMinutes)

end Mercator.Io.Clock
