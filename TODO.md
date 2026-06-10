# TODO — 階層的ペイン（グループレイヤー）実装

`SPEC.md` を実装するための作業リスト。
方針: ① `SplitTree` のジェネリック制約を一般化して両層で再利用、
② グループ用 action は Zig core (`src/input/Binding.zig`) まで完全統合、
③ Phase 0〜6 を順に実装する。

進捗を確認する正典は `SPEC.md`（特に §14 不変条件、§19 テスト計画）。

---

## Phase F: 基盤整備（Phase 1 の前提）✅ 完了

`SplitTree<GroupRef>` を成立させるための事前リファクタ。
ここが完了するまで Phase 1 以降には着手しない。

### F.1 SplitTree のジェネリック制約一般化 ✅

- [x] `SplitTree<ViewType: NSView & Codable & Identifiable>` の制約を
      `SplitTree<Element: Codable & Identifiable & Equatable>` へ緩める（`SplitTree.swift:5`）
      ※ 型パラメータも `ViewType` → `Element` へ改名
- [x] leaf 等価性を `===`（参照同一性）→ `==`（値等価）へ一般化
      （`SurfaceView` は `isEqual` 未 override のため挙動は完全同一）
- [x] `structuralIdentity` の `ObjectIdentifier(view)` / `view1 === view2` を
      `view.id` ベースへ（NSView は一意 UUID のため等価）
- [x] NSView 依存メソッドを `extension ... where Element: NSView` へ分離
  - [x] `SplitTree.viewBounds()` / `Node.viewBounds()`（`view.bounds.size` 依存）
  - [x] `valuesPublisher(...)`（KVO/Combine 依存）
  - 注: `calculateViewBounds(in:)` / `dimensions()` / `spatialSlots()` / `spatial(within:)`
    は NSView API を使わず**グループ層のナビゲーションに必須**のため、当初計画と異なり
    ジェネリックのまま残置（`TerminalWindow.swift:521` でも `spatial()` を利用中）
- [x] `spatial(within:)` は既に bounds 外部注入対応（引数 nil 時はグリッド次元で代替）
- [x] 既存 `SplitTree<Ghostty.SurfaceView>` 利用箇所が無改修で通ることを確認
      （`xcodebuild build` 成功 + 既存 `SplitTreeTests` 全パス）

### F.2 グループ層が必要とするヘルパーの汎用実装 ✅

要素非依存のプリミティブとして汎用 `SplitTree` extension に追加
（グループ固有ラッパーは Phase 4/5 の `WorkspaceModel` 側で id/predicate を渡して表現）。

- [x] `spatialNeighbor(from:direction:)`（`slots(in:from:)` を利用）
- [x] `lowestCommonSplitPath(between:and:matchingResizeDirection:)`
      （2 leaf の path の最長共通接頭辞 = LCA split、方向一致時のみ返す）
- [x] `adjustRatio(at:direction:amount:)`（amount は正規化比率デルタ。px→比率変換は呼び出し側）
- [x] `pruningLeaves(_ shouldPrune:)`（hidden 除外用、空 split は畳む、zoomed も整合）
- [x] `treeContainingOnly(_:)` / `subtreeContainingOnly(_:)`（zoom 用、単一 leaf 木を返す）
- [x] `nearestVisibleGroup(to:)` → 汎用 `nearestLeaf(to:matching:)` として実装
      （グループ層は canonical tree に対し `matching: { !hidden.contains($0.id) }` で呼ぶ想定）
- [x] `firstLeaf`
- [x] `Path.Component` に `Equatable` 追加（LCA 比較で必要）
- [x] 各ヘルパーの単体テスト（`SplitTreeTests` に F.2 セクション追加、値型 `MockRef` で実証）

### F.3 回帰確認 ✅

- [x] `zig build -Demit-macos-app=false` でビルド通過（exit 0）
- [x] `xcodebuild ... test`（macOS Swift ユニットテスト）全パス（`** TEST SUCCEEDED **`）
      ※ 既存 `SplitTreeTests`（insert/remove/focus/resize/equalize/structuralIdentity/
      viewBounds/spatial）が全パス = SplitTree 挙動の回帰なしを担保
