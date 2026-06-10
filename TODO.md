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

## Phase 3: label / rename（§7.1, §15 Phase 3）✅ 完了

- [x] `GroupLabel.swift`（左上 overlay, focused は opacity 1.0・強調〔regularMaterial +
      accent border〕/ unfocused は opacity 0.4・thinMaterial）
- [x] single click でその group に focus（`focusGroup` delegate → `WorkspaceModel.switchFocusedGroup`
      → surfaceTree 差替 + last focused pane へキーボード focus 移動）
- [x] double click で inline rename（`GroupLabel` の TextField。Return/blur で commit、
      Escape で cancel〔draft を title へ戻してから blur-commit を無害化〕）
- [x] `rename_group`（focused group を inline rename モードへ）/ `set_group_title:<name>`
      （focused group 名を直接設定）action の Swift プラミング
      （`Ghostty.App.action()` に case 追加 → `ghosttyRenameGroup`/`ghosttySetGroupTitle`
      notification → `BaseTerminalController` ハンドラ → `WorkspaceModel`）
- [x] Cmd+Opt+R = rename_group（§10.5, `src/config/Config.zig` macOS 既定）
- [x] ラベル常時表示へ変更（ユーザー合意。SPEC §6.3/§7.1 準拠で各 group に必ず表示。
      Phase 1 の `groups.count > 1` ゲートを撤去）

**成功条件**: label が terminal layout を押し下げない（overlay）/ rename 保存 /
復元後も名前が残る。
→ `zig build -Demit-macos-app=false` exit 0、`zig build test`（"group split" / "ghostty.h" /
"rename_group" パーサ）パス、`zig fmt --check` exit 0、`swiftlint --strict`（変更 10 ファイル）
0 violations、`xcodebuild test`（`WorkspaceModelTests` に switchFocusedGroup 3 件 + rename 7 件追加で
全パス、`SplitTreeTests`/`TerminalRestorableTests` 回帰なし `** TEST SUCCEEDED **`）。
overlay 不変条件（§14.13）は `GroupView` の ZStack 構造で担保。name の永続は `GroupState.name`
（既存 Codable）+ `WorkspaceState.encode` で保存済み（restore 統合は Phase 6）。

- [ ] 実機での目視確認（ラベル focused/unfocused 表示・single-click focus 切替・
      double-click/Cmd+Opt+R rename・set_group_title）は未実施
      （ロジックは自動テストで担保。Phase 4 の goto_group 目視と併せて実施推奨）

### Phase 3 実装メモ（レビュー観点）

- **single-click focus は group 切替機構を新設し Phase 4 と共有**: `WorkspaceModel.switchFocusedGroup`
  は `openNewGroup` から「新 group 作成・canonical 挿入」を除いた focus 切替のみ版
  （① outgoing focused group へ現 surfaceTree 保存 → ② focusedGroup 差替 → ③ 対象の
  focusedSurface を返す）。controller 側 `focusGroup` が `surfaceTree = focusedPaneTree` で
  差替え、続く `surfaceTreeDidChange` のミラーは新 focused group への no-op。返った
  focusedSurface（無ければ firstLeaf）へ `Ghostty.moveFocus`。Phase 4 goto_group はこの
  機構の上に方向/next/prev 解決を載せる。
- **rename は inline edit に一本化（modal prompt 不採用）**: `rename_group` action と double-click は
  どちらも `WorkspaceModel.renamingGroup`（`@Published`・transient・非永続）を立てて同じ
  `GroupLabel` の TextField を編集モードにする。`set_group_title:<name>` のみ非対話で直接設定。
  rename の commit/cancel/trim/空名拒否は `WorkspaceModel.renameGroup` に集約しテスト可能化。
- **Escape と blur の競合回避**: TextField は Return と blur で commit、Escape で cancel。Escape は
  draft を現在の title へ戻してから cancel するため、直後の teardown で発火する blur-commit は
  「title→title」の no-op（`renameGroup` の `name != trimmed` ガードで弾かれる）。これにより
  「Escape したのに blur が draft を保存してしまう」事故を防ぐ。
- **action プラミングは既存 apprt 型を再利用**: `rename_group` は void、`set_group_title` は
  既存 `ghostty_action_set_title_s`。Phase 2.1 で Zig core 語彙は整備済みのため Swift 層の
  case 追加のみ。notification object は trigger surface で、focused group を対象にする
  （controller が `surfaceTree.contains(view)` で自 tree 内であることを確認）。
