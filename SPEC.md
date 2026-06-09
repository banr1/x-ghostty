# X-Ghostty 階層的ペイン仕様書

## 1. 目的

Ghostty の既存 split pane の上位に、**グループレイヤー**を追加する。

既存のペイン分割は「同一グループ内の terminal surface 分割」として維持し、新たに「グループ単位の分割・移動・ズーム・非表示・復元」を実装する。

```text
Window / Tab
└─ GroupTree
   ├─ Group: calm-river
   │  └─ PaneTree
   │     ├─ pane
   │     └─ pane
   └─ Group: copper-owl
      └─ PaneTree
         ├─ pane
         └─ pane
```

Ghostty 既存の action model には `new_split`, `goto_split`, `toggle_split_zoom`, `resize_split`, `equalize_splits`, `close_surface` があり、`new_split` は方向指定で split を作り、`toggle_split_zoom` は現在 split をタブ領域全体に拡大し、`resize_split` と `equalize_splits` も split 単位で定義されています。したがって、本機能は既存 action を上書きせず、**グループ版 action を並列追加する**設計にする。([Ghostty][1])

## 2. 非目的

初期実装では以下をやらない。

```text
- Linux / GTK 対応
- tmux / zellij 互換
- floating pane
- live session 完全復元
- scrollback / PTY 状態の永続復元
- drag & drop によるグループ移動
- グループ入れ替え UI
- hidden 状態の永続化
- zoom 状態の永続化
```

MVPでは、**グループ作成・名前表示・rename・focus移動・resize・equalize・zoom・hide/show・layout復元**までを対象とする。

## 3. 基本設計

採用する構造は **二層SplitTree**。

```swift
WorkspaceState
  canonicalGroupTree: SplitTree<GroupRef>
  groups: [GroupID: GroupState]
  hiddenGroupIDs: Set<GroupID>
  focusedGroup: GroupID?
  zoomedGroup: GroupID?
```

各 `GroupState` は、内部に通常のペイン分割木を持つ。

```swift
GroupState
  id: GroupID
  name: String
  paneTree: SplitTree<SurfaceRef>
  focusedSurface: SurfaceID?
```

Ghostty macOS 側の `SplitTree.swift` は、leaf/split 構造、zoom tracking、codable path、focus traversal、spatial navigation、insert/remove/replace/equalize/resize semantics を担う split model として整理されているため、グループ層でも `SplitTree<GroupRef>` を使い、既存の抽象を最大限再利用する。([Rexbrahh][2])

## 4. 最重要設計判断

### 4.1 `canonicalGroupTree` と `effectiveVisibleGroupTree` を分ける

グループの本来の配置は常に `canonicalGroupTree` に保持する。

```text
canonicalGroupTree:
  calm-river | logs | agent | server

hiddenGroupIDs:
  logs, agent

effectiveVisibleGroupTree:
  calm-river | server
```

`hide_group` は tree を破壊しない。
`show_group` は `hiddenGroupIDs` から除外するだけ。
`close_group` だけが `canonicalGroupTree` と `groups` を破壊する。

これにより、非表示グループを元の場所に戻すための path 復元ロジックが不要になる。

### 4.2 グループは最上位レイアウト単位

`Cmd+D` は常に focused group 内の `paneTree` だけを分割する。
グループ境界は越えない。

```text
Cmd+D:
  focusedGroup.paneTree を split

Cmd+Opt+D:
  canonicalGroupTree を split して新 group を作る
```

### 4.3 terminal surface の lifetime と layout tree を分離する

`SplitTree` は layout を表す。
PTY / surface / renderer / scrollback の実体は registry 側で保持し、tree 変形に伴って安易に再生成しない。

Ghostty の `TerminalSplitTreeView` は `SplitTree<Ghostty.SurfaceView>` を受け取り、tree の `zoomed ?? root` を描画対象にしており、SwiftUI の structural identity 問題を避けるために `.id(node.structuralIdentity)` を使っています。この既存設計に合わせ、グループ層も view identity を慎重に扱う。([GitHub][3])

## 5. データモデル