- [x] `swiftlint --strict`（変更 2 ファイル）0 violations
- [ ] 実機での対話的 split 操作（Cmd+D 等）の目視回帰確認は未実施
      （自動テストで論理的回帰なしを担保済み。アプリ起動確認は Phase 1 着手時に併せて実施推奨）

---

## Phase 0: 既存挙動を 1 グループに包む（§15 Phase 0）✅ 完了

見た目・操作を変えず内部だけ二層化する。

### 0.1 データモデル（§5, ファイル構成 §16）✅

- [x] `Features/Groups/` を新設
- [x] `GroupID.swift`: `GroupID` / `SurfaceID` / `GroupRef` / `SurfaceRef`（§5.1）
- [x] `GroupState.swift`（§5.3: name, paneTree, focusedSurface, createdAt, lastFocusedAt）
      ※ `paneTree` は確定判断により `SplitTree<Ghostty.SurfaceView>` を維持（後述）
- [x] `WorkspaceState.swift`（§5.2: canonicalGroupTree, groups, hiddenGroupIDs,
      focusedGroup, zoomedGroup, version）+ `effectiveVisibleGroupTree`（§13）+ custom Codable
- [ ] `SurfaceRestoreSpec`（§5.4）は **Phase 6 へ先送り**
      （paneTree が `SurfaceView` を保持し既存 `SurfaceView` の Codable で復元できるため、
      現状は consumer ゼロの投機的型になる。restore 統合設計と併せて Phase 6 で導入）

### 0.2 二層化 ✅

- [x] `WorkspaceModel`（Phase 0 は `struct`）を新設し、`BaseTerminalController` の
      `surfaceTree` を `canonicalGroupTree = leaf(defaultGroup)` /
      `groups[defaultGroup].paneTree = surfaceTree` で包む（`init(wrapping:)`）
- [x] `effectiveVisibleGroupTree` 派生プロパティ（§13, `WorkspaceState` 側に実装）
- [x] 既存 Cmd+D / Cmd+Shift+D / goto_split / resize_split / toggle_split_zoom /
      close_surface が従来通り動く（**案A**: surfaceTree が source of truth のまま、
      `surfaceTreeDidChange` で focused group の paneTree をミラー同期。操作経路は無改修）

**成功条件（§15 Phase 0）**: 上記 6 操作すべてが従来通り
→ `SplitTreeTests` 169 件 + `TerminalRestorableTests` 6 件が全パス（回帰なし）、
新規 `WorkspaceStateTests` 7 件 / `WorkspaceModelTests` 6 件パス、
`swiftlint --strict` 0 violations、`zig build -Demit-macos-app=false` exit 0。

- [ ] 実機での 6 操作の目視回帰確認は未実施（操作経路は無改修・追加ミラーのみのため論理回帰なしを
      自動テストで担保。アプリ起動確認は Phase 1 着手時に併せて実施推奨）

### Phase 0 実装メモ（レビュー観点）

- **採用設計（案A: surfaceTree が source of truth）**: `surfaceTree`（30+ 箇所が依存・
  `$surfaceTree` publisher・restore・undo が絡む）を一切再解釈せず stored `@Published` のまま残し、
  `WorkspaceModel` は focused group の paneTree を**ミラー**する。同期は `surfaceTreeDidChange`
  （paneTree）と `focusedSurface.didSet`（focus）に一本化。Combine/描画/restore/undo は無改修。
- **SPEC §5.3 からの逸脱**: `GroupState.paneTree` を `SplitTree<SurfaceRef>` ではなく
  `SplitTree<Ghostty.SurfaceView>` に。SurfaceID は `view.id`(UUID) で表現。理由は既存の
  描画/action/restore/drag&drop が全て `SplitTree<Ghostty.SurfaceView>` 依存で、SurfaceRef+registry
  移行が Phase 0 の非破壊要件と衝突するため（ユーザー合意済み）。