- **ラベル常時表示の帰結**: 単一 group でも `defaultGroupName`（"Group 1"）ラベルが左上に出る
  （従来はピクセル同等のため非表示だった）。SPEC §6.3 準拠とユーザー合意による意図的変更。
- **group focus 切替の undo は未登録（既存 new_group_split と同様）**: `focusGroup` も
  `replaceSurfaceTree` の surfaceTree-only undo を流用できない（focus 切替後に旧 tree を
  誤った group へミラーする）ため undo 非登録。group-aware undo 横断タスクの対象（下記）。

---

## Phase 4: goto_group / resize_group / equalize_groups（§11.3–§11.5, §15 Phase 4）✅ 完了

- [x] `goto_group`（§11.3）: effectiveVisibleGroupTree で方向/next/prev 移動、
      移動先の last focused pane へ復元、hidden は対象外、zoom 中 no-op
      （`WorkspaceModel.gotoGroupTarget` で対象解決 → 既存 `focusGroup` で surfaceTree 差替+last pane focus）
- [x] `resize_group`（§11.4）: visible で隣接探索 → canonical の LCA split ratio を変更
      （`WorkspaceModel.resizeFocusedGroup`。px→比率は controller が window content size 基準で変換）
- [x] `equalize_groups`（§11.5）: **暫定案を採用** — hidden が空のときのみ実行、
      ある場合は no-op + warning（log）。hidden は Phase 5 まで常に空のため現状は常時実行と等価。
      推奨案（visible 対応 canonical split のみ均等化）は hidden が実体化する Phase 5 で対応
  - [x] `WorkspaceModel.equalizeGroups`（hidden 空ガード → `canonicalGroupTree.equalized()`）
- [x] デフォルト keybind: Cmd+Ctrl+Opt+方向 = goto_group / Cmd+Ctrl+Opt+Shift+方向 = resize_group:dir,10
      （§10.3, §10.4, `src/config/Config.zig` macOS 既定）。equalize_groups は SPEC に既定割当なし＝未配線

**成功条件**: 方向移動 / last focused pane 復帰 / group 境界 resize / equalize 動作。
→ `zig build -Demit-macos-app=false` exit 0、`zig build test`（"group split" パーサ）パス、
`zig fmt --check src/config/Config.zig` exit 0、`swiftlint --strict`（変更 5 ファイル）0 violations、
`xcodebuild test`（`WorkspaceModelTests` に Phase 4 10 件追加 = goto 4 / resize 4 / equalize 2、
全 `GhosttyTests` `** TEST SUCCEEDED **` 回帰なし）。方向移動・LCA resize・equalize の論理は
データ層（`WorkspaceModelTests`）で担保。

- [ ] 実機での目視確認（goto_group 方向移動・last focused pane 復帰・resize_group divider 移動・
      equalize_groups）は未実施（ロジックは自動テストで担保。Phase 5 zoom/hide の目視と併せて実施推奨）

### Phase 4 実装メモ（レビュー観点）

- **配線は Phase 2.3/3 と同一経路**: Zig core 語彙は Phase 2.1 で整備済みのため Swift 層のみ追加。
  `Ghostty.App.action()` に `GOTO_GROUP`/`RESIZE_GROUP`/`EQUALIZE_GROUPS` の case →
  3 notification（`ghosttyGotoGroup`/`ghosttyResizeGroup`/`ghosttyEqualizeGroups`）→
  `BaseTerminalController` ハンドラ → `WorkspaceModel`。
- **goto_group は label-click 機構を再利用**: `gotoGroupTarget` が visible tree の `focusTarget` で
  対象 group を解決（zoom 中 / 無 focused / 隣接なし / 対象==focused は nil）。controller は
  Phase 3 の `focusGroup` をそのまま呼び、surfaceTree 差替 + 移動先 last focused pane への
  キーボード focus（§14.12）を流用。next/prev の単一 group 自己ラップは `target != focused` で弾く。
- **resize_group の px→比率変換（要レビュー注目点）**: `adjustRatio` は正規化比率デルタを取るため、
  controller が `amount`(px) を `window.contentView.bounds` の軸方向サイズで割って比率化する。
  **トップレベル単一 group split（2 group の一般ケース）では厳密**、ネスト group split では LCA split の
  コンテナが小さいぶん divider 移動量が `amount`px をやや下回る近似（clamp [0.1,0.9] 済み）。
  隣接探索は visible tree、ratio 適用は canonical tree の LCA split（`lowestCommonSplitPath`）で、
  hidden があっても canonical を正しく更新する設計を維持。
