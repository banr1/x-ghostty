# X-Ghostty 階層的ペイン仕様書

## 1. 目的

Ghostty の既存 split pane の上位に、**プロジェクトレイヤー**を追加する。

既存のペイン分割は「同一プロジェクト内の terminal surface 分割」として維持し、新たに「プロジェクト単位の分割・移動・ズーム・非表示・復元」を実装する。

```text
Window（アプリ唯一のウィンドウ）
└─ ProjectTree
   ├─ Project: calm-river
   │  └─ PaneTree
   │     ├─ pane
   │     └─ pane
   └─ Project: copper-owl
      └─ PaneTree
         ├─ pane
         └─ pane
```

Ghostty 既存の action model には `new_split`, `goto_split`, `toggle_split_zoom`, `resize_split`, `equalize_splits`, `close_surface` があり、`new_split` は方向指定で split を作り、`toggle_split_zoom` は現在 split をウィンドウ全体に拡大し、`resize_split` と `equalize_splits` も split 単位で定義されています。したがって、本機能は既存 action を上書きせず、**プロジェクト版 action を並列追加する**設計にする。([Ghostty][1])

## 2. 非目的

初期実装では以下をやらない。

```text
- Linux / GTK 対応（本 fork は macOS 専用。GTK apprt は削除済みで、
  そもそも対応対象として存在しない）
- tmux / zellij 互換
- floating pane
- live session 完全復元
- scrollback / PTY 状態の永続復元
- drag & drop によるプロジェクト移動
- プロジェクト入れ替え UI
- hidden 状態の永続化
- zoom 状態の永続化
```

MVPでは、**プロジェクト作成・名前表示・rename・focus移動・resize・equalize・zoom・hide/show・layout復元**までを対象とする。

## 3. 基本設計

採用する構造は **二層SplitTree**。

```swift
WorkspaceState
  canonicalProjectTree: SplitTree<ProjectRef>
  projects: [ProjectID: ProjectState]
  hiddenProjectIDs: Set<ProjectID>
  focusedProject: ProjectID?
  zoomedProject: ProjectID?
```

各 `ProjectState` は、内部に通常のペイン分割木を持つ。

```swift
ProjectState
  id: ProjectID
  name: String
  paneTree: SplitTree<SurfaceRef>
  focusedSurface: SurfaceID?
```

Ghostty macOS 側の `SplitTree.swift` は、leaf/split 構造、zoom tracking、codable path、focus traversal、spatial navigation、insert/remove/replace/equalize/resize semantics を担う split model として整理されているため、プロジェクト層でも `SplitTree<ProjectRef>` を使い、既存の抽象を最大限再利用する。([Rexbrahh][2])

## 4. 最重要設計判断

### 4.1 `canonicalProjectTree` と `effectiveVisibleProjectTree` を分ける

プロジェクトの配置は常に `canonicalProjectTree` に保持する。
canonical tree の leaf 集合 = visible project の集合であり、
hidden project は leaf を持たず、`projects` の `ProjectState` としてのみ生存する。

```text
canonicalProjectTree:
  calm-river | server

hiddenProjectIDs:
  logs, agent        ← projects には残るが leaf は持たない

effectiveVisibleProjectTree:
  canonicalProjectTree に zoom を適用した派生tree
```

`hide_project` は対象の leaf を canonical tree から削除する(process は生存)。
`show_project` は末尾 leaf を左右分割して右側に再接続する(位置は復元しない)。
`close_project` だけが `projects` からも削除して process を終了する。

これにより、非表示プロジェクトを元の場所に戻すための path 復元ロジックが不要になり、
hide 中は残りの visible project がスペースを回収できる。

### 4.2 プロジェクトは最上位レイアウト単位

`Cmd+D` は常に focused project 内の `paneTree` だけを分割する。
プロジェクト境界は越えない。

```text
Cmd+D:
  focusedProject.paneTree を split

Cmd+Opt+D:
  canonicalProjectTree を split して新 project を作る
```

### 4.3 terminal surface の lifetime と layout tree を分離する

`SplitTree` は layout を表す。
PTY / surface / renderer / scrollback の実体は registry 側で保持し、tree 変形に伴って安易に再生成しない。

Ghostty の `TerminalSplitTreeView` は `SplitTree<Ghostty.SurfaceView>` を受け取り、tree の `zoomed ?? root` を描画対象にしており、SwiftUI の structural identity 問題を避けるために `.id(node.structuralIdentity)` を使っています。この既存設計に合わせ、プロジェクト層も view identity を慎重に扱う。([GitHub][3])

## 5. データモデル

### 5.1 ID 型

```swift
struct ProjectID: Codable, Hashable, Identifiable {
    let rawValue: UUID
    var id: UUID { rawValue }
}

struct SurfaceID: Codable, Hashable, Identifiable {
    let rawValue: UUID
    var id: UUID { rawValue }
}

struct ProjectRef: Codable, Hashable, Identifiable {
    let id: ProjectID
}

struct SurfaceRef: Codable, Hashable, Identifiable {
    let id: SurfaceID
}
```

### 5.2 WorkspaceState

```swift
struct WorkspaceState: Codable {
    var version: Int = 1

    var canonicalProjectTree: SplitTree<ProjectRef>
    var projects: [ProjectID: ProjectState]

    // runtime-only
    var hiddenProjectIDs: Set<ProjectID> = []
    var focusedProject: ProjectID?
    var zoomedProject: ProjectID?
}
```

`hiddenProjectIDs` と `zoomedProject` は原則 runtime-only。
保存してもよいが、restore時には破棄する。

### 5.3 ProjectState

```swift
struct ProjectState: Codable, Identifiable {
    let id: ProjectID
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
  ├─ ProjectSplitTreeView
  │   └─ ProjectView (VStack)
  │       ├─ ProjectLabel header band
  │       └─ TerminalSplitTreeView
  └─ HiddenProjectShelf overlay
```

### 6.2 TerminalWorkspaceView

```swift
struct TerminalWorkspaceView: View {
    @ObservedObject var workspace: WorkspaceModel

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let tree = workspace.effectiveVisibleProjectTree {
                ProjectSplitTreeView(
                    tree: tree,
                    focusedProject: workspace.focusedProject,
                    action: workspace.handleProjectOperation
                )
            }

            HiddenProjectShelf(
                hiddenProjects: workspace.hiddenProjectsInDisplayOrder,
                onShow: { workspace.showProject($0) }
            )
        }
    }
}
```

### 6.3 ProjectView

Project label は各 project 上部の **ヘッダー帯**（VStack の上段）として表示し、terminal
描画領域をその高さぶん押し下げる。overlay ではない。帯はターミナル配色に馴染ませる
（背景色フィル + split-divider 色のヘアライン）。

```swift
struct ProjectView: View {
    let project: ProjectState
    let isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ProjectLabel(
                title: project.name,
                isFocused: isFocused
            )

            TerminalSplitTreeView(
                tree: project.paneTree,
                action: handlePaneOperation
            )
        }
    }
}
```

## 7. UI 仕様

### 7.1 プロジェクトラベル

各 project 上部のヘッダー帯に、序数と名前を左寄せで表示する。帯はターミナルに馴染ませる
（ターミナル背景色フィル + 下端に split-divider 色のヘアライン、monospace フォント）。

```text
┌────────────────────────────┐
│ 3. calm-river              │  ← ヘッダー帯（序数 + 名前、bg 色 + 下罫線）
├────────────────────────────┤
│ terminal panes             │
└────────────────────────────┘
```

ラベル表示形式は `"{ordinal}. {name}"` 。序数は表示専用（1～9、canonical tree の葉走査順で動的決定）で、
`ProjectState.name` には保存されない。inline rename 時は裸の名前を編集し、`show_project:<name>` の引数も裸の名前とマッチする。
zoom 中のプロジェクトは canonical 序数をそのまま表示する。

表示ルール（material ピル等の浮いた装飾は用いず、フラットに馴染ませる）:

```text
focused project:
  text opacity 1.0
  weight やや強め（medium）

unfocused project:
  text opacity 0.35〜0.5（weight regular）
  視認はできるが主張しすぎない

帯の背景:
  両状態とも不透明（テキストのみ減光する）
```

操作:

```text
single click label:
  その project に focus

double click label:
  inline rename

click note glyph (帯の右端):
  その project のノート編集オーバーレイを開く(§21.2、focus は変えない)

rename_project action:
  focused project の名前を prompt で変更
```

### 7.2 Hidden Project Shelf

非表示projectは右上固定の shelf に表示する。

```text
┌─ 1. main ────┬─ 2. server ─── hidden: [logs] [agent] ┐
│              │                                        │
└──────────────┴────────────────────────────────────────┘
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

hidden shelf の pill は裸の名前を表示する（序数なし）。

操作:

```text
pill click:
  即 show_project（ただし visible が既に 9 個の場合は no-op・toast/beep なし）

+N click:
  hidden project menu を開く
```

Hidden shelf は `TerminalWorkspaceView` の overlay。
個別 `ProjectView` の責務ではない。

### 7.3 プロジェクト番号（1～9）と表示上限

visible project は最大 9 個まで。`WorkspaceState.maxVisibleProjects = 9` として実装。

#### 動的序数

visible project は canonical tree の **葉走査順序**（in-order、前後 focus 移動と同じ順）で
1～N（N = visible count）の序数を自動付与する。序数は display-only で内部保持しない。

枚数変化時（hide / close / show / move_project）、序数は自動的に再計算・再配置される。

```text
canon: [project-A | project-B | project-C]  (3 visible)

序数: 1. project-A | 2. project-B | 3. project-C

project-B を hide:

canon: [project-A | project-C]  (2 visible)

序数: 1. project-A | 2. project-C  ← 自動 re-pack
```

zoom 中のプロジェクトは canonical tree 上の序数をそのまま表示する（zoom は派生表示で canonical 不変のため）。

```text
canon: [project-A | project-B | project-C]  (3 visible)
zoom: project-B

表示: 2. project-B  (canonical 上の序数 2)
```

#### 表示上限 9 と no-op 挙動

visible project が既に 9 個のとき:

- `new_project_split` ... quietly no-op（モデル・UI 変化なし）
- `show_project`（shelf pill click と `show_project:<name>` action 両方） ... quietly no-op（pill は表示されたまま）
- `goto_project` index form（`goto_project:1`～`goto_project:9`）... 無効な index は no-op、performability gate あり
- `goto_project` directional form ... 変わらず動作（方向移動だけでは上限に到達しない）

performability gate の扱い：

- `show_project` ... 上限到達時（または対象が hidden でないとき）は performable = false で
  keybind を消費しない
- `goto_project` index form ... 対象 index が解決できない・focused と同じ
  （zoom 中は zoomed project 自身と同じ）とき performable = false で keybind を消費しない
- `new_project_split` ... performability 配線が無いため keybind は消費されるが、
  controller/model 側の gate（`canAddVisibleProject`）で静かに no-op

## 8. プロジェクト名生成

新規project名は固定 word list から `adjective-noun` 形式でランダム生成する。

```swift
enum ProjectNameGenerator {
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