- **WorkspaceState の Codable**: runtime-only の `hiddenGroupIDs`/`zoomedGroup` は非永続・decode 時
  クリア。`groups` は非 String キー dictionary が JSON 配列化するのを避けるため `uuidString` キーの
  object へ手動変換。
- **WorkspaceModel は struct**: Phase 0 では描画に使わないため `ObservableObject` 化しない。

### Phase 2 への申し送り（Phase 1 で未着手のまま意図的に先送り）

- [x] `WorkspaceModel` を `ObservableObject`（class）へ昇格（Phase 2.3 で実施。
      `@Published private(set) var state` + `TerminalWorkspaceView` を `@ObservedObject` 化）
- [x] group 切替は「旧 surfaceTree を groups へ保存 → focusedGroup 更新 → 新 group paneTree を
      surfaceTree へ差替」を**専用メソッド1箇所**に閉じる（`WorkspaceModel.openNewGroup` に集約。
      Phase 2.3 で実施。zoom 解除も同メソッド内で先行実施）
- [ ] inactive group の paneTree は surfaceTree とミラーされない（focused のみ）点に留意

---

## Phase 1: GroupSplitTreeView（§6, §15 Phase 1）✅ 完了

- [x] `TerminalWorkspaceView.swift`（§6.2: ZStack で GroupSplitTree + HiddenShelf overlay）
      ※ HiddenShelf は Phase 5 のためコメントプレースホルダ（hidden は常に空）
- [x] `GroupSplitTreeView.swift`（`SplitTree<GroupRef>` を描画）+ `GroupSplitOperation`（group resize は Phase 4 まで no-op）
- [x] `GroupView.swift`（§6.3: TerminalSplitTreeView + GroupLabel overlay）
      ※ ラベルは最小実装・複数 group 時のみ表示（単一 group はピクセル同等）。本実装は Phase 3
- [x] SwiftUI structural identity を `.id(node.structuralIdentity)` で担保（§4.3）
      （Phase F の値型一般化により `SplitTree<GroupRef>` でもそのまま機能）
- [x] ライブ描画パスを切替: `TerminalView` が `viewModel.surfaceTree` 直結 →
      `TerminalWorkspaceView(workspace:)` 経由に変更（focus/drag/palette 修飾子は据え置き）
- [x] `TerminalViewModel` プロトコルに `workspace` アクセサ追加

**成功条件（§15 Phase 1）**: 1 group で既存同等表示 / 2 group で各 paneTree 独立表示 /
identity 破綻なし
→ `zig build -Demit-macos-app=false` exit 0、`GhosttyTests` 288 件全パス（回帰なし、
`SplitTree`/`WorkspaceState`/`WorkspaceModel` 101 件含む）、`swiftlint --strict` 0 violations。
2 group 独立性はデータ層（`WorkspaceStateTests.phase0InvariantsHoldForTwoGroupState` /
`effectiveVisibleGroupTree*`）で担保。

- [ ] 実機での 1/2 group 目視確認は未実施（単一 group は描画経路がピクセル同等・
      自動テストで論理回帰なしを担保。複数 group の対話的作成は Phase 2 で初めて可能なため、
      アプリ起動確認は Phase 2 着手時に併せて実施推奨）

### Phase 1 実装メモ（レビュー観点）

- **採用設計（ライブ描画切替・surfaceTree が source of truth のまま）**: `TerminalView` の描画を
  `TerminalWorkspaceView → GroupSplitTreeView → GroupView → TerminalSplitTreeView` に差替。
  単一 group では focused group の `paneTree` が `surfaceTree` のミラーなので**挙動・見た目とも不変**。
  「描画プラミング切替」を Phase 1 に隔離し、Phase 2 を group 作成ロジックに専念させてレビューしやすくする狙い。