- **resize divider ドラッグは意図的に先送り**: `GroupSplitTreeView.groupAction` は nil のまま。
  divider が返すノードは visible tree のもので、Phase 5 で hidden により visible≠canonical になると
  canonical への対応付けが必要になり複雑化する。keybind 経路が §11.4 を完全に満たすため、
  divider ドラッグ resize は Phase 5（hidden 実装）と併せて対応する横断課題とする。
- **equalize_groups の暫定採用**: hidden が空のときのみ `canonicalGroupTree.equalized()`。hidden が
  ある場合は warning ログを出し no-op。hidden は Phase 5 まで生成されないため現状は常時実行と等価で、
  SPEC §11.5 の MVP フォールバックに準拠。推奨案（visible 対応 split のみ均等化）は hidden が実体化する
  Phase 5 で本対応。
- **`WorkspaceModel.init(_ state:)` 追加**: 任意の `WorkspaceState`（multi-group / zoomed / hidden）を
  直接包む initializer。zoom/hidden を立てる API は Phase 5 まで無いため、テストで zoom 中 no-op /
  hidden 時 equalize 拒否を検証するために導入。Phase 6 restore の rehydrate でも再利用予定。
- **performability**: `goto_group` は対象解決可能時のみ true（`gotoSplit` 同様、移動先が無ければ
  キーイベント非消費）。`resize_group` は visible が split のときのみ true（`resizeSplit` の `isSplit`
  ゲート同様、方向ごとの隣接有無はハンドラが解決）。`equalize_groups` は void（`equalizeSplits` 同様）。

---

## Phase 5: zoom / hide / shelf（§11.6–§11.8, §7.2, §15 Phase 5）✅ 完了

- [x] `toggle_group_zoom`（§11.6）: トグル、描画は外→内（group zoom → 内部 split zoom）
      （`WorkspaceModel.toggleGroupZoom`。描画は `effectiveVisibleGroupTree`〔group 層〕+
      `paneTree.zoomed`〔pane 層〕が外→内で自然合成され追加実装不要）
- [x] Cmd+Opt+Enter = toggle_group_zoom（§10.5, 既存 split zoom と非衝突、`src/config/Config.zig`）
- [x] zoom 中 Cmd+D は group 内 split / new_group_split は zoom 解除して隣作成（§11.1, §18.4）
      （Cmd+D は `surfaceTree`〔= focused/zoomed group の panes〕を分割＝zoomed group 内 split。
      new_group_split の zoom 解除は Phase 2.3 の `openNewGroup` で実装済み。いずれもアーキテクチャの帰結）
- [x] `hide_group`（§11.7）: hiddenGroupIDs 追加、process は生存、canonical/groups 不変、
      focus は visible neighbor へ、**最後の visible group は hide 拒否**（§18.2）
      （`WorkspaceModel.hideFocusedGroup` → controller `hideFocusedGroup` が surfaceTree 差替+focus 移動）
- [x] zoomed group の hide は zoom 解除後に hide（§18.3）（`hideFocusedGroup` 内で zoom 先行解除）
- [x] `show_group`（§11.8）: hidden から除外、zoom 解除、focus 移動、last pane 復元
      （`WorkspaceModel.showGroup` → controller `showGroup`。action は `show_group:<name>`、shelf は id 直指定）
- [x] `HiddenGroupShelf.swift`（§7.2）: 右上 overlay、0 個非表示 / 1〜4 個 pill /
      5 個以上は `[+N]` メニュー、pill click で即 show（`TerminalWorkspaceView` の ZStack overlay、§14.14）
- [x] Cmd+Opt+H = hide_group（§10.5, `src/config/Config.zig`）

**成功条件**: group 単位 zoom / zoom 中 Cmd+D は内部 split / hide は kill しない /
shelf 表示 / pill click で即復帰。
→ `zig build -Demit-macos-app=false` exit 0、`zig build test`（"group split" / "ghostty.h" パーサ）パス、
`zig fmt --check`（Config.zig / Binding.zig）exit 0、`swiftlint --strict`（変更 8 ファイル）0 violations、
`xcodebuild test`（`WorkspaceModelTests` に Phase 5 13 件追加 = zoom 3 / hide 5 / show 5、
`SplitTreeTests`/`TerminalRestorableTests` 回帰なし `** TEST SUCCEEDED **`）。group 単位 zoom / hide の
neighbor focus / 最後の visible group 拒否 / un-zoom on hide·show の論理はデータ層で担保。