        var n = existing.count + 1
        while existing.contains("project-\(n)") { n += 1 }
        return "project-\(n)"
    }
}
```

生成は作成時のみ。
復元時に再生成してはいけない。
名前は `ProjectState.name` に保存する。

## 9. Action 仕様

Ghostty既存の action naming に合わせ、`focus_project` ではなく `goto_project` を推奨する。既存の `goto_split` は方向または previous/next で split focus を移す action として定義されているため、プロジェクト版も同じ語彙に寄せる。([Ghostty][1])

### 9.1 追加action一覧

```text
new_project_split:right
new_project_split:down
new_project_split:left
new_project_split:up
new_project_split:auto

goto_project:right
goto_project:down
goto_project:left
goto_project:up
goto_project:next
goto_project:previous
goto_project:1
goto_project:2
goto_project:3
goto_project:4
goto_project:5
goto_project:6
goto_project:7
goto_project:8
goto_project:9

resize_project:right,10
resize_project:left,10
resize_project:up,10
resize_project:down,10

equalize_projects

toggle_project_zoom

hide_project
show_project:<project-id-or-name>

rename_project
set_project_title:<name>

edit_project_note
toggle_note_overview

set_primary

sort_projects_by_priority
sort_projects_by_deadline

choose_project_layout

close_project
```

### 9.2 既存actionとの対応

```text
new_split          -> new_project_split
goto_split         -> goto_project
resize_split       -> resize_project
equalize_splits    -> equalize_projects
toggle_split_zoom  -> toggle_project_zoom
close_surface      -> close_project
```

## 10. デフォルトキー割り当て

### 10.1 ペイン分割

既存維持。

```text
Cmd+D                 -> new_split:right
Cmd+Shift+D           -> new_split:down
```

### 10.2 プロジェクト分割

```text
Cmd+Opt+D             -> new_project_split:right
Cmd+Opt+Shift+D       -> new_project_split:down
```

### 10.3 プロジェクト移動

方向移動:

```text
Cmd+Ctrl+Opt+Left     -> goto_project:left
Cmd+Ctrl+Opt+Right    -> goto_project:right
Cmd+Ctrl+Opt+Up       -> goto_project:up
Cmd+Ctrl+Opt+Down     -> goto_project:down
```

序数ジャンプ:

```text
Cmd+1                 -> goto_project:1
Cmd+2                 -> goto_project:2
Cmd+3                 -> goto_project:3
Cmd+4                 -> goto_project:4
Cmd+5                 -> goto_project:5
Cmd+6                 -> goto_project:6
Cmd+7                 -> goto_project:7
Cmd+8                 -> goto_project:8
Cmd+9                 -> goto_project:9
```

Cmd+1～9 は physical `digit_1`～`digit_9` と unicode `1`～`9` の両方に登録し
（AZERTY 等のレイアウト対策）、`goto_project:1`～`goto_project:9` に performable 付きでバインドする。
本 fork にタブは存在せず、上流の `goto_tab` / `last_tab` は core ごと削除済みなので衝突しない。

### 10.4 プロジェクトリサイズ

```text
Cmd+Ctrl+Opt+Shift+Left     -> resize_project:left,10
Cmd+Ctrl+Opt+Shift+Right    -> resize_project:right,10
Cmd+Ctrl+Opt+Shift+Up       -> resize_project:up,10
Cmd+Ctrl+Opt+Shift+Down     -> resize_project:down,10
```

### 10.5 その他

```text
Cmd+Opt+Enter         -> toggle_project_zoom
Cmd+Opt+H             -> hide_project
Cmd+Opt+R             -> rename_project
Cmd+N                 -> edit_project_note
Cmd+Opt+N             -> toggle_note_overview
Cmd+P                 -> set_primary
Cmd+S                 -> sort_projects_by_priority
Cmd+Shift+S           -> sort_projects_by_deadline
Cmd+L                 -> choose_project_layout
```

`Cmd+Opt+Enter` は既存 split zoom と衝突しない形で「上位レイヤーのzoom」として覚えやすい。
ノート系 2 action の仕様は §21。`Cmd+N` / `Cmd+Opt+N` は config デフォルトにも
メニュー xib にも既存割り当てがないことを確認済み。
`set_primary`(§22.4)は zoom 中に focused ペインをプライマリーへ指定する。素の
`Cmd+P` に既存割り当てはない(コマンドパレットは `Cmd+Shift+P`)。
ソート 2 action の仕様は §24.4。素の `Cmd+S` / `Cmd+Shift+S` にも既存割り当てが
ないことを確認済み(上流はどちらの chord も未使用)。
`hide_project` は §25 の hide 選択画面を開く(即時 hide ではない。単一 hide の
モデルプリミティブは §11.7 のまま残る)。`choose_project_layout`(§26.2)は
レイアウト選択オーバーレイを開く。素の `Cmd+L` に既存割り当てはない(config
デフォルトにもメニュー key equivalent にも `l` の super chord は無いことを
確認済み)。
また、上流デフォルトの `cmd+enter=toggle_fullscreen` は解除済み:`Cmd+Enter` は
ノート編集オーバーレイの保存確定(§21.2)に予約する。fullscreen は
`Ctrl+Cmd+F`・Window メニュー・緑ボタンから引き続き到達できる。

## 11. 状態遷移仕様

### 11.1 `new_project_split`

表示上限到達時は no-op（§7.3）。

挙動:

```text
1. visible project 数が既に 9 個の場合は no-op（§7.3 の上限 gate）
2. focusedProject を基準projectにする
3. zoomedProject がある場合は、まず zoom を解除する
4. 新規 ProjectState を作る
5. 新規 project 内に初期paneを1つ作る
6. canonicalProjectTree に ProjectRef を挿入する
7. focus を新project内の初期paneへ移す
```

ズーム中に実行した場合:

```text
Before:
  zoomedProject = server

new_project_split:right

After:
  zoomedProject = nil
  server の右に新project
  focus = 新projectの初期pane
```

### 11.2 `Cmd+D`

常に focused project 内の `paneTree` のみを分割する。

```text
focusedProject = server

Cmd+D:
  projects[server].paneTree.insert(...)
```

プロジェクトズーム中も同じ。
ズーム中project内でpane splitされる。

### 11.3 `goto_project`

#### 方向移動形式（`goto_project:right` 等）

方向移動は `effectiveVisibleProjectTree` に対して行う。

```swift
func gotoProject(_ direction: FocusDirection) {
    guard zoomedProject == nil else { return }
    guard let visibleTree = effectiveVisibleProjectTree else { return }

    let next = visibleTree.focusTarget(
        from: focusedProject,
        direction: direction
    )

    if let next {
        focusedProject = next
        focusLastPane(in: next)
    }
}
```

移動先projectでは、最後にfocusしていたpaneへ戻す。

```text
goto_project:right:
  project focus を移す
  targetProject.focusedSurface を復元
```

hidden project は focus 対象にしない。
zoom中の `goto_project` 方向移動は no-op でよい。

#### 序数ジャンプ形式（`goto_project:1`～`goto_project:9`）

N 番目の visible project にジャンプする（traversal order の序数 1～9）。

```swift
func gotoProject(index: UInt8) {
    // index が resolveしないか focusedProject と同じならno-op
    guard let target = visibleProjectID(ordinal: index),
          target != focusedProject
    else { return }

    zoomedProject = nil  // zoom を解除してからジャンプ
    focusedProject = target
    focusLastPane(in: target)
}
```

**zoom中の特別ルール**: zoom 中に index form を実行するとまず **zoom を解除してからジャンプ** する。
ただし zoomed project 自身の序数を指定した場合（e.g. zoomed = 2. server、Cmd+2 押下）は、
no-op で zoom は保持される。

```text
Before:
  visible: [1. calm-river | 2. server | 3. logs]
  focused: 2. server
  zoomed: 2. server

Cmd+3 (goto_project:3):
  zoom解除 → focus 移動 → last pane focus

  After:
    focused: 3. logs
    zoomed: nil

Cmd+2 (goto_project:2,自 project):
  no-op、zoom 保持

  Before の状態のまま
```

hidden project は jump 対象にならない（序数は visible only）。
無効な index（0、10+、目標が hidden 等）は no-op。

### 11.4 `resize_project`

`resize_project` は `effectiveVisibleProjectTree` の見た目上の隣接関係を使うが、ratio変更は `canonicalProjectTree` に適用する。

```text
1. visible tree で focusedProject の隣接projectを探す
2. focusedProject と neighbor の canonical tree 上の LCA split を探す
3. その split ratio を変更する
```

hidden project がいる状態でも、canonical tree を直接正しく更新する。

```swift
func resizeProject(_ direction: Direction, amount: CGFloat) {
    guard zoomedProject == nil else { return }
    guard let focused = focusedProject else { return }
    guard let visibleTree = effectiveVisibleProjectTree else { return }

    guard let neighbor = visibleTree.spatialNeighbor(
        from: focused,
        direction: direction
    ) else { return }

    guard let splitPath = canonicalProjectTree.lowestCommonSplitPath(
        between: focused,
        and: neighbor,
        matchingResizeDirection: direction
    ) else { return }

    canonicalProjectTree = canonicalProjectTree.adjustRatio(
        at: splitPath,
        direction: direction,
        amount: amount
    )
}
```

### 11.5 `equalize_projects`

`equalize_projects` は visible project のレイアウトを均等化する。

hidden project は canonical tree に leaf を持たない(§11.7)ため、
`canonicalProjectTree.equalized()` をそのまま保存すればよい。
均等化されるのは visible project 間の split ratio だけである。

```swift
func equalizeProjects() -> Bool {
    guard canonicalProjectTree.isSplit else { return false }
    canonicalProjectTree = canonicalProjectTree.equalized()
    return true
}
```

project が1つ以下で split が存在しない場合は no-op。
hidden project の有無で実行を拒否してはいけない。

### 11.6 `toggle_project_zoom`

```text
if zoomedProject == focusedProject:
  zoomedProject = nil
else:
  zoomedProject = focusedProject