- **`WorkspaceModel` は struct のまま値渡し（ObservableObject 昇格を Phase 2 へ先送り）**: Phase 1 では
  描画に影響する全変更が `@Published surfaceTree` 変更を経由する（mirror は `surfaceTreeDidChange` 内で同期更新）。
  よって controller を `@ObservedObject` するだけで再描画が成立し、ObservableObject 化は不要。
  `focusedGroup` 変更だけで再描画が必要になる Phase 2 で昇格する。
- **ラベルは最小・条件付き表示**: `GroupView` のラベルは `groups.count > 1` のときのみ描画（§7.1 の
  focused=1.0 / unfocused=0.4 のみ）。単一 group は従来表示とピクセル同等を保つ。click/double-click と
  本格スタイルは Phase 3（`GroupLabel.swift`）。
- **group resize は未配線**: `GroupSplitTreeView` の `groupAction` は `nil`（divider ドラッグは no-op）。
  `resize_group` は Phase 4。
- **structuralIdentity の二段適用**: group 木は `GroupSplitTreeView` 側で `.id(group node)`、
  pane 木は `GroupView` 内の `TerminalSplitTreeView` 側で `.id(pane node)` を別レベルで適用。
  focused group の paneTree 変化時も group leaf の identity は安定 → GroupView は再生成されず内部 pane のみ更新。

---

## Phase 2: new_group_split（§9, §11.1, §15 Phase 2）

### 2.1 Zig core 統合（ギャップ3 対応）✅ 完了（コア語彙のみ）

グループ action の語彙を Zig core → apprt → C API まで一括追加。Swift 層は
`Ghostty.App.action()` の `default:` が吸収するため、この時点ではキーバインドとして
**認識・パース可能だが Swift 層では no-op**（挙動配線は 2.3）。

- [x] `src/input/Binding.zig` の Action union に group action 10 種を追加
  - [x] `new_group_split: SplitDirection`
  - [x] `goto_group: SplitFocusDirection`
  - [x] `resize_group: SplitResizeParameter`
  - [x] `equalize_groups` / `toggle_group_zoom` / `hide_group`
  - [x] `show_group: []const u8` / `rename_group` / `set_group_title: []const u8`
  - [x] `close_group`
- [x] `Action.scope()` の `.surface` 群に 10 種を登録（網羅 switch）
- [x] keybind パーサのテスト追加（`Binding.zig` "parse: group split actions"、
      enum/tuple/void/string を既存 split test に倣って実証）
- [x] `command.zig` の網羅 switch に追加（コマンドパレット登録は挙動実装フェーズへ
      先送り＝no-op コマンド露出回避のため空 `&.{}`）
- [x] `Surface.zig` performBindingAction に apprt ディスパッチ追加
      （`new_split`/`goto_split`/`resize_split` の変換を踏襲、文字列は `dupeZ`）
- [x] `apprt/action.zig` の Action union + Key enum 末尾に追加（ABI 互換、引数型は
      `SplitDirection`/`GotoSplit`/`ResizeSplit`/`SetTitle` を再利用）
- [x] `include/ghostty.h` の手書き enum/union を同期（`checkGhosttyHEnum` テスト通過）
- [x] `apprt/gtk/.../application.zig` の Unimplemented リストに追加（macOS では非
      コンパイルだがクロスプラットフォーム整合のため）
- [ ] apprt action → Swift `WorkspaceModel` のプラミング（`Ghostty.App.action()` の
      case 追加 → notification → `BaseTerminalController` ハンドラ）は **2.3 へ**

### 2.2 GroupNameGenerator（§8）✅ 完了

- [x] `GroupNameGenerator.swift`（adjective-noun, 既存名衝突回避, 作成時のみ生成）
  - RNG 注入シーム（`make(existing:using:)`）でテストを決定論化、本番は
    `SystemRandomNumberGenerator`
  - フォールバックは SPEC §8 の `group-N` を**衝突回避まで上方探索**するよう堅牢化
  - [x] 単体テスト 4 件（format / 累積一意性 / 全組合せ枯渇時フォールバック / 番号上方探索）
- [ ] `WorkspaceModel` への配線（新 group 作成時の名前採番）は 2.3 で実施