### 5.1 ID 型

```swift
struct GroupID: Codable, Hashable, Identifiable {
    let rawValue: UUID
    var id: UUID { rawValue }
}

struct SurfaceID: Codable, Hashable, Identifiable {
    let rawValue: UUID
    var id: UUID { rawValue }
}

struct GroupRef: Codable, Hashable, Identifiable {
    let id: GroupID
}

struct SurfaceRef: Codable, Hashable, Identifiable {
    let id: SurfaceID
}
```

### 5.2 WorkspaceState

```swift
struct WorkspaceState: Codable {
    var version: Int = 1

    var canonicalGroupTree: SplitTree<GroupRef>
    var groups: [GroupID: GroupState]

    // runtime-only
    var hiddenGroupIDs: Set<GroupID> = []
    var focusedGroup: GroupID?
    var zoomedGroup: GroupID?
}
```

`hiddenGroupIDs` と `zoomedGroup` は原則 runtime-only。
保存してもよいが、restore時には破棄する。

### 5.3 GroupState

```swift
struct GroupState: Codable, Identifiable {
    let id: GroupID
    var name: String

    var paneTree: SplitTree<SurfaceRef>
    var focusedSurface: SurfaceID?

    var createdAt: Date
    var lastFocusedAt: Date?
}
```

### 5.4 復元用 Surface

MVPでは live session 復元をしない。起動時は各paneを新規 shell で作る。

```swift
struct SurfaceRestoreSpec: Codable, Hashable, Identifiable {
    let id: SurfaceID
    var title: String?
    var initialWorkingDirectory: String?
    var initialCommand: [String]?
}
```

MVPでは `initialWorkingDirectory` と `initialCommand` は nil でもよい。

## 6. 描画モデル

### 6.1 View hierarchy

```text
TerminalWorkspaceView
  ├─ GroupSplitTreeView
  │   └─ GroupView
  │       ├─ TerminalSplitTreeView
  │       └─ GroupLabel overlay
  └─ HiddenGroupShelf overlay
```

### 6.2 TerminalWorkspaceView

```swift
struct TerminalWorkspaceView: View {
    @ObservedObject var workspace: WorkspaceModel

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let tree = workspace.effectiveVisibleGroupTree {
                GroupSplitTreeView(
                    tree: tree,
                    focusedGroup: workspace.focusedGroup,
                    action: workspace.handleGroupOperation
                )
            }

            HiddenGroupShelf(
                hiddenGroups: workspace.hiddenGroupsInDisplayOrder,
                onShow: { workspace.showGroup($0) }
            )
        }
    }
}
```

### 6.3 GroupView

Group label は terminal 描画領域を押し下げず、**半透明overlayとして重ねる**。

```swift
struct GroupView: View {
    let group: GroupState
    let isFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            TerminalSplitTreeView(
                tree: group.paneTree,
                action: handlePaneOperation
            )

            GroupLabel(
                title: group.name,
                isFocused: isFocused
            )
            .padding(6)
        }
    }
}
```

## 7. UI 仕様

### 7.1 グループラベル

各groupの左上に表示する。

```text
┌─ calm-river ───────────────┐
│                            │
│ terminal panes             │
└────────────────────────────┘
```

表示ルール:

```text
focused group:
  opacity 1.0
  背景強め
  border / accent 強め

unfocused group:
  opacity 0.35〜0.5
  背景弱め
  視認はできるが主張しすぎない
```

操作:

```text
single click label:
  その group に focus

double click label:
  inline rename

rename_group action:
  focused group の名前を prompt で変更
```

### 7.2 Hidden Group Shelf

非表示groupは右上固定の shelf に表示する。

```text
┌─ main ──────────────┬─ server ───── hidden: [logs] [agent] ┐
│                     │                                      │
└─────────────────────┴──────────────────────────────────────┘
```

仕様:

```text
hidden 0個:
  shelf 非表示

hidden 1〜4個:
  hidden: [name] [name] ...

hidden 5個以上:
  hidden: [a] [b] [c] [+N]
```

操作:

```text
pill click:
  即 show_group

+N click:
  hidden group menu を開く
```

Hidden shelf は `TerminalWorkspaceView` の overlay。
個別 `GroupView` の責務ではない。

## 8. グループ名生成

新規group名は固定 word list から `adjective-noun` 形式でランダム生成する。

```swift
enum GroupNameGenerator {
    static let adjectives = [
        "amber", "brave", "calm", "copper", "fuzzy",
        "gentle", "hidden", "lucky", "quiet", "silver"
    ]

    static let nouns = [
        "river", "owl", "shell", "forest", "moon",
        "stone", "field", "wave", "cloud", "spark"
    ]

    static func make(existing: Set<String>) -> String {
        for _ in 0..<64 {
            let name = "\(adjectives.randomElement()!)-\(nouns.randomElement()!)"
            if !existing.contains(name) { return name }
        }

        return "group-\(existing.count + 1)"
    }
}
```

生成は作成時のみ。
復元時に再生成してはいけない。
名前は `GroupState.name` に保存する。

## 9. Action 仕様

Ghostty既存の action naming に合わせ、`focus_group` ではなく `goto_group` を推奨する。既存の `goto_split` は方向または previous/next で split focus を移す action として定義されているため、グループ版も同じ語彙に寄せる。([Ghostty][1])

### 9.1 追加action一覧

```text
new_group_split:right
new_group_split:down
new_group_split:left
new_group_split:up
new_group_split:auto

goto_group:right
goto_group:down
goto_group:left
goto_group:up
goto_group:next
goto_group:previous

resize_group:right,10
resize_group:left,10
resize_group:up,10
resize_group:down,10

equalize_groups

toggle_group_zoom

hide_group
show_group:<group-id-or-name>

rename_group
set_group_title:<name>

close_group
```

### 9.2 既存actionとの対応

```text
new_split          -> new_group_split
goto_split         -> goto_group
resize_split       -> resize_group
equalize_splits    -> equalize_groups
toggle_split_zoom  -> toggle_group_zoom
close_surface      -> close_group
```

## 10. デフォルトキー割り当て

### 10.1 ペイン分割

既存維持。

```text
Cmd+D                 -> new_split:right
Cmd+Shift+D           -> new_split:down
```

### 10.2 グループ分割

```text
Cmd+Opt+D             -> new_group_split:right
Cmd+Opt+Shift+D       -> new_group_split:down
```

### 10.3 グループ移動

```text
Cmd+Ctrl+Opt+Left     -> goto_group:left
Cmd+Ctrl+Opt+Right    -> goto_group:right
Cmd+Ctrl+Opt+Up       -> goto_group:up
Cmd+Ctrl+Opt+Down     -> goto_group:down
```

### 10.4 グループリサイズ

```text
Cmd+Ctrl+Opt+Shift+Left     -> resize_group:left,10
Cmd+Ctrl+Opt+Shift+Right    -> resize_group:right,10
Cmd+Ctrl+Opt+Shift+Up       -> resize_group:up,10
Cmd+Ctrl+Opt+Shift+Down     -> resize_group:down,10
```

### 10.5 その他

```text
Cmd+Opt+Enter         -> toggle_group_zoom
Cmd+Opt+H             -> hide_group
Cmd+Opt+R             -> rename_group
```

`Cmd+Opt+Enter` は既存 split zoom と衝突しない形で「上位レイヤーのzoom」として覚えやすい。

## 11. 状態遷移仕様

### 11.1 `new_group_split`

挙動:

```text
1. focusedGroup を基準groupにする
2. zoomedGroup がある場合は、まず zoom を解除する
3. 新規 GroupState を作る
4. 新規 group 内に初期paneを1つ作る
5. canonicalGroupTree に GroupRef を挿入する
6. focus を新group内の初期paneへ移す
```

ズーム中に実行した場合:

```text
Before:
  zoomedGroup = server

new_group_split:right

After:
  zoomedGroup = nil
  server の右に新group
  focus = 新groupの初期pane
```

### 11.2 `Cmd+D`