```

描画時は:

```swift
if let zoomedProject {
    effectiveVisibleProjectTree = canonicalProjectTree.subtreeContainingOnly(zoomedProject)
} else {
    effectiveVisibleProjectTree = canonicalProjectTree.pruning(hiddenProjectIDs)
}
```

project zoom と inner split zoom は共存可能。

描画順序:

```text
1. project zoom を適用
2. project 内 paneTree の split zoom を適用
```

つまり外側から内側へ適用する。

### 11.7 `hide_project`

`hide_project` action(既定 `Cmd+Opt+H`)自体は §25 の hide 選択画面を開く。
本節が定める単一プロジェクト hide はモデルのプリミティブ
(`hideFocusedProject`)として残り、show/undo フローと §25 の一括 hide が
この意味論を共有する。

```text
1. focus の移動先を hide 前の canonical tree 上で解決(nearest leaf)
2. focusedProject の leaf を canonicalProjectTree から削除
   → 残りの visible project がスペースを回収する
3. focusedProject を hiddenProjectIDs に追加(shelf の source of truth)
4. process / PTY / surface は生存(ProjectState は projects に残る)
5. zoomedProject == hidden target なら zoom解除
6. focus を 1 で解決した neighbor へ移す
7. hidden shelf に pill 表示
```

```swift
func hideProject(_ id: ProjectID) {
    guard projects[id] != nil else { return }
    // 最後の visible project は hide できない
    guard let neighbor = canonicalProjectTree.nearestLeaf(to: id) else { return }

    canonicalProjectTree = canonicalProjectTree.removing(.leaf(view: ProjectRef(id: id)))
    hiddenProjectIDs.insert(id)

    if zoomedProject == id {
        zoomedProject = nil
    }

    focusedProject = neighbor
}
```

全projectをhiddenにしようとした場合:

```text
最後の visible project は hide できない
```

理由: workspace が空になると操作・復帰UIが不安定になるため。

### 11.8 `show_project`

表示上限到達時は no-op（§7.3）。

```text
1. visible project 数が既に 9 個の場合は no-op（pill は表示のまま、toast/beep なし）
2. hiddenProjectIDs から除外
3. 末尾プロジェクト(走査順の最後の leaf)を 50/50 で左右分割し、
   その右側に leaf を再接続
4. zoomedProject を解除
5. focus をそのprojectへ移す
6. project内では最後にfocusしていたpaneへ戻す
```

```swift
func showProject(_ id: ProjectID) {
    guard !hiddenProjectIDs.contains(id) else { return }
    guard visibleProjectCount < 9 else { return }  // cap gate

    hiddenProjectIDs.remove(id)
    canonicalProjectTree = canonicalProjectTree.appendingAtTrailingLeaf(ProjectRef(id: id))
    zoomedProject = nil
    focusedProject = id
    focusLastPane(in: id)
}
```

hide が leaf を削除しているため、show は元の位置を復元しない。
再表示された project は末尾プロジェクトのスペースを半分もらうだけで、
他の visible project のサイズと split ratio は一切変わらない。
空 tree への再接続は単一 leaf になる。

### 11.9 `close_project`

破壊的操作。必ず確認ダイアログを出す。

```text
Close Project “server”?

This will close 4 panes and terminate their processes.

[Cancel] [Close Project]
```

`Hide Instead` は入れない。

挙動:

```text
1. confirmation
2. project内の全surfaceを close
3. canonicalProjectTree から ProjectRef を削除
4. projects から削除
5. hiddenProjectIDs から削除
6. zoomedProject が対象なら解除
7. focus を nearest visible project に移す
8. visible project が残らない場合は最古の hidden project を
   §11.8 と同じ末尾分割で再表示してから focus する(§14.6)
```

既存 `close_surface` は close confirmation popup を出し得る action として定義されているため、`close_project` も同じく破壊的操作として確認を持つ。([Ghostty][1])

### 11.10 最後のpaneで `Cmd+W`

```text
if project.paneTree.leafCount > 1:
  close_surface normally
else if projects.count > 1:
  close_project confirmation
else:
  close_surface normally  (唯一の project なので window close → app 終了, §18.5)
```

最後のpaneを閉じることは、実質projectを閉じること。project が複数ある場合のみ
close_project confirmation に昇格する(実装: `BaseTerminalController` の
close_surface 経路)。

## 12. 復元仕様

### 12.1 保存するもの

```text
- canonicalProjectTree
- projects
- project names
- project paneTree
- focusedProject
- focusedSurface per project
```

### 12.2 保存しないもの

```text
- hiddenProjectIDs
- zoomedProject
```

復元時はすべて visible、非zoom状態に戻す。ただし §7.3 の表示上限 9 を適用する。

### 12.3 起動時pane復元

MVPでは各paneは新規 shell として復元する。

```text
Before quit:
  project / pane layout 保存

After launch:
  同じ project / pane layout で shell を起動
```

live process / scrollback / PTY状態は復元しない。

### 12.4 表示上限による pruning

保存時の canonical tree に 9 個を超える leaf がある場合は、復元時に **先頭 9 個のみを visible のまま、
超過分を hiddenProjectIDs に移す**（alive・shelf に表示されるが leaf なし）。

保存時に hidden だった project は canonical tree に leaf を持たないまま
`projects` に残っている(§11.7)。復元時はまず canonical 上限 9 個の枠に収めてから、
orphaned project（leaf なし・creation order 順）を末尾に再接続する。枠内に収まる orphaned のみ
再接続し、超過分は hidden のまま。

```swift
func applyRestoreLayout() -> WorkspaceState {
    var restored = self
    restored.hiddenProjectIDs = []
    restored.zoomedProject = nil

    // canonical が 9 を超える場合は超過分を非表示化
    restored.capVisibleProjects()  // 先頭 9 保持、以降を hiddenProjectIDs へ

    // orphaned（leaf なし）project を末尾から順に再接続（枠内で止める）
    restored.reconcileOrphanedProjects()  // 再接続可能な分のみ connect

    // focusedProject 検証・フォールバック
    let focusValid = restored.focusedProject.map { id in
        restored.projects[id] != nil && restored.canonicalProjectTree.find(id: id) != nil
    } ?? false
    if !focusValid {
        restored.focusedProject = restored.canonicalProjectTree.firstLeaf?.id
    }
    return restored
}
```

## 13. effectiveVisibleProjectTree

`effectiveVisibleProjectTree` は描画・focus・visible hit testing 用の派生状態。

```swift
var effectiveVisibleProjectTree: SplitTree<ProjectRef>? {
    if let zoomedProject {
        guard !hiddenProjectIDs.contains(zoomedProject),
              canonicalProjectTree.find(id: zoomedProject) != nil
        else { return nil }
        return canonicalProjectTree.treeContainingOnly(zoomedProject)
    }

    // hidden project は canonical tree に leaf を持たない(§11.7)ため、
    // この pruning は stale な hiddenProjectIDs に対する防御でしかない。
    return canonicalProjectTree.pruningLeaves { ref in
        hiddenProjectIDs.contains(ref.id)
    }
}
```

`canonicalProjectTree` は source of truth。
`effectiveVisibleProjectTree` を永続化してはいけない。

## 14. 不変条件

必ずテストする。

```text
1. canonicalProjectTree の leaf は必ず projects に存在する
2. projects に存在しない ProjectID は canonicalProjectTree に存在しない
3. hiddenProjectIDs は projects.keys の部分集合であり、hidden project は
   canonicalProjectTree に leaf を持たない(leaf 集合 = visible project 集合)
4. hiddenProjectIDs は永続復元しない
5. zoomedProject は visible project のみ
6. focusedProject は visible project のみ
7. hide_project は process を終了しない
8. close_project は process を終了する
9. Cmd+D は focused project 内の paneTree だけを変更する
10. new_project_split は canonicalProjectTree を変更し、新project内に初期paneを1つ作る
11. new_project_split 後は新projectの初期paneにfocusする
12. goto_project 後は対象projectの last focused pane にfocusする
13. project label はヘッダー帯であり、terminal layout を自身の高さぶん押し下げる
14. hidden shelf は workspace overlay であり、project overlay ではない
15. project zoom と pane zoom は外側から内側へ適用する
16. hidden project は focus / resize / equalize の直接対象にならない
17. 最後の visible project は hide できない
18. project が複数あるとき、最後の pane で close_surface すると close_project
    confirmation に昇格する（唯一の project では通常の close_surface として
    window close → app 終了になる。§11.10, §18.5）
19. visible project 数は常に ≤ 9（§7.3）
20. visible project の序数は canonical tree 葉走査順で 1～visibleCount となり、
    hide/close/show/move 時に自動 re-pack される（表示のみ、保存しない）
21. restore 時は canonical が 9 を超える場合は先頭 9 のみ visible、
    超過分と orphaned project を hiddenProjectIDs に移す（§12.4）
```

## 15. 実装フェーズ

### Phase 0: 既存挙動を1プロジェクトに包む

目的: 見た目と操作を一切変えず、内部だけ二層化する。

```text
Before:
  controller.surfaceTree: SplitTree<SurfaceView>

After:
  workspace.canonicalProjectTree = leaf(defaultProject)
  projects[defaultProject].paneTree = old surfaceTree
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

### Phase 1: `ProjectSplitTreeView`

`SplitTree<ProjectRef>` を描画できるようにする。

```text
TerminalWorkspaceView
  -> ProjectSplitTreeView
     -> ProjectView
        -> TerminalSplitTreeView
```

成功条件:

```text
- 1 project でも既存と同じ表示
- 2 project でもそれぞれの paneTree が独立表示
- SwiftUI identity 破綻がない
```

### Phase 2: `new_project_split`

```text
Cmd+Opt+D
Cmd+Opt+Shift+D
```

成功条件:

```text
- 新projectがランダム名で作成される
- 新project内に初期paneが1つ作られる
- focusが新project paneへ移る
- Cmd+D は新project内だけを分割する
```

### Phase 3: label / rename

```text
- project label ヘッダー帯（§6.3 / §7.1）
- focused強調 / unfocused薄表示
- double click inline rename
- rename_project prompt
```

成功条件:

```text
- label ヘッダー帯が terminal layout を自身の高さぶん押し下げる（§14.13）
- rename が保存される
- 復元後も名前が残る
```

### Phase 4: `goto_project` / `resize_project` / `equalize_projects`

成功条件:

```text
- 方向移動できる
- 移動先projectのlast focused paneに戻る
- project境界をresizeできる
- project境界double-clickまたはactionでequalizeできる
```