- [ ] 実機での目視確認（group zoom トグル・zoom 中 Cmd+D が内部 split・hide で kill されない・
      shelf 表示〔1〜4 pill / 5+ で `[+N]`〕・pill click で即復帰）は未実施
      （ロジックは自動テストで担保。Phase 6 restore の目視と併せて実施推奨）

### Phase 5 実装メモ（レビュー観点）

- **zoom は派生表示状態の最小変更**: `toggleGroupZoom` は `state.zoomedGroup` を flip するだけ。
  `surfaceTree`〔focused group が source of truth〕は不変で、focused group は zoom 後も focused のため
  group 切替を伴わない。描画は `effectiveVisibleGroupTree`（zoom 時 `treeContainingOnly`）の変化で
  `@ObservedObject` 経由再描画。group zoom（外）と inner split zoom（`paneTree.zoomed`、内）は SPEC §14.15 の
  外→内順に自然合成（GroupView が `effectiveVisibleGroupTree` の単一 leaf を描き、その中の
  `TerminalSplitTreeView` が `tree.zoomed ?? tree.root`）。
- **zoom トグル時の focus 再付与**: zoom で group 木の構造（split↔単一 leaf）が変わり `.id(structuralIdentity)` が
  変化 → GroupSplitSubtreeView が再生成され同一 SurfaceView を再ホスト。pane 層 `toggle_split_zoom` と同じく
  first responder が外れ得るため、ハンドラで `window.makeKeyAndOrderFront` + 起点 surface へ `moveFocus` を再付与
  （`ghosttyDidToggleSplitZoom` を踏襲）。
- **hide の neighbor 解決は canonical 基準（zoom 無視）**: `neighborAfterHiding` は hide 対象を加えた
  hidden 集合で `canonicalGroupTree.nearestLeaf(matching: visible)` を引く。§18.3 で hide は zoom を先行解除する
  ため zoom を無視して canonical で探索するのが正しい。neighbor が無い＝**最後の visible group**（§18.2）→ 拒否。
  performability（`canHideFocusedGroup`）も同経路で判定し、拒否時はキー非消費。
- **hide/show は group 切替機構を再利用**: hide は「outgoing pane 保存 → hidden 追加 → zoom 解除 →
  neighbor へ focus」、show は「outgoing 保存 → hidden 除外 → zoom 解除 → 対象へ focus」を model で原子的に行い、
  controller が `surfaceTree = focusedPaneTree` + `moveKeyboardFocus(toGroupSurface:)` で仕上げる。
  この末尾処理は `focusGroup`/`goto_group`/`hide`/`show` 共通の private ヘルパーへ抽出（§14.12）。
  **process は kill しない**（§14.7）: hidden group の `paneTree` は `groups` に生存し canonical も不変なので、
  `show_group` で元位置に自然復帰。
- **shelf は workspace overlay（§14.14）/ 安定順**: `HiddenGroupShelf` は `TerminalWorkspaceView` の ZStack
  top-trailing overlay で、個別 GroupView の責務ではない。hidden は Set のため `createdAt`（同値時 id）で
  ソートし pill 順がちらつかないようにした。0 個は overlay 自体を出さない。5 個以上は先頭 3 pill + `[+N]` Menu
  （SPEC §7.2 の `[a] [b] [c] [+N]` 例に厳密準拠）。pill/menu クリックは `onShowGroup`→controller `showGroup(id)`。
- **action 配線は Phase 2.3/3/4 と同一経路**: Zig core 語彙は Phase 2.1 で整備済み。`Ghostty.App.action()` に
  `TOGGLE_GROUP_ZOOM`/`HIDE_GROUP`/`SHOW_GROUP` の case → 3 notification → `BaseTerminalController` ハンドラ。
  `show_group` のみ引数あり（既存 `ghostty_action_set_title_s` を再利用、`.title` を name として ShowGroupNameKey で運搬）。
  performability: zoom は `canToggleGroupZoom`（visible が複数 or 既 zoom）、hide は `canHideFocusedGroup`、
  show は該当名 hidden group の存在で gate。
- **group 操作の undo は引き続き未登録**: hide/show/zoom も `surfaceTree`-only undo を流用できない
  （focusedGroup 切替後に旧 tree を誤 group へミラー）ため undo 非登録。group-aware undo 横断タスクの対象（後述）。
