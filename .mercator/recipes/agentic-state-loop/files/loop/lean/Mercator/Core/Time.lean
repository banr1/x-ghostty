import Mercator.Core.Prim

/-!
`Mercator.Core.Time` — 表示用タイムスタンプの純粋コア(META.md §8.4)。

ゼロ依存の Lean 実行層は tzdata を持たない(LEAN_MIGRATION_PLAN.md §4.4)ため、
時刻は「Unix epoch 秒 + 固定オフセット」で扱う。epoch 秒の取得だけが IO
(`Mercator.Io.Clock`)で、暦変換(proleptic Gregorian)と ISO 8601 整形は
本モジュールの純粋関数が行う。タイムスタンプは表示専用であり判定には使われない。

`MERCATOR_TZ` はオフセット方言(`+HH:MM` / `-HH:MM` / `Z` / `UTC`)を受理する
(META.md §8.4-2 の仕様変更)。旧 IANA 名(`Asia/Tokyo` 等)は解釈できず、
不正な名前の場合の Python 版と同じく既定の +09:00 へフォールバックする。
-/

namespace Mercator.Core.Time

/-- 既定の表示オフセット: JST(+09:00)= 540 分(META.md §8.4-1)。 -/
def defaultOffsetMinutes : Int := 540

private def digit? (c : Char) : Option Nat :=
  if '0' ≤ c && c ≤ '9' then some (c.toNat - '0'.toNat) else none

/-- `MERCATOR_TZ` のオフセット方言: `+HH:MM` / `-HH:MM`(HH ≤ 23、MM ≤ 59)、
`Z` / `UTC`(= +00:00)。それ以外(旧 IANA 名・空文字列含む)は none。 -/
def parseTzOffset? (raw : String) : Option Int := do
  let s := raw.trimAscii.toString
  if s == "Z" || s == "UTC" then
    some 0
  else
    match s.toList with
    | [sign, h1, h2, ':', m1, m2] =>
      let sgn : Int ← match sign with
        | '+' => some 1
        | '-' => some (-1)
        | _ => none
      let hh := (← digit? h1) * 10 + (← digit? h2)
      let mm := (← digit? m1) * 10 + (← digit? m2)
      if hh ≤ 23 && mm ≤ 59 then some (sgn * Int.ofNat (hh * 60 + mm)) else none
    | _ => none

/-- Unix epoch からの日数 → (年, 月, 日)。proleptic Gregorian
(Howard Hinnant の civil_from_days)。 -/
def civilFromDays (days : Int) : Int × Nat × Nat :=
  let z := days + 719468
  let era := z.ediv 146097
  let doe := (z.emod 146097).toNat
  let yoe := (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  let doy := doe - (365 * yoe + yoe / 4 - yoe / 100)
  let mp := (5 * doy + 2) / 153
  let d := doy - (153 * mp + 2) / 5 + 1
  let m := if mp < 10 then mp + 3 else mp - 9
  (Int.ofNat yoe + era * 400 + (if m ≤ 2 then 1 else 0), m, d)

private def pad2 (n : Nat) : String := Prim.padLeftZeros (toString n) 2

/-- epoch 秒 + 表示オフセット(分)→ ISO 8601(秒精度・オフセット付き)。
Python の `datetime.now(tz).isoformat(timespec="seconds")` に対応する。 -/
def isoTimestamp (epochSeconds : Int) (offsetMinutes : Int) : String :=
  let localSecs := epochSeconds + offsetMinutes * 60
  let (y, m, d) := civilFromDays (localSecs.ediv 86400)
  let sod := (localSecs.emod 86400).toNat
  let sign := if offsetMinutes < 0 then "-" else "+"
  s!"{Prim.padLeftZeros (toString y) 4}-{pad2 m}-{pad2 d}T{pad2 (sod / 3600)}:{pad2 (sod / 60 % 60)}:{pad2 (sod % 60)}{sign}{pad2 (offsetMinutes.natAbs / 60)}:{pad2 (offsetMinutes.natAbs % 60)}"

/-- Python `datetime.now(tz).strftime("%Y%m%dT%H%M%S%z")`: 区切りなしの
コンパクト形(`%z` はコロンなしオフセット)。run_id / loop-gate id の
スタンプが使う(META.md §8.4-4)。 -/
def compactTimestamp (epochSeconds : Int) (offsetMinutes : Int) : String :=
  let localSecs := epochSeconds + offsetMinutes * 60
  let (y, m, d) := civilFromDays (localSecs.ediv 86400)
  let sod := (localSecs.emod 86400).toNat
  let sign := if offsetMinutes < 0 then "-" else "+"
  s!"{Prim.padLeftZeros (toString y) 4}{pad2 m}{pad2 d}T{pad2 (sod / 3600)}{pad2 (sod / 60 % 60)}{pad2 (sod % 60)}{sign}{pad2 (offsetMinutes.natAbs / 60)}{pad2 (offsetMinutes.natAbs % 60)}"

/-! ## コンパイル時テスト -/

#guard compactTimestamp 0 540 == "19700101T090000+0900"
#guard compactTimestamp 1767225600 0 == "20260101T000000+0000"
#guard compactTimestamp 0 (-330) == "19691231T183000-0530"

#guard isoTimestamp 0 0 == "1970-01-01T00:00:00+00:00"
#guard isoTimestamp 0 540 == "1970-01-01T09:00:00+09:00"
#guard isoTimestamp 86399 0 == "1970-01-01T23:59:59+00:00"
-- 2024-02-29(閏年)と 2026-01-01(平年跨ぎ)の既知 epoch
#guard isoTimestamp 1709164800 0 == "2024-02-29T00:00:00+00:00"
#guard isoTimestamp 1767225600 0 == "2026-01-01T00:00:00+00:00"
-- 負オフセットは日付を跨いで戻る
#guard isoTimestamp 1767225600 (-330) == "2025-12-31T18:30:00-05:30"
#guard parseTzOffset? "+09:00" == some 540
#guard parseTzOffset? "-05:30" == some (-330)
#guard parseTzOffset? "Z" == some 0
#guard parseTzOffset? " UTC " == some 0
#guard parseTzOffset? "+00:15" == some 15
#guard parseTzOffset? "Asia/Tokyo" == none
#guard parseTzOffset? "+24:00" == none
#guard parseTzOffset? "+9:00" == none
#guard parseTzOffset? "" == none

end Mercator.Core.Time