### Phase 5: zoom / hide / shelf

成功条件:

```text
- toggle_project_zoom が project単位で動く
- zoom中 Cmd+D は project内splitになる
- zoom中 new_project_split は zoom解除して隣にproject作成
- hide_project は process を殺さない
- hidden shelf が右上に出る
- pill click で即visibleに戻る
```

### Phase 6: restore

成功条件:

```text
- project layout が復元される
- project names が復元される
- pane layout が復元される
- hidden 状態は復元されず全project visible
  （後続変更: 表示上限 9 の cap を適用、超過分は hidden。§12.4）
- zoom 状態は復元されず非zoom
```

## 16. 推奨ファイル構成

```text
macos/Sources/Features/Projects/
  ProjectID.swift
  ProjectState.swift
  WorkspaceState.swift
  WorkspaceModel.swift
  ProjectNameGenerator.swift
  ProjectSplitTreeView.swift
  ProjectView.swift
  ProjectLabel.swift            (ProjectPriorityDeadlineMeta を含む、§24.2)
  HiddenProjectShelf.swift
  TerminalWorkspaceView.swift
  ProjectNoteEditor.swift
  ProjectNoteOverview.swift
  ProjectTerminatedPaneView.swift  (§23.3)
  ProjectHideSelector.swift        (hide 選択画面とレイアウト hide-pick が共用、§25/§26.3)
  ProjectLayout.swift              (登録レイアウト 11 種とスロット計算、§26.1)
  ProjectLayoutSelector.swift      (レイアウト選択オーバーレイ、§26.2)
  ProjectOverlayKeys.swift         (オーバーレイ共有のローカル keyDown モニタ、§21.2/§25)
```

(close 確認ダイアログは専用ファイルではなく `BaseTerminalController` の既存
確認経路を流用する。§23.1)

既存 split と密接に関わるため、最終的には `Features/Splits` 配下に統合してもよい。
ただし初期実装では `Features/Projects` として分離した方が差分を追いやすい。

## 17. Action parser 追加方針

既存 action enum に追加する。

```swift
enum Action {
    case newSplit(NewSplitDirection)
    case gotoSplit(FocusDirection)
    case resizeSplit(Direction, Int)
    case equalizeSplits
    case toggleSplitZoom

    case newProjectSplit(NewSplitDirection)
    case gotoProject(FocusDirection)
    case resizeProject(Direction, Int)
    case equalizeProjects
    case toggleProjectZoom
    case hideProject
    case showProject(String?)
    case renameProject
    case setProjectTitle(String)
    case closeProject
}
```

config syntax:

```text
keybind = cmd+opt+d=new_project_split:right
keybind = cmd+opt+shift+d=new_project_split:down
keybind = cmd+ctrl+opt+left=goto_project:left
keybind = cmd+one=goto_project:1
keybind = cmd+ctrl+opt+shift+left=resize_project:left,10
keybind = cmd+opt+enter=toggle_project_zoom
keybind = cmd+opt+h=hide_project
keybind = cmd+opt+r=rename_project
```

## 18. エッジケース

### 18.1 hidden project がある状態で close_project

hidden中の project を shelf menu から close する機能はMVPでは不要。
MVPでは visible focused project のみ close 対象。

### 18.2 focused project を hide

```text
1. 対象の leaf を canonicalProjectTree から削除し、hiddenProjectIDs に追加
2. nearest project にfocus(削除前の tree 上で解決する)
3. visible project が残らないなら hide を拒否
```

### 18.3 zoomed project を hide

```text
1. zoom解除
2. hide
3. nearest visible project にfocus
```

### 18.4 zoomed project 中の `new_project_split`

```text
1. base = zoomedProject
2. zoom解除
3. base の隣に new project
4. new project にfocus
```

### 18.5 close_project 後に project が0個になる

原則、最後のprojectの close はウィンドウ close と同等に扱う。
本 fork は単一ウィンドウなので、**ウィンドウが閉じる = アプリ終了**である。

実装:

```text
最後のprojectをclose:
  Close Project? confirmation（live process が残っている場合のみ）
  WorkspaceModel.closeFocusedProject() は .closedLast を返し、モデルは変更しない
  controller が空の surfaceTree を replaceSurfaceTree に渡す
  TerminalController の override が closeWindowImmediately() でウィンドウを閉じる
  ウィンドウが閉じると AppDelegate がアプリを終了する
  この経路では undo を登録しない
```

## 19. テスト計画

### 19.1 Unit tests

```text
- random project name uniqueness
- hide/show does not mutate canonicalProjectTree
- close_project mutates canonicalProjectTree and projects
- focusedProject never points to hidden project
- zoomedProject never points to hidden project
- restore clears hiddenProjectIDs
- restore clears zoomedProject
- new_project_split creates project + initial pane
- Cmd+D changes only focused project paneTree
- goto_project restores target focusedSurface
```

### 19.2 Layout tests

```text
- project split right
- project split down
- nested project split
- hide middle project
- show hidden project
- resize with hidden project
- equalize without hidden project
- equalize with hidden project
- zoom project with inner split zoom
```

### 19.3 UI tests

```text
- label visible on all projects
- focused label emphasized
- unfocused label dimmed
- label double-click starts rename
- shelf appears only with hidden projects
- shelf pill click immediately shows project
- close_project dialog has only Cancel / Close Project
```

## 20. 最終MVP仕様サマリ

```text
既存:
  Cmd+D              pane split right
  Cmd+Shift+D        pane split down

追加（プロジェクト分割）:
  Cmd+Opt+D          project split right
  Cmd+Opt+Shift+D    project split down

追加（プロジェクト番号・序数ジャンプ）:
  Cmd+1～9           goto_project:1～9（visible project の序数でジャンプ）
  ※ 本 fork にタブはなく、goto_tab / last_tab は core から削除済み

project UI:
  ヘッダー帯に "{序数}. {名前}" を表示
  序数は表示のみ（canonical tree の葉走査順で動的）
  focus時だけ強調
  double-click rename（裸の名前を編集）
  command prompt rename

hidden UI:
  右上 fixed shelf
  hidden: [name] [name] （bare name、序数なし）
  pill clickで即show（ただし visible が 9 個では no-op）

表示上限:
  visible project 最大 9 個
  9 個で満杯のとき new_project_split / show_project は no-op
  序数は自動的に 1～9 に re-pack（hide/close/show時）

zoom:
  project単位
  zoom中 Cmd+D はproject内pane split
  zoom中 new_project_split はzoom解除して隣に作成
  goto_project:<N> で zoom 解除してジャンプ（自 project は no-op）

focus:
  goto_project方向移動（zoom中は no-op）
  goto_project序数ジャンプ（1～9）
  移動先projectのlast focused paneに戻る

resize:
  project境界をresize
  equalize_projectsあり

close:
  最後のpaneでCmd+W -> Close Project?
  [Cancel] [Close Project]
  Hide Insteadなし
  最後のprojectをcloseするとウィンドウが閉じ、アプリが終了する（§18.5）

restore:
  layout/name/pane layout復元
  canonical が 9 超える場合は先頭 9 のみ visible、超過分を hidden に移す
  hidden は復元しない（runtime-only）
  zoom は復元しない（runtime-only）
  orphaned project は可能な限り再接続（9 cap内）
  focusedProject 無効時は firstLeaf へフォールバック
```

この仕様の核は、**`canonicalProjectTree` を唯一のプロジェクト配置source of truthにし、hide/zoomを派生表示状態として扱うこと**です。これにより、プロジェクトは第一級レイアウト単位になりつつ、既存のペイン分割・surface lifetime・GhosttyのSplitTree設計を壊さずに拡張できます。また、**表示上限 9 と動的序数により、UI の安定性と操作性を両立**させています。

## 21. ノート仕様

プロジェクト(=プロジェクト)ごとに人間が手書きする短いメモを保持する層。
判断ロジック(保持・復元・表示対象)はすべてモデル層に置き、`XGhosttyTests`
から検証する。

### 21.1 データモデル

```swift
// ProjectState に追加
var note: String = ""            // 常に正規化済み
static let maxNoteLines = 10
```

- ノートは**プロジェクトに属する**。ペイン(split)には属さない。
- 正規化 `ProjectState.normalizedNote`: 改行を `\n` に統一し、
  `maxNoteLines`(10 行)を超える行を捨てる。init / `setNote` / decode の
  3 経路すべてで適用されるため、レガシー保存(note キーなし → `""`)や
  改竄された保存(10 行超)も読み込み時に再正規化される。
- 永続化はプロジェクト名と同一経路(workspace state の Codable →
  `invalidateRestorableState`)。再起動後、同じプロジェクトへ復元される。
- `WorkspaceModel.setProjectNote(_:to:)` が唯一の書込み口。正規化後に変化が
  なければ状態を発行しない。

### 21.2 編集オーバーレイ(edit_project_note / Cmd+N)

- focused プロジェクトのノート編集オーバーレイを開く。セッション状態は
  `WorkspaceModel.noteEditingProject`(transient、永続化しない)。
- マウス導線: 各プロジェクトのヘッダー帯右端のノートグリフ(hover で強調)を
  クリックすると、**そのプロジェクト**のノート編集オーバーレイが開く。focused
  でないプロジェクトも直接編集でき、プロジェクト focus は変更しない。rename 編集中の
  帯ではグリフを出さない。一望モード中は捕捉層がマウスを遮断し、モデル側の
  `beginNoteEditing` ガードも no-op にする(§21.3)。
- 複数行 `TextEditor` は 10 行ぶんの高さを確保し、**編集中は常に全文が
  見える**。
- **Cmd+Enter は保存して閉じる**(背景クリックも同じ保存経路)。実装上、
  `TextEditor` がフォーカスを持つ間も届くよう、§21.3 の捕捉層と同じ隠し
  `keyboardShortcut` ボタンで受ける。この chord を空けるため、本 fork は
  上流の `cmd+enter=toggle_fullscreen` デフォルトを解除している(§10.5)。
