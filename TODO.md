# TODO — 階層的ペイン（グループレイヤー）実装

`SPEC.md` を実装するための作業リスト。
方針: ① `SplitTree` のジェネリック制約を一般化して両層で再利用、
② グループ用 action は Zig core (`src/input/Binding.zig`) まで完全統合、
③ Phase 0〜6 を順に実装する。

進捗を確認する正典は `SPEC.md`（特に §14 不変条件、§19 テスト計画）。

---

## Phase F: 基盤整備（Phase 1 の前提）

`SplitTree<GroupRef>` を成立させるための事前リファクタ。
ここが完了するまで Phase 1 以降には着手しない。

### F.1 SplitTree のジェネリック制約一般化
- [ ] `SplitTree<ViewType: NSView & Codable & Identifiable>` の制約を
      `Element: Codable & Identifiable & Equatable` 系へ緩める（`SplitTree.swift:5`）
- [ ] NSView 依存メソッドを `extension SplitTree where Element: NSView` へ分離
  - [ ] `viewBounds()` / `calculateViewBounds(in:)` / `dimensions()` / `spatialSlots(in:)`
  - [ ] `valuesPublisher(...)`（KVO 依存）
- [ ] 描画用 `spatial(within:)` 系が bounds を外部注入で動くよう整理
      （グループ層は実 NSView を持たないため）
- [ ] 既存 `SplitTree<Ghostty.SurfaceView>` 利用箇所が無改修〜最小改修で通ることを確認
      （`BaseTerminalController.swift:44` ほか SplitTree 利用全箇所）

### F.2 グループ層が必要とするヘルパーの汎用実装
SPEC が前提とするが既存に無いメソッドを、汎用 `SplitTree` extension として追加する。
- [ ] `spatialNeighbor(from:direction:)`（既存 `slots(in:from:)`/`doesBorder` を利用）
- [ ] `lowestCommonSplitPath(between:and:matchingResizeDirection:)`
- [ ] `adjustRatio(at:direction:amount:)`（既存 `resizing(to:)` を利用）
- [ ] `pruningLeaves(_ shouldPrune:)`（hidden 除外用）
- [ ] `treeContainingOnly(_:)` / `subtreeContainingOnly(_:)`（zoom 用）
- [ ] `nearestVisibleGroup(to:)`
- [ ] `firstLeaf`
- [ ] 各ヘルパーの単体テスト（`SplitTreeTests` に追加）

### F.3 回帰確認
- [ ] `zig build -Demit-macos-app=false` でビルド通過
- [ ] 既存 split 操作（Cmd+D / Cmd+Shift+D / goto / resize / equalize / zoom / close）に
      挙動変化がないことを確認

---

## Phase 0: 既存挙動を 1 グループに包む（§15 Phase 0）

見た目・操作を変えず内部だけ二層化する。

### 0.1 データモデル（§5, ファイル構成 §16）
- [ ] `Features/Groups/` を新設
- [ ] `GroupID.swift` / `SurfaceID` / `GroupRef` / `SurfaceRef`（§5.1）
- [ ] `GroupState.swift`（§5.3: name, paneTree, focusedSurface, createdAt, lastFocusedAt）
- [ ] `WorkspaceState.swift`（§5.2: canonicalGroupTree, groups, hiddenGroupIDs,
      focusedGroup, zoomedGroup, version）
- [ ] `SurfaceRestoreSpec`（§5.4, MVP は nil 許容）

### 0.2 二層化
- [ ] `WorkspaceModel`（`ObservableObject`）を新設し、`BaseTerminalController` の
      `surfaceTree` を `canonicalGroupTree = leaf(defaultGroup)` /
      `groups[defaultGroup].paneTree = 旧 surfaceTree` で包む
- [ ] `effectiveVisibleGroupTree` 派生プロパティ（§13）
- [ ] 既存 Cmd+D / Cmd+Shift+D / goto_split / resize_split / toggle_split_zoom /
      close_surface が **focused group の paneTree に委譲**されて従来通り動く

**成功条件（§15 Phase 0）**: 上記 6 操作すべてが従来通り。

---

## Phase 1: GroupSplitTreeView（§6, §15 Phase 1）

- [ ] `TerminalWorkspaceView.swift`（§6.2: ZStack で GroupSplitTree + HiddenShelf overlay）
- [ ] `GroupSplitTreeView.swift`（`SplitTree<GroupRef>` を描画）
- [ ] `GroupView.swift`（§6.3: TerminalSplitTreeView + GroupLabel overlay）
- [ ] SwiftUI structural identity を `.id(node.structuralIdentity)` で担保（§4.3）

**成功条件**: 1 group で既存同等表示 / 2 group で各 paneTree 独立表示 / identity 破綻なし。

---

## Phase 2: new_group_split（§9, §11.1, §15 Phase 2）

### 2.1 Zig core 統合（ギャップ3 対応）
- [ ] `src/input/Binding.zig:629〜` に group action を union 追加
  - [ ] `new_group_split: SplitDirection`
  - [ ] `goto_group: SplitFocusDirection`
  - [ ] `resize_group: SplitResizeParameter`
  - [ ] `equalize_groups` / `toggle_group_zoom` / `hide_group`
  - [ ] `show_group: []const u8` / `rename_group` / `set_group_title: []const u8`
  - [ ] `close_group`
- [ ] keybind パーサのテスト追加（`Binding.zig` 内、既存 split test に倣う）
- [ ] apprt action 経由で Swift `WorkspaceModel` までプラミング

### 2.2 GroupNameGenerator（§8）
- [ ] `GroupNameGenerator.swift`（adjective-noun, 既存名衝突回避, 作成時のみ生成）

### 2.3 new_group_split 実装（§11.1, エッジ §18.4）
- [ ] focusedGroup 基準で新 GroupState 作成 → 初期 pane 1 つ → canonicalGroupTree へ挿入
- [ ] zoom 中は zoom 解除してから隣に作成し、新 group の初期 pane へ focus
- [ ] デフォルト keybind: Cmd+Opt+D / Cmd+Opt+Shift+D（§10.2, §17）

**成功条件**: 新 group がランダム名で作成 / 初期 pane 1 つ / focus 移動 /
Cmd+D は新 group 内のみ分割。

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