### 2.3 new_group_split 実装（§11.1, エッジ §18.4）✅ 完了

Swift 側の挙動。`WorkspaceModel` のアーキテクチャ変更を伴うため独立フェーズとして分離。

- [x] `WorkspaceModel` を `ObservableObject`（class）へ昇格（`@Published private(set) var state`）
- [x] apprt action → Swift プラミング（`Ghostty.App.action()` に `GHOSTTY_ACTION_NEW_GROUP_SPLIT`
      の case 追加 → `ghosttyNewGroupSplit` notification → `BaseTerminalController` ハンドラ）
- [x] focusedGroup 基準で新 GroupState 作成（名前は `GroupNameGenerator.make(existing:)`）→
      初期 pane 1 つ（新 `SurfaceView`）→ canonicalGroupTree へ隣接挿入
- [x] group 切替を専用メソッド1箇所に閉じる（`WorkspaceModel.openNewGroup`: 旧 surfaceTree 保存 →
      canonical 挿入 → focusedGroup 更新。throw 時はローカルコピーで no-op）
- [x] zoom 中は zoom 解除してから隣に作成し（`openNewGroup` 内で `zoomedGroup = nil` 先行）、
      新 group の初期 pane へ focus
- [x] デフォルト keybind: Cmd+Opt+D / Cmd+Opt+Shift+D（§10.2, §17, `src/config/Config.zig` macOS 既定）

**成功条件**: 新 group がランダム名で作成 / 初期 pane 1 つ / focus 移動 /
Cmd+D は新 group 内のみ分割。
→ `zig build -Demit-macos-app=false` exit 0、`GhosttyTests` 全パス（`WorkspaceModelTests` に
`openNewGroup` 3 件追加: 兄弟挿入+focus 切替 / canonical·groups 整合 / focusedGroup 無時 throw）、
`swiftlint --strict` 0 violations、`zig build test`（"group split" パーサ / "ghostty.h" 同期）パス、
`zig fmt --check` exit 0。Cmd+D が「focused group 内のみ分割」（不変条件 §14.9）はデータ層で担保。

- [ ] 実機での 2 group 作成・focus 移動・各 group 独立分割の目視確認は未実施
      （ロジックは自動テストで担保。Phase 3 のラベル目視と併せて実施推奨）

### Phase 2.3 実装メモ（レビュー観点）

- **採用設計（surfaceTree が source of truth のまま class 化）**: `WorkspaceModel` を
  `ObservableObject` 化し `TerminalWorkspaceView` を `@ObservedObject` に。これにより
  「focusedGroup 変更が `surfaceTree` 変更を伴わず再描画を要する」将来の操作（Phase 3 rename 等）に
  備える。Phase 2.3 自体は new_group_split が `surfaceTree` を差替えるため struct でも描画は成立するが、
  計画通り本フェーズで昇格して以後を簡潔化。
- **group 切替の単一化と順序**: `openNewGroup` 1 メソッドに集約。
  ① zoom 解除 → ② 旧 focused group へ現 surfaceTree を保存 → ③ canonical へ隣接挿入 →
  ④ focusedGroup を新 group へ。全てローカル `var next = state` に対して行い、`inserting` の throw 時は
  `state` 無変更（原子性）。`focusedGroup` を先に新 group へ移してから controller 側で
  `surfaceTree = newPaneTree` するため、続く `surfaceTreeDidChange` のミラーは新 group への no-op。
- **group 操作の undo は意図的に未実装（要申し送り）**: 既存 `replaceSurfaceTree` の undo は
  `surfaceTree` のみ復元するため、focusedGroup 切替後に再生すると旧 pane tree を**新 group へ**
  誤ミラーして層を破壊する。よって new_group_split は `replaceSurfaceTree` を使わず `surfaceTree` を
  直接差替え（undo 非登録）。group 層を含む undo は独立設計が必要なため横断タスクへ（下記）。