- **Esc は破棄して閉じる**:開く前の本文が保持され、破棄に確認は挟まない。
- **標準テキスト編集ショートカットが効く**:オーバーレイ表示中、Cmd+A(全
  選択)/ Cmd+C(コピー)/ Cmd+X(切り取り)/ Cmd+V(貼り付け)はエディタに
  対して標準どおり動作する。Edit メニューのキー equivalents は端末 action
  (`copy_to_clipboard` 等)に同期されておりテキストビューへ届かないため、
  オーバーレイの表示期間だけ張られるローカル keyDown モニタ
  (`OverlayKeyDownMonitor`、`ProjectOverlayKeys.swift`)が chord を
  key-equivalent / メニュー判定より前に捕まえ、標準セレクタ
  (`selectAll:`/`copy:`/`cut:`/`paste:`)を focused なテキストビュー
  (エディタ本体、または締切フィールドの field editor)へ直接 perform する。
  当初の隠し `keyboardShortcut` 受け口 + `NSApp.sendAction(to: nil)` 方式は
  実機で `selectAll:`/`copy:` のみ届き `cut:`/`paste:` が不達だったため、
  key-equivalent 経路にも action dispatch にも依存しない方式に置き換えた。
  モニタはオーバーレイと同寿命なので、端末側のコピー/ペースト挙動は
  変わらない。
- **貼り付けで 10 行を超えた場合も保存時に先頭 10 行へ切り詰める**(手入力と
  同じ §21.1 の正規化経路。CRLF / CR の行末は正規化で `\n` に統一されるため、
  ペースト由来の行末でもキャップは回避されない)。
- **優先度・締切コントロール**: `TextEditor` 下の metaRow で優先度と締切を
  設定・変更できる(§24.1)。保存は Cmd+Enter の単一 commit にノートと一括、
  Esc は 3 ドラフト(ノート・優先度・締切)とも破棄する。
- 閉じると(保存・破棄どちらでも)first responder は端末 surface に戻る。
- オーバーレイは編集中のみ描画され、端末領域を恒久的に占有しない。
- 編集対象プロジェクトが消えた場合(undo 復元・全プロジェクト削除)はセッションを
  クリアする。

### 21.3 一望モード(toggle_note_overview / Cmd+Opt+N)

- visible な全プロジェクトの上に、それぞれのノートを同時に読み取り専用
  オーバーレイ表示するトグルモード。状態は
  `WorkspaceModel.noteOverviewActive`(transient、永続化しない)。
- **進入時に zoom を先に解除**してから表示する(`zoomedProject = nil`)。
  `focusedProject` は変更しない。
- **表示対象集合は visible プロジェクトのみ**:
  `noteOverviewProjectIDs == WorkspaceState.visibleProjectIDs`
  (canonical tree の葉 = visible。hidden プロジェクトは含まれない)。
- **閲覧専用**: モード中は `beginNoteEditing*` と focus 移動 3 経路
  (`gotoProjectTarget` / `gotoProjectIndexTarget` / `switchFocusedProject`)が
  すべて no-op。ワークスペース全面の捕捉層がマウス操作も遮断する。
- ノート編集オーバーレイが開いている間のトグルは no-op(編集ドラフトを
  黙って破棄しない)。
- 退出は**再度 Cmd+Opt+N または Esc**。退出時に first responder は端末
  surface に戻る。実装上、モード中は surface が unfocused で keybind 経路が
  効かないため、Esc は捕捉層内の focused field の `onExitCommand`、
  再トグルはデフォルト chord (cmd+opt+n) を再照合する隠し
  `keyboardShortcut` ボタンで受ける(keybind を変更した場合の退出は Esc)。
- **切り詰め表示**: 各プロジェクトのパネルは `lineLimit(maxNoteLines)` +
  末尾切り詰めをプロジェクト境界内のフレームで行い、レイアウトを壊さない。
  全文表示は編集オーバーレイの役割。
- undo 復元(`restoreState`)・全プロジェクト削除はモードを終了させる
  (復元された zoom が「zoom 解除済み」不変条件と矛盾しないように)。

### 21.4 テスト(ProjectNoteTests)

```text
- 正規化: 10 行上限(init / setNote / decode)、改行統一、レガシー decode
- setProjectNote: 保存・上限・未知プロジェクト no-op・クリア
- Codable round trip でノート本文復元
- 編集セッション: begin は focused を対象 / begin(id) は非 focused でも
  開き focus を変えない(ヘッダー帯マウス導線) / end(Cmd+Enter)は保存して
  閉じる / cancel(Esc)は破棄して閉じ開く前の本文を保持 /
  超過ペースト(CRLF 行末含む)は保存時に先頭 10 行へ切り詰め /
  プロジェクト消滅でクリア
- 一望モード: 表示対象 = visible のみ(hidden 除外) / 進入で zoom 解除 /
  focusedProject 不変 / 再トグル・endNoteOverview で退出 /
  モード中はノート編集・focus 移動 3 経路とも no-op /
  編集オーバーレイ表示中のトグルは no-op /
  restoreState・removeAllProjects で終了
```

## 22. プライマリーペイン仕様

プロジェクトごとに常に 1 つだけ存在する代表ペインの層。全体ビュー
(非 zoom)は各プロジェクトのプライマリーペインだけを描画し、一望に適した情報密度を
作る。判断ロジック(既定付与・唯一性・昇格・復元時正規化・全体ビューの表示対象)
はすべてモデル層に置き、`XGhosttyTests` から検証する(§22.7)。

### 22.1 データモデル

```swift
// ProjectState に追加
private(set) var primaryPane: SurfaceID?   // 非空ツリーでは常にちょうど 1 つ
```

- プライマリーは**プロジェクトに属する単一値フラグ**。非空の `paneTree` を持つ
  プロジェクトには常にちょうど 1 つ存在し、空プロジェクトには存在しない。単一値なので
  「複数プライマリー」は構造的に表現できない。
- 既定付与:新規プロジェクトの初期ペイン(= 最初に作られたペイン)がプライマリー。
- 永続化はペインレイアウトと同一経路・同一レコード:保存形式は `primaryPanes`
  (フラグの立ったペイン id のリスト)で、ProjectState の Codable レコードに乗る。
  健全な保存は常に 1 要素。リスト形式なのは、壊れた保存(0 個/複数/迷子 id/
  キー欠落)を decode が**拒否せず修復**するため。
- 復元時正規化 `SplitTree.normalizedPrimary(from:)`(init / decode の両経路):
  保存候補のうち復元後のツリーに現存する最初のものが勝ち、有効候補がなければ
  first leaf、空ツリーならなし。プライマリー導入前の保存(キーなし)も同じ経路で
  first leaf に決まる。
- `setPrimaryPane(_:)` はツリー外のペイン id を拒否する(戻り値 `false`・無変化)。
  旧プライマリーの解除は単一値フラグの上書きとして暗黙に起きる。

### 22.2 昇格(ツリー置換との同期)

- `paneTree` の `didSet` が置換のたびに
  `SplitTree.reconciledPrimary(previousTree:previousPrimary:)` でフラグを
  再解決する。シェルの exit・`Cmd+W`・process 死は、いずれも controller の
  surface tree 置換としてモデルに届くため、この 1 点で全ケースを扱える。
- 規則:
  - 旧プライマリーが新ツリーに現存する限りフラグは動かない。**後続分割で作られた
    ペインがフラグを奪うことはない。**
  - 旧プライマリーが消えたら、**旧ツリー上の位置**を基準に `SplitTree.nearestLeaf`
    (スロット原点間のユークリッド距離。同距離は走査順で先のものが勝ち)で、
    新ツリーへ生き残っているペインの最近傍 leaf を昇格する。
  - 昇格候補がない(旧プライマリー不明・生存者なし)場合は first leaf。空ツリーは
    プライマリーなし(最後のペインの close は §11.10 / §18.5 の既存挙動どおり
    プロジェクトごと閉じる)。

### 22.3 全体ビューの描画対象

- モデル層の判断は `WorkspaceState.overallViewPaneIDs`(`[ProjectID: SurfaceID]`):
  visible な各プロジェクト → そのプライマリー。hidden プロジェクトと空プロジェクトは
  含まれない。zoom 中の局所視点はこの判断を使わず、従来どおり全ペインを
  レイアウトのまま表示する。
- 描画には `ProjectState.overallViewPaneTree`(プライマリーだけを含む単一 leaf
  ツリー)を使い、`TerminalWorkspaceView` → `ProjectSplitTreeView` → `ProjectView` の
  `primaryOnly`(`zoomedProject == nil`)経由で切り替える。不変条件が壊れて
  プライマリーを解決できない場合のフォールバックは全ツリー表示(プロジェクトを
  白紙にしない)。

### 22.4 focus と set_primary(Cmd+P)

- 全体ビューでのキーボード入力・focus は常にプライマリーへ向く。
  `WorkspaceState.snapFocusToPrimaryInOverallView()`(非 zoom 時のみ作用)を、
  非 zoom 状態に着地しうる全ミューテーションの後段で呼ぶ:
  `replaceFocusedPaneTree`(プライマリー exit 昇格を含む)/ `setFocusedSurface` /
  `switchFocusedProject` / `gotoProject` / `toggleProjectZoom`(zoom 解除時の寄せ)/
  `hideFocusedProject` / `showProject` / `closeFocusedProject`。
- controller 側の focus 配線:`ghosttyDidToggleProjectZoom` は zoom 解除時に
  プライマリーへ focus を渡し、`ghosttyDidPresentTerminal` と
  `replaceSurfaceTree` は非 zoom 時の focus 先をプライマリーへ付け替える。
- `set_primary` action(§9.1、既定 `Cmd+P`)は zoom 中に focused ペインを
  プライマリーへ指定する。
  - 判定は `WorkspaceModel.canSetPrimaryToFocusedPane`:focused プロジェクトに
    zoom 中 + focused ペインがツリー内 + まだプライマリーでない。performable
    チェックと実行が同じ判定を共有するため常に一致し、不成立時はキーを消費せず
    fall through する。
  - 実行は `setPrimaryToFocusedPane()`:フラグが focused ペインへ移り、
    旧プライマリーは暗黙に解除される(§22.1 の単一値フラグ)。キーボード focus は
    変わらない(既に focused なペインを指定する操作のため)。

### 22.5 ペイン系操作の no-op(zoom 中のみ有効)

- モデル層の判断は `WorkspaceState.paneOperationsEnabled`:
  `zoomedProject != nil && zoomedProject == focusedProject` のときだけ true。
  全体ビューでは false(プライマリーしか描画されず、ペイン操作は視認できない
  ツリーへの操作になる)。別プロジェクトへ zoom した過渡状態でも false。
- ガード地点:
  - controller:`newSplit` / `performSplitAction`(divider resize・drop)/
    `ghosttyDidFocusSplit` / `ghosttyDidToggleSplitZoom` /
    `ghosttyDidResizeSplit` / `ghosttyDidEqualizeSplits`。
  - App の performability:`newSplit` / `gotoSplit` / `resizeSplit` /
    `toggleSplitZoom` / `equalizeSplits` は不成立時に decline し、keybind は
    未消費で fall through する。
  - `validateMenuItem`:ペイン系操作のメニュー項目(分割 4・pane zoom 1・
    ペイン間 focus 移動 6・equalize 1・divider 移動 4 の計 16 selector)を
    グレーアウトする。