- **新規ファイルの Xcode 取り込み**: `HiddenGroupShelf.swift` は file-system synchronized group により
  自動コンパイル対象（`TerminalWorkspaceView` からの参照解決＋テストビルド成功で確認）。

---

## Phase 6: restore（§12, §15 Phase 6）✅ 完了

- [x] 保存: canonicalGroupTree / groups / names / paneTree / focusedGroup /
      group ごとの focusedSurface（§12.1）
      （`WorkspaceState` 全体を `InternalState` v8 の `workspace: WorkspaceState?` として永続化。
      `WorkspaceState` 既存 Codable が canonical / groups〔name / paneTree / focusedSurface〕/
      focusedGroup を保存。各 group の `focusedSurface` は `GroupState.focusedSurface` で保存済み）
- [x] 非保存: hiddenGroupIDs / zoomedGroup（§12.2）
      （`WorkspaceState` の Codable が両者を encode 対象外とし decode 時クリア。
      `WorkspaceState.restoring` でも冗長にクリアしランタイム状態の混入を防止）
- [x] `restoreWorkspace`（§12.3）: 全 group visible・非 zoom で復元、
      focusedGroup が無効なら firstLeaf へフォールバック
      （`WorkspaceState.restoring(_:)` として実装。hidden/zoom クリア + focusedGroup を
      groups·canonical 双方で検証 → 無効時 `canonicalGroupTree.firstLeaf?.id`）
- [x] 起動時 pane は新規 shell（live process/scrollback/PTY は復元しない）
      （`SurfaceView.init(from:)` が global app から新 surface を生成〔§12.3〕。
      全 group の `paneTree` が decode 時に新 shell を起こす。UUID は保持され focus 復元に利用）
- [x] 既存 `TerminalRestorable` 系との整合
      （`TerminalRestorableState` version 7→8〔minimumVersion 5 据置〕。`workspace` は
      optional 追加フィールドで pre-v8 archive は `decodeIfPresent` 合成で nil → 従来の
      単一 surfaceTree 復元へフォールバック。v1/v5/v7 fixture が v8 `InternalState` へ無改修で round-trip）

**成功条件**: layout / names / pane layout 復元 / hidden は全 visible / zoom は非 zoom。
→ `zig build -Demit-macos-app=false` exit 0、`swiftlint --strict`（変更 7 ファイル）0 violations、
`xcodebuild test`（`GhosttyTests` 全パス `** TEST SUCCEEDED **` = `WorkspaceStateTests` に restoring 4 件追加
〔hidden/zoom クリア / 有効 focusedGroup 保持 / 無効·nil 時 firstLeaf フォールバック〕、
`TerminalRestorableTests` の version assertion 7→8 更新 + v1/v5/v7 後方互換 round-trip 回帰なし）。
restore の論理〔§12.3 の hidden·zoom クリア / focusedGroup 検証〕はデータ層で担保。

- [ ] 実機での目視確認（複数 group + 各 group pane layout / names を保存 → 再起動 → 全 group visible·
      非 zoom·layout·name 復元 / focusedGroup の focused pane へ復帰）は未実施
      （ロジックは自動テストで担保。横断タスク完了時の実機回帰と併せて実施推奨）

### Phase 6 実装メモ（レビュー観点）

- **採用設計（`InternalState` v8 に `workspace` を追加・`surfaceTree` は据置）**: 既存 restore は
  `TerminalRestorableState.InternalState`〔version 7〕が `surfaceTree`/`focusedSurface` 等を持つ。
  Phase 6 は version 8 として **optional の `workspace: WorkspaceState?`** を追加するだけ。pre-v8 archive は
  `workspace` キーを欠くため Swift 合成 Codable の `decodeIfPresent` で nil となり、従来の単一 surfaceTree
  復元経路へ自動フォールバック。これは v5→v7 で `effectiveFullscreenMode`/`tabColor`/`titleOverride` を
  追加したのと同じ「additive optional」パターンで、`restoreTerminal57`/`quickTerminalRestorableFromV1`
  の既存 fixture が無改修で v8 `InternalState` へ decode できることで後方互換を実証。
- **encode は冗長だが安全**: `InternalState.init(from controller:)` は `surfaceTree`〔= focused group の
  panes〕と `workspace.state`〔全 group〕の双方を保存する。focused group の paneTree は `surfaceTree`
  と二重化するが、focused group の paneTree は `surfaceTreeDidChange` 経由で常時 `surfaceTree` にミラー
  同期されているため両者は一致し、保存内容は無矛盾。`SurfaceView` の Codable は pwd/uuid/title のみで
  scrollback/PTY を含まないため二重化のコストは軽微。