- **direction 変換**: 通知ハンドラが C enum `ghostty_action_split_direction_e` を
  `SplitTree<GroupRef>.NewDirection` へ変換（`ghosttyDidNewSplit` を踏襲、`auto` は既存同様 no-op）。
  既定 keybind は right/down のみ割当。
- **既知の制約（focused group のみ surfaceTree に乗る）**: new_group_split 後、`surfaceTree` は新
  group の pane のみを保持する。両 group の描画は各 `group.paneTree`（workspace.state）から行われ
  維持されるが、controller が `surfaceTree` を走査する処理（occlusion / color scheme / bell 集約 /
  flagsChanged / focus sync）は **focused group の surface にしか及ばない**。非 focused group の
  surface は process 生存・描画は継続するが、これらの window 横断同期からは外れる。Phase 0 の
  「focused のみミラー」設計の帰結で、group 間移動が常用化する Phase 4（goto_group）で
  controller の surface 走査を「全 group の全 surface」へ広げる際に併せて解消する想定。

### Phase 2.1 実装メモ（レビュー観点）

- **語彙レイヤーのみ（Phase F 同様の基盤）**: Zig core の Action union に group action を
  足すと `scope()` / `command.zig` / `Surface.zig`（surface-scoped 網羅 switch）/
  `apprt/action.zig` / `ghostty.h`（手書き・`checkGhosttyHEnum` で同期検証）/ GTK switch が
  芋づる式にコンパイル要求される。一方 Swift `Ghostty.App.action()` は `default:` を持つため、
  ここで止めればビルドは緑のまま。挙動配線（2.3）と分離してレビューしやすくする狙い。
- **引数型は既存 apprt 型を再利用**: `new_group_split`→`SplitDirection`、`goto_group`→
  `GotoSplit`、`resize_group`→`ResizeSplit`、`show_group`/`set_group_title`→`SetTitle`。
  新規 C enum を増やさず、`CValue` サイズ assert も不変。
- **コマンドパレット非登録 / キーバインド未配線**: 挙動が無い段階で no-op コマンドや
  「bind されるが何もしない」キーを露出しないよう、`command.zig` は空コマンド、既定 keybind も
  2.3 まで保留。config に明示すればパース・bind は可能だが Swift 層で no-op。

**検証**: `zig build -Demit-macos-app=false` exit 0、`zig build test`（"group split"
パーサ / "ghostty.h Action.Key" 同期）パス、`swiftlint --strict` 0 violations、
`xcodebuild test`（`GroupNameGeneratorTests` 4 件 + 既存 `WorkspaceModel`/`WorkspaceState`
テスト全パス、回帰なし）、`zig fmt --check` exit 0。

---

## Phase 3: label / rename（§7.1, §15 Phase 3）

- [ ] `GroupLabel.swift`（左上 overlay, focused は opacity 1.0・強調 /
      unfocused は opacity 0.35〜0.5）
- [ ] single click でその group に focus
- [ ] double click で inline rename
- [ ] `rename_group`（prompt）/ `set_group_title:<name>` action
- [ ] Cmd+Opt+R = rename_group（§10.5）

**成功条件**: label が terminal layout を押し下げない（overlay）/ rename 保存 /
復元後も名前が残る。

---

## Phase 4: goto_group / resize_group / equalize_groups（§11.3–§11.5, §15 Phase 4）

- [ ] `goto_group`（§11.3）: effectiveVisibleGroupTree で方向/next/prev 移動、
      移動先の last focused pane へ復元、hidden は対象外、zoom 中 no-op
- [ ] `resize_group`（§11.4）: visible で隣接探索 → canonical の LCA split ratio を変更
- [ ] `equalize_groups`（§11.5, 推奨案）: visible group に対応する canonical split ratio のみ均等化
  - [ ] 難しければ暫定: hidden が空のときのみ実行、ある場合は no-op + warning（log）
- [ ] デフォルト keybind: Cmd+Ctrl+Opt+方向 / Cmd+Ctrl+Opt+Shift+方向（§10.3, §10.4）