- 全体ビューはペイン間 divider・drop ターゲットを描画しない(§22.3 の単一 leaf
  ツリーの帰結)。
- この変更に伴い `canToggleProjectZoom` は「focused プロジェクトがあること」だけを
  要求する(従来は複数プロジェクトが前提)。ペイン操作が zoom 中のみになった結果、
  単一プロジェクトでも zoom できなければ分割に到達できないため(設計判断 R-005)。
  zoom は局所視点への入口である。

### 22.6 プライマリー印

- モデル層の判断は `WorkspaceState.primaryMarkPaneIDs`:zoom 中のプロジェクトの
  プライマリーを、**そのプロジェクトが複数ペインを持つときだけ**返す。全体ビュー
  (プライマリーしか表示されず印はノイズ)と単一ペインのプロジェクト(唯一のペインが
  自明にプライマリー)では常に空。
- 描画は `TerminalWorkspaceView` → `ProjectSplitTreeView` → `ProjectView` →
  `TerminalSplitTreeView.markedPane` と通し、`TerminalSplitLeaf` がマーク対象
  leaf の右上に `PaneMarkBadge`(控えめな 9pt の star + ultraThinMaterial
  チップ、hit-test 無効)をオーバーレイする。split 層は中立な「mark this leaf」
  概念しか知らず、どのペインに印を付けるかの判断は project 層が持つ。

### 22.7 ペイン数バッジ(全体ビュー)

- モデル層の判断は `WorkspaceState.overallViewPaneCountBadges`:**全体ビュー
  (非 zoom)のときだけ**、visible なプロジェクトのうち**非プライマリーペインを
  持つもの(ペイン 2 つ以上)**に、そのプロジェクトの総ペイン数を返す。zoom 中
  (局所視点は実レイアウトを表示)と単一ペインのプロジェクト(隠れているものが
  ない)では常に空。hidden なプロジェクトは visible 集合に入らないので対象外。
- 意図: 全体ビューはプライマリーしか描画しないため、「その背後にさらに
  ペインがある」ことが分かる控えめな手掛かりを出す(任意対応事項)。
- 描画は `TerminalWorkspaceView` → `ProjectSplitTreeView` → `ProjectView` と通し、
  ペイン領域(プライマリー leaf)の右上に `ProjectPaneCountBadge`
  (rectangle.split.2x1 グリフ + 等幅数字、プライマリー印 `PaneMarkBadge` と
  同じ ultraThinMaterial チップ様式、hit-test 無効)をオーバーレイする。
  印(§22.6)は zoom 中のみ・バッジは非 zoom のみなので、同じ右上スロットを
  排他的に共有する。

### 22.8 テスト(ProjectPrimaryPaneTests、35 件)

モデル層はジェネリック(`ProjectStateOf` / `WorkspaceStateOf` /
`WorkspaceModelOf`。runtime は `SurfaceView` への typealias)なので、テストは
値型ペインに特殊化して実 leaf 入りのツリーで同一の判断コードを検証する
(`SurfaceView` の生成は live app を要するため)。

```text
- 既定付与・唯一性: 新規プロジェクトの初期ペイン / WorkspaceModel(wrapping:) /
  空ツリーはなし / 後続分割は非プライマリー / setPrimaryPane の移動と
  旧プライマリー解除・ツリー外 id 拒否
- 昇格: [A|B]・[A|[B|C]] でのプライマリー close 最近傍昇格 / 非プライマリー
  close はフラグ不変 / 最終ペイン close でクリア
- 永続化・復元正規化: Codable round trip で同一ペインに復元 / 0 個・キー
  なし・複数・迷子 id の decode 正規化 / ワークスペース全体 round trip
- 全体ビュー: 表示対象 = visible 各プロジェクトのプライマリーのみ(hidden 除外)/
  overallViewPaneTree は単一 leaf / 空プロジェクトは空
- focus と no-op: paneOperationsEnabled は focused プロジェクト zoom 中のみ
  (別プロジェクト zoom では無効)/ 非 zoom の setFocusedSurface・
  switchFocusedProject はプライマリーへスナップ / zoom 解除で寄せ /
  非 zoom のプライマリー close は昇格先へ focus
- set_primary: zoom 中の移動と旧プライマリー解除 / 非 zoom no-op /
  既にプライマリー no-op
- 印: zoom 中かつ複数ペインのみ(全体ビューでは空)/ 単一ペイン非表示 /
  再指定に追従 / zoom 解除で消える
- ペイン数バッジ: 複数ペインの visible プロジェクトのみ(単一ペイン・hidden は
  対象外)/ 総ペイン数を表示(3 ペインで 3)/ zoom 中は空・解除で復帰 /
  1 ペインに減ると消える
- controller ミラー経路(replaceFocusedPaneTree)でのフラグ維持・昇格
```

## 23. 削除保護仕様

プロジェクトは「情報を預ける場所」(ノート・優先度・締切)であるため、プロジェクトと
その情報が失われる経路を、確認ダイアログを経た明示的な close 操作だけに限定する
層。判断ロジックはモデル層に置き、`XGhosttyTests` から検証する(§23.5)。

### 23.1 常時確認(close_project / 最終ペインの Cmd+W)

- 判断はモデルの `WorkspaceModel.closeProjectRequiresConfirmation(anyLiveProcess:)`
  で、**無条件に true** を返す。確認済み close ダイアログがプロジェクトとその情報を
  失う唯一の正規経路だからである(§23.4)。
- controller の `closeFocusedProject` は従来の surfaceTree `needsConfirmQuit`
  スキャンではなくこの判断を使うため、実行中プロセスの有無によらず既存の
  Cancel / Close Project ダイアログ(同一形式を流用)が出る。
- 最終ペインの `Cmd+W`:`ghosttyDidCloseSurface` の最終ペイン昇格から
  `projects.count > 1` ガードを外し、単一プロジェクトの最終ペイン close も確認付き
  `close_project` へ昇格する(確定後の経路は §18.5 どおり window close へ委譲)。
- この常時確認が健全なのは §23.2 の帰結:core は child exit でペインを閉じなく
  なったため、controller に届く close_surface 通知はすべて明示的なユーザー操作
  であり、シェル死をきっかけに確認ダイアログが出ることはない。

### 23.2 終了済み状態(最終ペインの shell exit)

- Zig core 側:`Surface.childExited` は surface を**閉じない**(メッセージは
  "Process exited." に簡素化し、`wait_after_command` の早期 return を削除 —
  exit が何を意味するかは app 層が決める)。`keyCallback` は exited ペインへの
  エンコード済みキー入力を(close せず)握りつぶす。これにより core 発の close
  はすべて明示操作になる。
- App 層:`show_child_exited` は新しい `ghosttyChildExited` 通知を**無条件に**
  post する(window なし・hidden・即時 exit のペインも含む)。
  `abnormalCommandExitRuntime` 由来の異常終了 Bool を添える。メッセージバー
  表示自体は上流の可視性ガードを維持する。
- モデル判断 `WorkspaceModel.childExitOutcome(for:abnormalExit:)`(純粋・
  値型検証可能):
  - プロジェクトの**最終ペイン** → `.terminated`。正常終了・異常終了・process 死は
    いずれも同じ経路で届き、同じ判定になる。
  - 兄弟のいるペイン → `.closePane`(正常)/ `.keepPaneAwaitingKey`(異常。
    上流の「キーで閉じる」契約を維持)。
- `ProjectState.terminatedPane`(`private(set)`):不変条件は「そのペインが
  ツリーの唯一 leaf のときのみ非 nil」。`paneTree` observer が分割・除去の
  たびにクリアする。`markPaneTerminated` は唯一 leaf のみ受理。
  `removeExitedPane` はモデル側の兄弟ペイン close(hidden プロジェクトも対象)で、
  最終ペインは拒否する — その場合は `.terminated` であって除去ではない。
- terminated なプライマリーはフラグを保持する:プライマリー close の最終ペイン
  経路は本節の終了済み意味論に従う(§22.2 の昇格は兄弟がいる場合の話)。

### 23.3 終了済み表示と Enter 再開

- `ProjectTerminatedPaneView`:死んだ端末の最終フレームを薄暗く残したまま
  (最後の出力にシェルの終わり方が出ていることが多い)、端末様式のパネル
  (poweroff グリフ・"Shell exited"・"Press Return to start a new shell"・
  等幅タイポ・端末自身の背景色と split divider ストローク)を重ねる。
  hit-test 無効なので、終了済みプロジェクトのクリックは従来どおりプロジェクト focus に
  落ち、続く Enter が再開経路へ届く。
- キー配線:`SurfaceView.keyDown` は exited ペインでは死んだ pty へ書き込む
  代わりに `ghosttyExitedSurfaceKeyDown`(`isReturn` フラグ付き)を post する。
  素の keyDown だけが対象で、コマンド chord(`Cmd+W` 等)は exited ペインでも
  従来どおり効く。
- controller:terminated なプロジェクトでの Enter は `restartTerminatedPane` —
  新しい `SurfaceView`(新シェル)を生成し、モデルの
  `WorkspaceModel.restartTerminatedPane` で**同じペインスロット**へ差し替える
  (新ペインはプライマリーかつ focused surface になり、ノートは保持)。
  surfaceTree を再同期し、focused プロジェクトならキーボード focus も移す。
- terminated でない exited ペイン(兄弟あり)は上流の any-key-closes 契約を
  維持する。判定はキー入力時に**再実行**するため、その間に兄弟が閉じ終わって
  最終ペインになっていた場合は close ではなく terminated 化する。

### 23.4 永続化と喪失経路

- 終了済み状態は **runtime-only**(保存しない)。復元は全ペインを新しい
  シェルで再生成するため、terminated だったプロジェクトも生きて戻る。ノート・
  優先度・締切は ProjectState レコードに乗って保持される(§21.1、§24.1)。
- プロジェクトとその情報が失われる経路は、確認ダイアログを経た明示的な close
  操作**のみ**。アプリ終了・再起動では従来どおり全プロジェクトが復元される。

### 23.5 テスト(ProjectTerminatedTests、16 件)