- **decode は workspace 優先・surfaceTree フォールバック**: `TerminalWindowRestoration.restoreWindow` は
  `state.workspace` があれば `WorkspaceState.restoring` を適用し `withWorkspace:` で controller を構築。
  無ければ従来どおり `withSurfaceTree: state.surfaceTree`。`restoring` 後に `focusedGroup == nil`〔= groups
  空など異常〕の場合も surfaceTree 経路へ退避し、空 workspace で起動しないよう防御。
- **controller 構築の identity 整合**: `BaseTerminalController.init(workspace:)` は restore branch で
  ① `surfaceTree = model.focusedPaneTree`〔この時点の `workspace` はまだ既定の空 model で focusedGroup
  無 → ミラーは no-op〕→ ② `self.workspace = model` の順。これにより `surfaceTree` の `SurfaceView`
  インスタンスと `workspace.groups[focused].paneTree` のそれが**同一**になり、source-of-truth とミラーの
  整合が保たれる。非 focused group の `paneTree` は decode 時に live surface 化され、Phase 1 の
  `TerminalWorkspaceView → GroupSplitTreeView → GroupView` 経路が `effectiveVisibleGroupTree`〔全 visible
  group〕から描画するため全 group が復元表示される。
- **focus 復元は focused group の stored focus を優先**: workspace restore 時は
  `c.workspace.focusedGroupState?.focusedSurface` を `surfaceTree`〔= focused group〕内で解決。
  `focusedGroup` が firstLeaf へフォールバックしても正しい pane に着地する。legacy 経路は従来どおり
  top-level `state.focusedSurface` を使用〔`init(wrapping:)` が focusedSurface を firstLeaf に初期化する
  ため、workspace 経路と分岐しないと legacy で「保存した focused surface ではなく先頭 pane」に
  着地する事故が起きるため、明示的に分岐〕。
- **新規 C/Zig 変更なし**: Phase 6 は純 Swift。Zig core の action 語彙は restore に不要〔restore は
  AppKit の window restoration 経路〕。よって `zig build`〔core コンパイル〕は無関係に exit 0、Zig
  テストは対象外〔変更ファイルゼロ〕。

---

## 横断: close_group / Cmd+W（§11.9, §11.10, §18.5）✅ 完了

- [x] close confirmation（§11.9: Cancel / Close Group のみ、Hide Instead なし）
      ※ 専用 `CloseGroupConfirmation.swift`（SwiftUI）は**不採用**。既存 `close_surface` が
      Ghostty #560 の SwiftUI confirmationDialog バグ回避で NSAlert（`confirmClose`）を使うのに合わせ、
      同じ 2 ボタン NSAlert を再利用（`BaseTerminalController.closeFocusedGroup`）。メッセージは
      `Close Group "<name>"?` / `This will close N pane(s) and terminate their processes.`
- [x] `close_group`: focused group の全 surface を terminate → canonicalGroupTree/groups/hidden から削除 →
      zoom 対象なら解除 → nearest visible group へ focus（`WorkspaceModel.closeFocusedGroup` →
      controller `performCloseFocusedGroup` が surfaceTree 差替 + last pane focus）
- [x] 最後の pane で Cmd+W は close_group confirmation に昇格（§11.10, 不変条件 18）
      ※ 昇格は **複数 group のときのみ**（`groups.count > 1 && surfaceTree.removing(node).isEmpty`）。
      単一 group では従来の `close_surface`（"Close Terminal?" / tab·window close）経路を維持し UX 非回帰
- [x] 最後の group の close は tab/window close に委譲（§18.5）
      （`closeFocusedGroup` が `.closedLast` 時は model 非変更のまま `replaceSurfaceTree(.init())` →
      `TerminalController` override が `closeTabImmediately()` へ。既存 tab/window close の undo を流用）
- [x] Zig core 語彙は Phase 2.1 で整備済み（`close_group` は `Binding.zig`/`Surface.zig`/`action.zig`/
      `ghostty.h`/`command.zig` に配線済み）。本タスクは純 Swift 配線
      （`Ghostty.App.action()` に `GHOSTTY_ACTION_CLOSE_GROUP` case + `closeGroup` ヘルパー →
      `ghosttyCloseGroup` notification → `BaseTerminalController` ハンドラ）

