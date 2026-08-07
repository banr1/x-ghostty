import Mercator.Core.Json

/-!
`Mercator.Core.Stop` — stop-reason 優先順の唯一の定義箇所(D-005)。

シェル側は `mercator util stop-status` 経由で本モジュールを実体として使い、
state エンジンの emit 順もここに揃う。reasons は payload JSON の現行契約の
まま文字列リストで持つ(抽象語彙への持ち上げは証明層 `Proofs.Spec.Model`
の `StopReason` が担い、`canonical_matches_runtime` で本定義に接地する)。
-/

namespace Mercator.Core.Stop

/-- 停止理由の優先順(高い順)。state.py `should_stop_payload` が reasons を
append する順序と同一でなければならない(D-005)。 -/
def reasonPriority : List String := [
  "state_unreadable",
  "essence_missing",
  "essence_placeholder",
  "essence_structure",
  "essence_asset_integrity",
  "essence_unreviewed_change",
  "essence_blocking",
  "blocking_recommendation",
  "human_input_required",
  "must_complete_awaiting_phase_approval",
  "idle_cycles",
  "infra_unreachable"
]

/-- reasons のうち最優先のものを Run-Status として返す。未知の理由しか
含まない・空の場合は `"stopped"`(META.md §24.3 のフォールバック)。 -/
def runStatusFromReasons (reasons : List String) : String :=
  (reasonPriority.find? reasons.contains).getD "stopped"

/-- should-stop payload(JSON object)から Run-Status を決める。

Python 側(旧 `_lib.sh` インライン)の `payload.get("reasons", [])` に対応:
- `reasons` キー欠落 → 空リスト → `"stopped"`
- `reasons` が文字列の配列 → 優先探索(文字列でない要素は一致し得ないため無視)
- トップレベルが object でない・`reasons` が配列でない(null 含む)→ エラー。
  Python はここで TypeError 等により非ゼロ終了しており(fail-closed)、
  その扱いを明示的なエラーとして保存する。 -/
def runStatusFromJson : Json.Value → Except String String
  | .obj entries =>
    match (Json.Value.obj entries).get? "reasons" with
    | none => .ok (runStatusFromReasons [])
    | some (.arr items) =>
      .ok (runStatusFromReasons (items.filterMap Json.Value.asStr?))
    | some _ => .error "reasons must be an array"
  | _ => .error "should-stop payload must be a JSON object"

#guard runStatusFromReasons [] == "stopped"
#guard runStatusFromReasons ["some_future_reason"] == "stopped"
#guard runStatusFromReasons ["idle_cycles", "essence_blocking"] == "essence_blocking"
#guard runStatusFromReasons ["infra_unreachable", "idle_cycles"] == "idle_cycles"
-- 文書自身の形(§13.1-15)は、文書から essences/ への相互参照より先に成立する
#guard runStatusFromReasons ["essence_asset_integrity", "essence_structure"]
    == "essence_structure"
#guard runStatusFromReasons ["essence_structure", "essence_placeholder"]
    == "essence_placeholder"
#guard runStatusFromReasons reasonPriority.reverse == "state_unreadable"
#guard reasonPriority.all (fun r => runStatusFromReasons [r] == r)
#guard (runStatusFromJson (.obj [])).toOption == some "stopped"
#guard (runStatusFromJson (.obj [("reasons", .arr [.str "idle_cycles"])])).toOption
    == some "idle_cycles"
#guard (runStatusFromJson
    (.obj [("reasons", .arr [.num 1 0, .str "idle_cycles"])])).toOption
    == some "idle_cycles"
#guard (runStatusFromJson (.obj [("reasons", .null)])).isOk == false
#guard (runStatusFromJson (.arr [])).isOk == false

end Mercator.Core.Stop