```text
- 常時確認: 実行中プロセスの有無によらず確認要求
- exit 判定: 最終ペインはあらゆる exit 種別で .terminated / 兄弟の正常 exit は
  .closePane / 兄弟の異常 exit は .keepPaneAwaitingKey / 未知ペインは判定なし /
  兄弟 close 後の再判定は .terminated へ昇格
- terminated 状態: プロジェクトとノート・ペインを保持 / 複数ペイン中の mark は
  拒否 / terminated プライマリーはフラグ保持 / 分割で状態クリア
- removeExitedPane: そのペインだけ閉じる(ノート保持・hidden プロジェクト対応)/
  最終ペインは拒否
- 永続化: terminated プロジェクトの round trip でノート保持(状態自体は
  runtime-only、復元は生きて戻る)
- 再開: 同一スロットへ新ペイン(プライマリー化・focused 化・ノート保持・
  状態クリア)/ 非 terminated では拒否
```

## 24. 優先度・締切仕様

プロジェクトごとの優先度と締切を保持・表示し、明示的なソート
アクションで実レイアウトを並び替える層。保持・復元・ソート順・締切超過判定は
すべてモデル層に置き、`XGhosttyTests` から検証する(§24.5)。

### 24.1 データモデルとエディタ統合

```swift
// ProjectState に追加(いずれも未設定 = nil)
var priority: ProjectPriority?     // high / medium / low
var deadline: ProjectDeadline?     // 日付のみ、時刻なし
```

- `ProjectPriority`:String-raw の Codable enum(high/medium/low)。
  `sortRank` 0/1/2 と `unsetSortRank` 3 がソートキー。未設定は**値の不在**
  (Optional)で表現する。
- `ProjectDeadline`:日付のみの値型。**検証は構成的** — failable initializer
  だけが値を作れるため、不正な締切は型として表現不能:
  - `init(year:month:day:)` は `DateComponents.isValidDate` で実在しない
    グレゴリオ日付を拒否(閏日は受理)。
  - `init(parsing:)` は `YYYY-MM-DD` / `YYYY/MM/DD` 形のみ受理。
  - `Comparable` は `ordinalValue`(y×10000 + m×100 + d。ソートキー兼用)。
  - `init(from: Date, calendar:)` が実行時の「今日」を導出(時刻は落ちる)。
  - Codable は正準 `YYYY-MM-DD` テキストを保存し、decode で再検証する。
- 永続化はノートと同一の ProjectState レコード(`encodeIfPresent`)。decode は
  **不正→未設定**を寛容に適用:未知の priority 文字列や実在しない保存日付は
  プロジェクトレコードごと拒否せず unset として読む。キーのないレガシー保存も
  unset。
- 書込み口:`setProjectPriority` / `setProjectDeadline(to:)`(未知プロジェクト・
  無変化は no-op)。保存時境界 `setProjectDeadline(parsing:)`:空入力は意図的な
  クリア(true を返す)、不正入力は**未設定へ**拒否(false。前の値には
  戻さない)。
- エディタ統合(§21.2 の metaRow):segmented な優先度 picker
  (none/high/med/low)と等幅 `YYYY-MM-DD` テキストフィールド(Return は
  Cmd+Enter と同じ commit)。不正入力の "→ unset" ヒントは
  `ProjectDeadline(parsing:)` を再利用するため、ヒントと保存時判断は乖離
  しえない。全保存経路は単一 commit ポイント
  `endNoteEditing(saving:priority:deadlineInput:)` に集約され、ノート・
  優先度・締切が一括保存される。note-only の `endNoteEditing(saving:)` は
  優先度・締切に触れない。Esc(`cancelNoteEditing`)は 3 ドラフトとも破棄
  する — ドラフトは view 状態で、モデルは commit まで不変。

### 24.2 締切超過の判定と表示

- 判定はモデル:`ProjectDeadline.isOverdue(today:)` — today より**厳密に前**の
  日だけ超過(締切当日はまだ超過でない)。`WorkspaceState.overdueProjectIDs(today:)`
  は**全プロジェクト**を対象にする(超過は hiding をまたいで生存すべき情報で、
  表示層が既に visibility でスコープしているため)。
- 表示は共有ビュー `ProjectPriorityDeadlineMeta`(ProjectLabel.swift。両表示面が
  同じビューを使うため乖離しない):優先度は等幅の bang 密度
  (high `!!!` / medium `!!` / low `!` — 色もアイコンも使わない控えめな印)、
  締切は `YYYY-MM-DD` テキスト、**未設定の項目は何も描かない**。超過は
  ちょうど 1 段階の控えめな強調(赤みのある tint + 不透明度引き上げ)。
  「間近」等の段階分けはしない。
- 配置:ラベル帯の trailing(ノートグリフの手前。inline rename 中は非表示 —
  帯は一度に 1 つの対話モードだけを持つ。unfocused プロジェクトでは 0.6 opacity)
  と、一望モードの各パネルヘッダー(プロジェクト名の横)。today は描画時に
  `ProjectDeadline(from: Date())` で導出し、表示層はモデルの答えだけを描く。

### 24.3 ソート順序付け(純関数)

- `priorityOrderedVisibleProjectIDs()`:high → medium → low → 未設定。
- `deadlineOrderedVisibleProjectIDs()`:近い日付順、未設定は末尾。
- 共通契約:入力は `visibleProjectIDs` のみ(hidden は入力に入らないため構造的に
  影響不能)、純関数で副作用なし、**安定性は構成で保証**(stdlib の sort は
  安定性を文書化しないため、enumerated + offset の明示タイブレーク)。
  同順位・同日は現在の相対順を維持する。

### 24.4 ソートアクション(sort_projects_by_priority / sort_projects_by_deadline)

- `sort_projects_by_priority`(既定 `Cmd+S`)/ `sort_projects_by_deadline`
  (既定 `Cmd+Shift+S`)。§10.5 のとおり両 chord とも既存割り当てなし。
- 判定は `WorkspaceModel.canSortVisibleProjects`:visible プロジェクト 2 つ以上 +
  オーバーレイセッション中でない(`overlaySessionActive`:一望モード §21.3・
  hide 選択 §25・レイアウトセッション §26 を統合した判定)。`set_primary` と同型で、
  performable チェックと実行が同じ判定を共有し、不成立時はキー未消費で
  fall through する。
- 実行:`SplitTree.reorderingLeaves(to:)` が**同一構造の上で leaf の載せ替え
  だけ**を行い(形状・分割方向・分割比は不変。現 leaf の順列でなければ nil)、
  `WorkspaceState.applyVisibleProjectOrder` が §24.3 の順序を canonical tree へ
  適用する。レイアウトはリフローせず、プロジェクトがスロットを入れ替える —
  `move_project` の `swappingLeaves` と同じ意味論の n 項版。
- 帰結(いずれも構成から従う):
  - 序数(Cmd+1〜9)は走査順由来なので**自動追従**する。
  - focus は id ベースなので不変(focused プロジェクトが新しいスロットに移る)。
  - hidden プロジェクトは canonical leaf を持たないため影響を受けない。
  - **明示実行時のみソート**:優先度・締切の setter はツリーに触れないため、
    値の変更で自動再ソートは起きない。
  - ソート後の並びは次のソートまで持続する(leaf 割り当てを書き換える経路が
    他にない)。
  - zoom 中も実行可(canonical tree は表示非依存。zoom 解除時に新しい並びが
    見える)。

### 24.5 テスト(ProjectPriorityDeadlineTests、21 件)

```text
- 既定: 新規プロジェクトは優先度・締切とも未設定
- 永続化: 優先度+締切の round trip 復元 / 壊れた保存(未知 priority 文字列・
  実在しない日付)は unset として decode
- 入力境界: 不正日付は未設定へ拒否(前の値も残らない)/ 空入力は意図的
  クリア / parser は実在日付のみ受理(閏日含む)/ today 導出は時刻を捨てる
- 超過: 締切日より厳密に後のみ / 未設定は非超過 / hidden も判定対象
- 順序付け: 優先度順(安定タイ)/ 締切順(未設定末尾・同日安定)/
  visible のみ・無副作用
- ソートアクション: 実レイアウトの並び替え(優先度・締切とも、序数追従)/
  hidden・focus 不変 / 明示実行のみで次のソートまで持続 / 単一プロジェクトと
  一望モード中は decline(退出後は可)
- エディタ commit: 3 値一括保存 / 不正締切は unset へ / note-only 経路は
  優先度・締切不変 / セッションなし no-op / 未知プロジェクト setter no-op
```

## 25. hide 選択仕様

`Cmd+Opt+H`(`hide_project` action)は focused プロジェクトの即時 hide ではなく、
visible なプロジェクトから隠すものを複数選ぶ選択画面を開く(即時 hide の置換は
必須対応事項 14 の列挙済み意図的変更)。判断ロジックはモデル層に置き、
`XGhosttyTests` から検証する(本節末尾)。

### セッションとモデル判断

- セッション状態は `WorkspaceModel.hideSelection`(`Set<ProjectID>?`、nil =
  画面なし)。**transient(保存しない)**で、`restoreState`(undo/redo)と
  `removeAllProjects` がセッションを終了する。
- `canBeginHideSelection`:visible プロジェクト 2 つ以上(1 つでは「最低 1 つは
  visible に残る」制約により何も隠せない)+ ノートエディタ・他のオーバーレイ
  セッションが開いていないこと。performable チェックと実行が同じ判定を共有し、
  不成立時はキー未消費で fall through する(`set_primary` と同型)。
- `beginHideSelection` は zoom を先に解除する(zoom 中呼び出しの挙動は Essence が
  実装に委ねた部分)。列挙対象 `hideSelectionProjectIDs` は visible な
  プロジェクトを序数順で返す。hidden なプロジェクトは列挙されず選択にも
  入れない — 復帰導線は従来どおり hidden シェルフで、変更しない(§7.2)。
- `toggleHideSelection` は visible なプロジェクトのみトグルする。
- `canConfirmHideSelection`:**select-all は拒否**(selection.count <
  visibleProjectCount。最低 1 つは visible に残る)。空選択は確定可能 —
  「何も隠さず閉じる」として扱う。
- `confirmHideSelection(savingOutgoingPaneTree:)`:選択された全プロジェクトを
  **1 回の state 書き込みで一括 hide** — 各 leaf が canonical tree から抜けて
  残存プロジェクトがスペースを回収し、id が `hiddenProjectIDs`(シェルフの
  source of truth)へ入る。focused プロジェクトが選択に含まれる場合、除去前の
  ツリー上で `hideFocusedProject` と同じ nearest-leaf 規則により生存者へ focus を
  渡す。ミッドセッションの menu-bar zoom に備えた zoom 解除バックストップと
  `snapFocusToPrimaryInOverallView` を適用する。