**検証**: `zig build -Demit-macos-app=false` exit 0、`zig build test`（"close_group" パーサ /
"ghostty.h" enum 同期）exit 0、`swiftlint --strict`（変更 4 ファイル）0 violations、
`xcodebuild test`（`GhosttyTests` 全パス `** TEST SUCCEEDED **` = `WorkspaceModelTests` に close_group
6 件追加〔neighbor 切替+prune / 単一 group は .closedLast かつ model 不変 / focused 無時 nil /
zoom 解除 / 可視 neighbor 無時は hidden を reveal〔§14.6〕/ 他 hidden は hidden 維持〕、
`SplitTreeTests`/`WorkspaceStateTests`/`TerminalRestorableTests` 回帰なし）。

- [ ] 実機での目視確認（close_group confirmation の 2 ボタン / 複数 group での Cmd+W 昇格・
      visible neighbor へ focus / 単一 group は "Close Terminal?" のまま / 最後の group close で
      tab·window close）は未実施（ロジックは自動テストで担保。group-aware undo 着手時の実機回帰と併せて実施推奨）

### close_group 実装メモ（レビュー観点）

- **confirmation は live process があるときのみ**: `closeFocusedGroup` は focused group の panes
  （= `surfaceTree`）に `needsConfirmQuit` な surface が 1 つでもあれば NSAlert を出し、無ければ即実行。
  これは `close_surface` / window close と同じ UX で、ダイアログ文言「terminate their processes」が
  live process 前提のため整合的。SPEC §11.9 の「必ず確認」は live multi-pane group の明示 close では
  実質常に確認となり満たされる一方、dead shell の最後の pane を Cmd+W で閉じる常用ケースで余計な
  prompt を出さない（=既存挙動の非回帰）。
- **Cmd+W 昇格は複数 group ゲート**: `ghosttyDidCloseSurface` で `surfaceTree.removing(node).isEmpty`
  かつ `groups.count > 1` のときだけ `closeFocusedGroup()` へ昇格。単一 group の最後の pane は従来の
  `close_surface` 経路（空ツリー → `closeTabImmediately`）に委ね、文言も "Close Terminal?" のまま。
  複数 group のときは sibling が canonical に必ず存在するため `closeFocusedGroup` は必ず `.switched` を返し、
  tab を誤って閉じない。
- **`.closedLast` は model 非変更**: 最後の group の close は `closeFocusedGroup` が**何も変更せず**
  `.closedLast` を返し、controller が `replaceSurfaceTree(.init())` で既存 tab/window close 経路へ委譲する。
  これにより close の undo（既存 `closeTabImmediately` の restorable-state スナップショット）が
  **無傷の workspace（1 group）**を捉え、tab 復元時に空 workspace で起動しない。
- **focused group は常に可視（§14.6）の保全**: close 後の focus 先は pre-mutation canonical で
  `nearestLeaf(matching: !hidden)` を優先し、可視 neighbor が無ければ `nearestLeaf(matching: 全て)` に
  フォールバックして**その group を un-hide（reveal）**してから focus する。これは「focused（visible）group が
  最後の 1 つで他は全 hidden」という稀なケースで、close 後に可視 group が消えて blank workspace になるのを防ぐ。
- **process 終了は参照ドロップに依拠（§14.8）**: closed group は `groups`・canonical から除去され、
  `surfaceTree` も新 focused group の木へ差し替わるため、closed group の `SurfaceView` は強参照を失い
  dealloc → PTY/process 終了。既存 `removeSurfaceNode` と同じ機構で、明示 close 呼び出しは不要。
- **undo は引き続き未登録**: 他の group 操作同様、`replaceSurfaceTree` の surfaceTree-only undo は
  focusedGroup 切替後に旧 tree を誤 group へミラーするため流用不可。`.switched` 経路は undo 非登録、
  `.closedLast` 経路のみ既存 tab/window close の undo を流用。group-aware undo 横断タスクで統合予定（下記）。

## 横断: group 操作の undo（Phase 2.3 申し送り）✅ 完了