常に focused group 内の `paneTree` のみを分割する。

```text
focusedGroup = server

Cmd+D:
  groups[server].paneTree.insert(...)
```

グループズーム中も同じ。
ズーム中group内でpane splitされる。

### 11.3 `goto_group`

方向移動は `effectiveVisibleGroupTree` に対して行う。

```swift
func gotoGroup(_ direction: FocusDirection) {
    guard zoomedGroup == nil else { return }
    guard let visibleTree = effectiveVisibleGroupTree else { return }

    let next = visibleTree.focusTarget(
        from: focusedGroup,
        direction: direction
    )

    if let next {
        focusedGroup = next
        focusLastPane(in: next)
    }
}
```

移動先groupでは、最後にfocusしていたpaneへ戻す。

```text
goto_group:right:
  group focus を移す
  targetGroup.focusedSurface を復元
```

hidden group は focus 対象にしない。
zoom中の `goto_group` は no-op でよい。

### 11.4 `resize_group`

`resize_group` は `effectiveVisibleGroupTree` の見た目上の隣接関係を使うが、ratio変更は `canonicalGroupTree` に適用する。

```text
1. visible tree で focusedGroup の隣接groupを探す
2. focusedGroup と neighbor の canonical tree 上の LCA split を探す
3. その split ratio を変更する
```

hidden group がいる状態でも、canonical tree を直接正しく更新する。

```swift
func resizeGroup(_ direction: Direction, amount: CGFloat) {
    guard zoomedGroup == nil else { return }
    guard let focused = focusedGroup else { return }
    guard let visibleTree = effectiveVisibleGroupTree else { return }

    guard let neighbor = visibleTree.spatialNeighbor(
        from: focused,
        direction: direction
    ) else { return }

    guard let splitPath = canonicalGroupTree.lowestCommonSplitPath(
        between: focused,
        and: neighbor,
        matchingResizeDirection: direction
    ) else { return }

    canonicalGroupTree = canonicalGroupTree.adjustRatio(
        at: splitPath,
        direction: direction,
        amount: amount
    )
}
```

### 11.5 `equalize_groups`

`equalize_groups` は visible group のレイアウトを均等化する。

ただし実装上は、単に `effectiveVisibleGroupTree.equalized()` の結果を保存してはいけない。
canonical tree に hidden group が残っているため、以下のどちらかを採用する。

推奨:

```text
visible group のみを対象に、対応する canonical tree 上の relevant split ratios を均等化する
```

MVPで難しい場合:

```text
hiddenGroupIDs が空の場合のみ equalize_groups を実行
hidden がある場合は no-op または warning
```

自分用forkでも最適設計を狙うなら、前者を実装する。

### 11.6 `toggle_group_zoom`

```text
if zoomedGroup == focusedGroup:
  zoomedGroup = nil
else:
  zoomedGroup = focusedGroup
```

描画時は:

```swift
if let zoomedGroup {
    effectiveVisibleGroupTree = canonicalGroupTree.subtreeContainingOnly(zoomedGroup)
} else {
    effectiveVisibleGroupTree = canonicalGroupTree.pruning(hiddenGroupIDs)
}
```

group zoom と inner split zoom は共存可能。

描画順序:

```text
1. group zoom を適用
2. group 内 paneTree の split zoom を適用
```

つまり外側から内側へ適用する。

### 11.7 `hide_group`

```text
1. focusedGroup を hiddenGroupIDs に追加
2. process / PTY / surface は生存
3. canonicalGroupTree は変更しない
4. groups は変更しない
5. zoomedGroup == hidden target なら zoom解除
6. focus は visible neighbor へ移す
7. hidden shelf に pill 表示
```

```swift
func hideGroup(_ id: GroupID) {
    guard groups[id] != nil else { return }

    hiddenGroupIDs.insert(id)

    if zoomedGroup == id {
        zoomedGroup = nil
    }

    if focusedGroup == id {
        focusedGroup = effectiveVisibleGroupTree?.nearestVisibleGroup(to: id)
    }
}
```

全groupをhiddenにしようとした場合:

```text
最後の visible group は hide できない
```

理由: workspace が空になると操作・復帰UIが不安定になるため。

### 11.8 `show_group`

```text
1. hiddenGroupIDs から除外
2. zoomedGroup を解除
3. focus をそのgroupへ移す
4. group内では最後にfocusしていたpaneへ戻す
```

```swift
func showGroup(_ id: GroupID) {
    guard hiddenGroupIDs.contains(id) else { return }

    hiddenGroupIDs.remove(id)
    zoomedGroup = nil
    focusedGroup = id
    focusLastPane(in: id)
}
```

canonical tree を変えていないため、元の場所に自然に戻る。

### 11.9 `close_group`

破壊的操作。必ず確認ダイアログを出す。

```text
Close Group “server”?

This will close 4 panes and terminate their processes.

[Cancel] [Close Group]
```

`Hide Instead` は入れない。

挙動:

```text
1. confirmation
2. group内の全surfaceを close
3. canonicalGroupTree から GroupRef を削除
4. groups から削除
5. hiddenGroupIDs から削除
6. zoomedGroup が対象なら解除
7. focus を nearest visible group に移す
```

既存 `close_surface` は close confirmation popup を出し得る action として定義されているため、`close_group` も同じく破壊的操作として確認を持つ。([Ghostty][1])

### 11.10 最後のpaneで `Cmd+W`

```text
if group.paneTree.leafCount > 1:
  close_surface normally
else:
  close_group confirmation
```

最後のpaneを閉じることは、実質groupを閉じること。

## 12. 復元仕様

### 12.1 保存するもの

```text
- canonicalGroupTree
- groups
- group names
- group paneTree
- focusedGroup
- focusedSurface per group
```

### 12.2 保存しないもの

```text
- hiddenGroupIDs
- zoomedGroup
```

復元時はすべて visible、非zoom状態に戻す。

```swift
func restoreWorkspace(_ saved: SavedWorkspaceState) -> WorkspaceState {
    WorkspaceState(
        version: saved.version,
        canonicalGroupTree: saved.canonicalGroupTree,
        groups: saved.groups,
        hiddenGroupIDs: [],
        focusedGroup: saved.focusedGroup.validIn(saved.groups)
            ? saved.focusedGroup
            : saved.canonicalGroupTree.firstLeaf?.id,
        zoomedGroup: nil
    )
}
```

### 12.3 起動時pane復元

MVPでは各paneは新規 shell として復元する。

```text
Before quit:
  group / pane layout 保存

After launch:
  同じ group / pane layout で shell を起動
```

live process / scrollback / PTY状態は復元しない。

## 13. effectiveVisibleGroupTree

`effectiveVisibleGroupTree` は描画・focus・visible hit testing 用の派生状態。

```swift
var effectiveVisibleGroupTree: SplitTree<GroupRef>? {
    if let zoomedGroup {
        guard !hiddenGroupIDs.contains(zoomedGroup) else { return nil }
        return canonicalGroupTree.treeContainingOnly(zoomedGroup)
    }

    return canonicalGroupTree.pruningLeaves { ref in
        hiddenGroupIDs.contains(ref.id)
    }
}
```

`canonicalGroupTree` は source of truth。
`effectiveVisibleGroupTree` を永続化してはいけない。

## 14. 不変条件

必ずテストする。

```text
1. canonicalGroupTree の leaf は必ず groups に存在する
2. groups に存在しない GroupID は canonicalGroupTree に存在しない
3. hiddenGroupIDs は groups.keys の部分集合
4. hiddenGroupIDs は永続復元しない
5. zoomedGroup は visible group のみ
6. focusedGroup は visible group のみ
7. hide_group は process を終了しない
8. close_group は process を終了する
9. Cmd+D は focused group 内の paneTree だけを変更する
10. new_group_split は canonicalGroupTree を変更し、新group内に初期paneを1つ作る
11. new_group_split 後は新groupの初期paneにfocusする
12. goto_group 後は対象groupの last focused pane にfocusする
13. group label は overlay であり、terminal layout を押し下げない
14. hidden shelf は workspace overlay であり、group overlay ではない
15. group zoom と pane zoom は外側から内側へ適用する
16. hidden group は focus / resize / equalize の直接対象にならない
17. 最後の visible group は hide できない
18. 最後の pane で close_surface した場合は close_group confirmation に昇格する
```