**成功条件**: 方向移動 / last focused pane 復帰 / group 境界 resize / equalize 動作。

---

## Phase 5: zoom / hide / shelf（§11.6–§11.8, §7.2, §15 Phase 5）

- [ ] `toggle_group_zoom`（§11.6）: トグル、描画は外→内（group zoom → 内部 split zoom）
- [ ] Cmd+Opt+Enter = toggle_group_zoom（§10.5, 既存 split zoom と非衝突）
- [ ] zoom 中 Cmd+D は group 内 split / new_group_split は zoom 解除して隣作成（§11.1, §18.4）
- [ ] `hide_group`（§11.7）: hiddenGroupIDs 追加、process は生存、canonical/groups 不変、
      focus は visible neighbor へ、**最後の visible group は hide 拒否**（§18.2）
- [ ] zoomed group の hide は zoom 解除後に hide（§18.3）
- [ ] `show_group`（§11.8）: hidden から除外、zoom 解除、focus 移動、last pane 復元
- [ ] `HiddenGroupShelf.swift`（§7.2）: 右上 overlay、0 個非表示 / 1〜4 個 pill /
      5 個以上は `[+N]` メニュー、pill click で即 show
- [ ] Cmd+Opt+H = hide_group（§10.5）

**成功条件**: group 単位 zoom / zoom 中 Cmd+D は内部 split / hide は kill しない /
shelf 表示 / pill click で即復帰。

---

## Phase 6: restore（§12, §15 Phase 6）

- [ ] 保存: canonicalGroupTree / groups / names / paneTree / focusedGroup /
      group ごとの focusedSurface（§12.1）
- [ ] 非保存: hiddenGroupIDs / zoomedGroup（§12.2）
- [ ] `restoreWorkspace`（§12.3）: 全 group visible・非 zoom で復元、
      focusedGroup が無効なら firstLeaf へフォールバック
- [ ] 起動時 pane は新規 shell（live process/scrollback/PTY は復元しない）
- [ ] 既存 `TerminalRestorable` 系との整合

**成功条件**: layout / names / pane layout 復元 / hidden は全 visible / zoom は非 zoom。

---

## 横断: close_group / Cmd+W（§11.9, §11.10, §18.5）

- [ ] `CloseGroupConfirmation.swift`（§11.9: Cancel / Close Group のみ、Hide Instead なし）
- [ ] `close_group`: 全 surface close → canonicalGroupTree/groups/hidden から削除 →
      zoom 対象なら解除 → nearest visible group へ focus
- [ ] 最後の pane で Cmd+W は close_group confirmation に昇格（§11.10, 不変条件 18）
- [ ] 最後の group の close は tab/window close に委譲（§18.5）

## 横断: group 操作の undo（Phase 2.3 申し送り）

- [ ] group 層を含む undo/redo の設計と実装。現状 `new_group_split` は undo 非登録
      （既存 `replaceSurfaceTree` の surfaceTree-only undo は focusedGroup 切替後に旧 tree を
      新 group へ誤ミラーするため流用不可）。`WorkspaceState` + `surfaceTree` のスナップショットを
      まとめて復元する group-aware undo を別途用意し、new_group_split / close_group / hide·show /
      group resize へ横断適用する。

---

## テスト（§14 不変条件 / §19）

- [ ] Unit（§19.1）: 名前一意性 / hide·show が canonical 不変 / close が canonical·groups 変更 /
      focusedGroup·zoomedGroup が hidden を指さない / restore で hidden·zoom クリア /
      new_group_split が group+初期 pane / Cmd+D は focused group のみ / goto_group が focusedSurface 復元
- [ ] Layout（§19.2）: split right/down / nested / hide middle / show / resize with hidden /
      equalize with·without hidden / zoom group + inner split zoom
- [ ] UI（§19.3）: 全 group に label / focused 強調 / unfocused 薄 / double-click rename /
      shelf は hidden 時のみ / pill click 即 show / close ダイアログは 2 ボタン
- [ ] 不変条件 §14 の 1〜18 を網羅するテストを用意