- `cancelHideSelection`(Esc 経路)は何も隠さず閉じる。
- セッション中は画面が対話を占有する:focus 移動(`switchFocusedProject` /
  `gotoProjectTarget` / `gotoProjectIndexTarget`)・ノート編集・一望モード・
  ソートは既存の閲覧専用ガードと統合された `overlaySessionActive` 判定で
  no-op になる(一望モード §21.3・レイアウトセッション §26 と相互排他)。

### UI(ProjectHideSelector)

- オーバーレイはセッション中のみ描画され、端末領域を恒久的に占有しない。抜ければ
  端末が全面に戻り、キーボード focus も端末へ返る(ノートエディタと同じ流儀)。
- visible なプロジェクトを序数順に列挙(チェックボックスグリフ + 序数 + 名前、
  カーソル行ハイライト、ProjectNoteEditor 様式のスタイリング)。フッターは
  選択中の件数、または Enter がブロックされる理由(「at least one project must
  stay visible」)を表示する。
- キーボードは CommandPaletteView と同じ機構(不可視の focused TextField が
  キーボードを所有):Esc(`onExitCommand`)= キャンセル、Enter(`onSubmit`)=
  確定(モデルが `canConfirmHideSelection` を再判定するため、拒否された確定は
  画面が残る)、Space = カーソル行トグル。矢印(↑/↓)のカーソル移動だけは
  `onMoveCommand` でなくローカル keyDown モニタ(`overlayArrowKeys`、
  `ProjectOverlayKeys.swift`)で受ける — 編集可能な sink TextField が
  フォーカスを持つ間は field editor が矢印を消費して `onMoveCommand` が
  発火しない(実機で不達を確認)ため、dispatch 前にイベントを取って消費する。
  行クリックでトグル、**背景クリックはキャンセル**(hide するのは
  Enter だけ)。
- controller の確定経路は、バッチ全体に対して **1 つ**のプロジェクト対応
  「Hide Projects」undo を登録する。
- 本画面はレイアウト適用の超過分 hide-pick(§26.3)と共用で、title / hint /
  footer をパラメータ化してある。

### テスト(ProjectHideSelectionTests、14 件)

```text
- 確定: 選択した複数プロジェクトが一括で hidden(1 コミット、leaf 除去、
  projects には生存、シェルフ復帰導線不変)
- キャンセル: 何も hidden にならず、画面を開く前と完全に同一
- select-all: 確定できず画面が残る / 1 つ外せば確定でき、外した 1 つが
  visible に残る
- セッション機構: begin は序数順列挙・zoom 解除 / visible 1 つ・ノート
  エディタ中・一望モード中は begin 拒否 / toggle は複数可・hidden と未知 id
  拒否 / 空選択の確定は何も隠さず閉じる
- focus: focused プロジェクトが選択に含まれると最近傍の生存者へ移る
- 占有: セッション中の focus 移動・ノート編集・一望モード・ソートは no-op、
  終了後に復活 / restoreState と removeAllProjects がセッションを終了
```

## 26. 登録レイアウト仕様

組み込み固定 11 種の画面配置テンプレートを一手で適用する層。スロット計算・
数合わせ・割り当て順の判断ロジックはモデル層に置き、`XGhosttyTests` から
検証する(§26.5)。

### 26.1 レイアウト定義とスロット計算(ProjectLayout)

- `ProjectLayout.registered`:等分割(プロジェクト数 4〜9 の 6 種)と X+1
  (X = 4〜8 の 5 種)の計 11 種。**データとしての閉集合**で、ユーザー定義
  レイアウトは存在しない(非対応事項)。
- 等分割の行配分は純関数 `equalSplitRowCounts(n)`:行数 = √n に最も近い整数、
  余りは上の行から 1 つずつ配る — 4 = 2+2、5 = 3+2、6 = 3+3、7 = 3+2+2、
  8 = 3+3+2、9 = 3+3+3(Essence の表をそのまま固定)。
- `rowCounts`:X+1 は X 部分の行配分の末尾に `[1]`(最下段・全幅)を足したもの。
- `slotFrames`:単位正方形上の rect 列を**割り当て順**(row-major:上の行から、
  行内は左から右 — +1 枠は最下段なので自然に最後)で返す。**全行の高さは等分**
  (X+1 の +1 行も他の行と同じ高さ — Essence は +1 行の高さを規定しないため、
  行高等分をそのまま延長する設計解釈。T-041 の実機確認対象)。行内の各スロット
  幅は等分。
- `SplitTree.init(gridRows:)`(element-agnostic)がグリッドを入れ子の等比
  split として構築する(行方向 vertical、行内 horizontal。equalChain により
  先頭ノード比 1/n、以降は残りの 1/(n-1) で全スロット等分)。走査順は
  row-major で、`slotFrames` の割り当て順と一致する。

### 26.2 レイアウト選択オーバーレイ(choose_project_layout / Cmd+L)

- 新規 action `choose_project_layout`(§9.1、既定 `Cmd+L`。§10.5 のとおり
  既存割り当てなし)。performability は `canBeginLayoutSelection`(visible
  プロジェクト 1 つ以上 + 他のオーバーレイなし)で、不成立時はキー未消費で
  fall through する。
- `beginLayoutSelection` は zoom を先に解除する(zoom 中呼び出しの挙動は
  Essence が実装に委ねた部分)。セッション状態 `layoutSelectionActive` は
  transient で、`restoreState` / `removeAllProjects` が終了する。
- `ProjectLayoutSelector` オーバーレイ:11 種を列挙(ラベル・プロジェクト数・
  **効果プレビュー** — モデルの数合わせ判断をそのまま行ごとに表示:
  「fits」/「+N new」/「pick N to hide」)。矢印でカーソル移動、Enter または
  行クリックで選択、Esc または背景クリックで何も変えずに閉じる。キーボード
  機構は ProjectHideSelector と同じ sink-TextField 方式(矢印も同じく共有の
  ローカル keyDown モニタ `overlayArrowKeys` で受ける、§25)。
- オーバーレイは呼び出し中のみ描画され、抜ければ端末が全面に戻る。selector →
  hide-pick の遷移では focus 手戻りをスキップし、キーボードは pick 画面に
  着地する。

### 26.3 数合わせ(chooseLayout の判断)

`chooseLayout` がモデルの数合わせ判断を一手に持つ:

- **等数**(レイアウト数 = 現表示数):即時適用(`.applied`)。visible な
  プロジェクトが現在の序数順のままスロットへ入る。
- **不足**(レイアウト数 > 現表示数):`.needsNewProjects(n)` を返し、controller
  が不足分を通常の新規作成と同様に構築(fresh `SurfaceView` = 新シェル、
  `ProjectNameGenerator` 名、初期ペインがプライマリー)して
  `applyLayout(appending:)` で完了する。新規プロジェクトは**序数の末尾**に
  登録され、既存 visible が先頭側スロットを、新規が末尾側スロットを埋める。
  `applyLayout` は不足数の不一致・id 衝突を拒否する(無変化で false)。
- **超過**(レイアウト数 < 現表示数):hide-pick セッション
  (`layoutHidePick`:選ばれたレイアウト + 選択集合)が開く。
  - `layoutHidePickRequiredCount`(超過数)は live state から再導出される。
  - `canConfirmLayoutHidePick`:**選択数が超過分ちょうど**のときのみ確定可
    (多くても少なくても不可。画面は残る)。
  - `confirmLayoutHidePick`:選択されたプロジェクトを hide(**close はしない**
     — ペイン・プロセス・情報はシェルフの背後に生存)し、残りへレイアウトを
    序数順で適用 — **1 回の state 書き込み**。focus 規則は §25 の確定と同一。
  - `cancelLayoutHidePick`(Esc)は**レイアウト適用ごと**キャンセルする —
    何も隠れず、何も並び替わらない。
  - UI は ProjectHideSelector の再利用(title「apply <layout>」、footer
    「select exactly N to hide (k/N)」/確定サマリ)。
- controller は適用 1 回につき **1 つ**の「Apply Layout」undo を登録する
  (等数・不足・超過のいずれの完了経路でも)。

### 26.4 一回性と永続化

- 適用は `applyLayoutTree` による canonical tree の再構築のみ:**「適用中の
  レイアウト」という状態は持たない**(one-shot)。適用後の手動 resize・分割・
  ソートは従来どおり可能で、配置は従来の経路でそのまま保存・復元される。
- 選択されなかった hidden プロジェクトは `projects` エントリもシェルフ位置も
  一切影響を受けない。
- 序数(Cmd+1〜9)は走査順由来なので適用後の配置に自動追従する。zoom は
  クリアされる(適用は全体ビューの配置替え)。

### 26.5 テスト(ProjectLayoutTests、14 件)

```text
- 定義とスロット計算: 11 種の registered 定義 / 等分割行配分の Essence 表 /
  slotFrames のグリッド規則(行高等分〔+1 行含む〕・行内幅等分・+1 全幅
  最下段・row-major 割り当て順・7 分割の具体ピン)/ gridRows ツリーが
  手組みの等比ノードツリーと一致
- 等数: 序数順割り当て・ツリー = 期待グリッド・序数追従
- 不足: 新規プロジェクトが序数末尾に作成・割り当て / 不足数不一致は拒否
- 超過: hide-pick が超過分ちょうどで確定ゲート(0/1/3 選択は拒否・画面
  維持)/ 選択 2 つだけが hidden(close されない)・残り 4 つが序数順割り
  当て・序数追従 / focused が選択されると最近傍生存者へ focus /
  選択外の hidden プロジェクトは不変
- キャンセル: selector の Esc も hide-pick の Esc も適用ごと取りやめ(無変化)
- セッション: begin は zoom 解除・他オーバーレイ中は拒否 / セッション中は
  画面が対話を占有 / restoreState・teardown で終了
- 一回性: 適用後のソートは自由 / Codable round trip で適用後の canonical
  tree が保存・復元される
```

[1]: https://ghostty.org/docs/config/keybind/reference "Action Reference - Keybindings"
[2]: https://rexbrahh.github.io/ghostty-knowledge-base/reference/macos/Sources/Features/Splits/SplitTree.swift/ "macos/Sources/Features/Splits/SplitTree.swift | Ghostty Knowledge Base"
[3]: https://github.com/ghostty-org/ghostty/blob/main/macos/Sources/Features/Splits/TerminalSplitTreeView.swift "ghostty/macos/Sources/Features/Splits/TerminalSplitTreeView.swift at main · ghostty-org/ghostty · GitHub"