- [x] group 層を含む undo/redo の設計と実装。`WorkspaceState` 全体のスナップショットを
      まとめて復元する group-aware undo を新設し、**構造的** group 操作
      （`new_group_split` / `hide_group` / `show_group` / `close_group` の `.switched`）へ適用。
      合わせて既存 pane undo（`replaceSurfaceTree`）に **focusedGroup ガード**を追加し、
      別 group 切替後に旧 surfaceTree を誤ミラーする層破壊を根絶。
  - [x] `WorkspaceModel.restoreState(_:)`: `WorkspaceState` を丸ごと差替える復元 API
        （focusedGroup / canonical / groups / hidden / zoom を原子的に。消えた group を指す
        `renamingGroup` は併せてクリア）+ 単体テスト 4 件
        （`restoreStateSwapsEntireState` / `restoreStateRoundTripsAfterHide` /
        `restoreStateCancelsRenameForMissingGroup` / `restoreStateKeepsRenameForSurvivingGroup`）
  - [x] `BaseTerminalController.registerWorkspaceUndo` / `restoreWorkspaceState`:
        before/after の `WorkspaceState` を捕捉する対称 ping-pong。スナップショットが
        live `SurfaceView` を保持するため close_group の undo は `undoExpiration` 窓内で
        process を生かす（既存 close_surface undo と同セマンティクス）
  - [x] pane undo（`replaceSurfaceTree`）に `groupID` ガード: 別 group で再生時は no-op
        （同 group へ戻れば再び有効。期限切れ非依存で堅牢）

### group-aware undo 実装メモ（レビュー観点）

- **採用設計（天機 /abyss と協議の上、refined Option B を簡素化）**: 当初案 Option A
  「全 group 切替を undo スタックに載せてバリアにする」は `ExpiringUndoManager` の**個別期限切れ**で
  バリア不変条件が崩れ corruption が再発しうるため却下。代わりに ①構造的 group 操作のみ
  whole-state スナップショット undo、②pane undo に focusedGroup ガード、を採用。**②のガード単独で
  corruption は完全に防げる**（別 group での pane undo は no-op、同 group 復帰で再有効、期限切れ非依存）
  ため、天機が補助的に提案した token-target による pane undo の選択的クリアは**意図的に省略**し
  差分を最小化した（共有 pane undo 経路への手術リスク回避）。
- **undo 登録するもの / しないもの（pane 層との parity を基準に判断）**:
  - 登録: `new_group_split`("New Group") / `hide_group`("Hide Group") / `show_group`("Show Group") /
    `close_group`.switched("Close Group")。いずれも focusedGroup を切替える構造的変更。
  - 非登録（parity）: `focusGroup`/`goto_group`（純ナビ＝`goto_split`・タブ切替と同様）、
    `resize_group`（divider drag resize）、`equalize_groups`（`equalize_splits`）、
    `toggle_group_zoom`（`toggle_split_zoom`・runtime-only）、`rename_group`
    （`prompt_tab_title`・インラインエディタ内 text undo はローカル）。
  - `close_group`.closedLast は model 非変更で既存 tab/window close（自前 undo 持ち）へ委譲するため
    **二重登録しない**。
- **復元順序が load-bearing**: `restoreWorkspaceState` は ①`workspace.restoreState` で state を先に復元
  → ②`surfaceTree = focusedPaneTree` → ③`moveKeyboardFocus`。②の `surfaceTreeDidChange` ミラーが
  読む `self.focusedSurface` が古くても、`replaceFocusedPaneTree` が「復元木に無い surface は無視し
  stored focus を保持」するため無害。
- **既知の制約 / 残課題（follow-up）**:
  - **pane undo メニュー表示**: 別 group へ切替後も "Undo New Split" 等がメニューに残り、押下すると
    ガードで no-op になる（cosmetic）。完全解消には token-target での選択的クリアが必要。
  - **state-only 変更の restorable-state 非無効化**: `resize_group`/`equalize_groups`/`rename_group` は
    `surfaceTree` を変えないため `surfaceTreeDidChange`→`invalidateRestorableState` を経由せず、
    canonical 比率 / name の変更が再起動保存に乗らない**既存の潜在バグ**（本タスク範囲外。別途
    明示 `invalidateRestorableState()` フックが必要）。
  - undo の実機目視（Cmd+Z で new_group/hide/show/close が反転・process 生存）は未実施。

### group undo 由来の follow-up（任意・低優先）

- [ ] state-only group 変更（`resize_group` / `equalize_groups` / `rename_group`）が
      `surfaceTree` を変えないため restorable-state が無効化されない既存バグの修正
      （各ハンドラで明示 `invalidateRestorableState()` を呼ぶ。本タスクで顕在化）
- [ ] pane undo のメニュー残留（別 group 切替後に no-op になる項目）を消すための
      token-target ベース選択的クリア（cosmetic。現状はガードで安全だが UX 改善余地）

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