## 15. 実装フェーズ

### Phase 0: 既存挙動を1グループに包む

目的: 見た目と操作を一切変えず、内部だけ二層化する。

```text
Before:
  tab.surfaceTree: SplitTree<SurfaceView>

After:
  workspace.canonicalGroupTree = leaf(defaultGroup)
  groups[defaultGroup].paneTree = old surfaceTree
```

成功条件:

```text
- Cmd+D が従来通り動く
- Cmd+Shift+D が従来通り動く
- goto_split が従来通り動く
- resize_split が従来通り動く
- toggle_split_zoom が従来通り動く
- close_surface が従来通り動く
```

### Phase 1: `GroupSplitTreeView`

`SplitTree<GroupRef>` を描画できるようにする。

```text
TerminalWorkspaceView
  -> GroupSplitTreeView
     -> GroupView
        -> TerminalSplitTreeView
```

成功条件:

```text
- 1 group でも既存と同じ表示
- 2 group でもそれぞれの paneTree が独立表示
- SwiftUI identity 破綻がない
```

### Phase 2: `new_group_split`

```text
Cmd+Opt+D
Cmd+Opt+Shift+D
```

成功条件:

```text
- 新groupがランダム名で作成される
- 新group内に初期paneが1つ作られる
- focusが新group paneへ移る
- Cmd+D は新group内だけを分割する
```

### Phase 3: label / rename

```text
- group label overlay
- focused強調 / unfocused薄表示
- double click inline rename
- rename_group prompt
```

成功条件:

```text
- label が terminal layout を押し下げない
- rename が保存される
- 復元後も名前が残る
```

### Phase 4: `goto_group` / `resize_group` / `equalize_groups`

成功条件:

```text
- 方向移動できる
- 移動先groupのlast focused paneに戻る
- group境界をresizeできる
- group境界double-clickまたはactionでequalizeできる
```

### Phase 5: zoom / hide / shelf

成功条件:

```text
- toggle_group_zoom が group単位で動く
- zoom中 Cmd+D は group内splitになる
- zoom中 new_group_split は zoom解除して隣にgroup作成
- hide_group は process を殺さない
- hidden shelf が右上に出る
- pill click で即visibleに戻る
```

### Phase 6: restore

成功条件:

```text
- group layout が復元される
- group names が復元される
- pane layout が復元される
- hidden 状態は復元されず全group visible
- zoom 状態は復元されず非zoom
```

## 16. 推奨ファイル構成

```text
macos/Sources/Features/Groups/
  GroupID.swift
  GroupState.swift
  WorkspaceState.swift
  WorkspaceModel.swift
  GroupNameGenerator.swift
  GroupActions.swift
  GroupSplitTreeView.swift
  GroupView.swift
  GroupLabel.swift
  HiddenGroupShelf.swift
  CloseGroupConfirmation.swift
```

既存 split と密接に関わるため、最終的には `Features/Splits` 配下に統合してもよい。
ただし初期実装では `Features/Groups` として分離した方が差分を追いやすい。

## 17. Action parser 追加方針

既存 action enum に追加する。

```swift
enum Action {
    case newSplit(NewSplitDirection)
    case gotoSplit(FocusDirection)
    case resizeSplit(Direction, Int)
    case equalizeSplits
    case toggleSplitZoom

    case newGroupSplit(NewSplitDirection)
    case gotoGroup(FocusDirection)
    case resizeGroup(Direction, Int)
    case equalizeGroups
    case toggleGroupZoom
    case hideGroup
    case showGroup(String?)
    case renameGroup
    case setGroupTitle(String)
    case closeGroup
}
```

config syntax:

```text
keybind = cmd+opt+d=new_group_split:right
keybind = cmd+opt+shift+d=new_group_split:down
keybind = cmd+ctrl+opt+left=goto_group:left
keybind = cmd+ctrl+opt+shift+left=resize_group:left,10
keybind = cmd+opt+enter=toggle_group_zoom
keybind = cmd+opt+h=hide_group
keybind = cmd+opt+r=rename_group
```

## 18. エッジケース

### 18.1 hidden group がある状態で close_group

hidden中の group を shelf menu から close する機能はMVPでは不要。
MVPでは visible focused group のみ close 対象。

### 18.2 focused group を hide

```text
1. 対象を hiddenGroupIDs に追加
2. nearest visible group にfocus
3. visible group が残らないなら hide を拒否
```

### 18.3 zoomed group を hide

```text
1. zoom解除
2. hide
3. nearest visible group にfocus
```

### 18.4 zoomed group 中の `new_group_split`

```text
1. base = zoomedGroup
2. zoom解除
3. base の隣に new group
4. new group にfocus
```

### 18.5 close_group 後に group が0個になる

原則、最後のgroupの close は window/tab close と同等に扱う。
つまり既存 `close_surface` の window/tab close semantics に寄せる。

MVPでは:

```text
最後のgroupをclose:
  Close Group? confirmation
  実行後、tab/window close に委譲
```

## 19. テスト計画

### 19.1 Unit tests

```text
- random group name uniqueness
- hide/show does not mutate canonicalGroupTree
- close_group mutates canonicalGroupTree and groups
- focusedGroup never points to hidden group
- zoomedGroup never points to hidden group
- restore clears hiddenGroupIDs
- restore clears zoomedGroup
- new_group_split creates group + initial pane
- Cmd+D changes only focused group paneTree
- goto_group restores target focusedSurface
```

### 19.2 Layout tests

```text
- group split right
- group split down
- nested group split
- hide middle group
- show hidden group
- resize with hidden group
- equalize without hidden group
- equalize with hidden group
- zoom group with inner split zoom
```

### 19.3 UI tests

```text
- label visible on all groups
- focused label emphasized
- unfocused label dimmed
- label double-click starts rename
- shelf appears only with hidden groups
- shelf pill click immediately shows group
- close_group dialog has only Cancel / Close Group
```

## 20. 最終MVP仕様サマリ

```text
既存:
  Cmd+D              pane split right
  Cmd+Shift+D        pane split down

追加:
  Cmd+Opt+D          group split right
  Cmd+Opt+Shift+D    group split down

group UI:
  左上label
  focus時だけ強調
  double-click rename
  command prompt rename

hidden UI:
  右上 fixed shelf
  hidden: [name] [name]
  pill clickで即show

zoom:
  group単位
  zoom中 Cmd+D はgroup内pane split
  zoom中 new_group_split はzoom解除して隣に作成

focus:
  goto_group方向移動
  移動先groupのlast focused paneに戻る

resize:
  group境界をresize
  equalize_groupsあり

close:
  最後のpaneでCmd+W -> Close Group?
  [Cancel] [Close Group]
  Hide Insteadなし

restore:
  layout/name/pane layout復元
  hiddenは復元しない
  zoomは復元しない
  起動時は全group visible
```

この仕様の核は、**`canonicalGroupTree` を唯一のグループ配置source of truthにし、hide/zoomを派生表示状態として扱うこと**です。これにより、グループは第一級レイアウト単位になりつつ、既存のペイン分割・surface lifetime・GhosttyのSplitTree設計を壊さずに拡張できます。

[1]: https://ghostty.org/docs/config/keybind/reference "Action Reference - Keybindings"
[2]: https://rexbrahh.github.io/ghostty-knowledge-base/reference/macos/Sources/Features/Splits/SplitTree.swift/ "macos/Sources/Features/Splits/SplitTree.swift | Ghostty Knowledge Base"
[3]: https://github.com/ghostty-org/ghostty/blob/main/macos/Sources/Features/Splits/TerminalSplitTreeView.swift "ghostty/macos/Sources/Features/Splits/TerminalSplitTreeView.swift at main · ghostty-org/ghostty · GitHub"
