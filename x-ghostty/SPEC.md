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

採用する構造は **台帳 + 二層SplitTree**(2026-08-18 改訂で台帳を導入)。

```swift
WorkspaceState
  // 台帳(source of truth、§27.1)
  projectOrder: [ProjectID]              // hidden を含む全行の単一の行順
  hiddenProjectIDs: Set<ProjectID>       // visibility 列(永続)
  layoutType: ProjectLayoutType          // 記憶しているレイアウト型(§26)
  listColumnOrder: [ProjectListColumn]   // 一覧の列順
  projects: [ProjectID: ProjectState]

  // 投影・runtime
  canonicalProjectTree: SplitTree<ProjectRef>  // 台帳+型から relayout() で再導出
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

### 4.1 台帳が source of truth、tree は投影

**台帳(`projectOrder` + `hiddenProjectIDs` + `layoutType`)が配置の
source of truth** であり(2026-08-18 改訂の主従逆転、§27.1)、
`canonicalProjectTree` は台帳の visible な行をレイアウト型のスロットへ
割り当てた**投影**である(`relayout()`、§26.3)。canonical tree の leaf 集合 =
visible project の集合であり、hidden project は leaf を持たず、`projects` の
`ProjectState` としてのみ生存する。

```text
projectOrder:  calm-river, logs, server, agent   ← 単一の行順(台帳)
hidden:        logs, agent                        ← projects には残るが leaf は持たない

canonicalProjectTree(投影):
  calm-river | server        ← layoutType.tree(over: visible 行)

effectiveVisibleProjectTree:
  canonicalProjectTree に zoom を適用した派生tree
```

`hide_project` / `show_project` / 一覧の表示トグルは台帳の hidden フラグを
変えるだけで、配置は `relayout()` が再導出する(hide 中は残りの visible
project がスペースを回収し、show は行順どおりの位置に戻る — 位置復元ロジックは
不要)。`close_project` だけが `projects` と台帳の行からも削除して process を
終了する。

さらに `effectiveVisibleProjectTree`(zoom の派生)を分けることで、
台帳 → 配置 → 表示の 3 段が常に一方向に導出される。

### 4.2 プロジェクトは最上位レイアウト単位

`Cmd+D` は常に focused project 内の `paneTree` だけを分割する。
プロジェクト境界は越えない。

```text
Cmd+D:
  focusedProject.paneTree を split

Cmd+N:
  台帳に新規 project の行を挿入する(§27.4。分割ではない)
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

    // 台帳(すべて永続、§27.1)
    var projectOrder: [ProjectID]
    var hiddenProjectIDs: Set<ProjectID> = []
    var layoutType: ProjectLayoutType = .default
    var listColumnOrder: [ProjectListColumn] = ProjectListColumn.defaultOrder
    var projects: [ProjectID: ProjectState]
    var lastPriorityResetWorkday: Workday?      // §28.2

    // 投影(encode されない。decode 時に relayout() で再構築)
    var canonicalProjectTree: SplitTree<ProjectRef>

    var focusedProject: ProjectID?              // 永続(復元時に検証)
    var zoomedProject: ProjectID?               // runtime-only
}
```

`zoomedProject` だけが runtime-only。`hiddenProjectIDs` は 2026-08-18 改訂で
永続へ昇格した(一覧の visibility 列、§12.1)。旧保存の
`canonicalProjectTree` は decode 時に行順の種としてのみ読まれる。

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
  └─ overlay 群(呼び出し中のみ:ノート編集 §21.2 / 一望モード §21.3 /
     レイアウト型選択 §26.2 / プロジェクト一覧 §27)
```

常時表示の overlay は無い(思想 2)。hidden プロジェクトを常時映す帯も持たない
(§7.2)。

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

            // 呼び出し中のオーバーレイだけがここに載る(§21.2, §21.3,
            // §26.2, §27)。常設の overlay は無い。
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

### 7.2 hidden プロジェクトの扱い（常設 shelf は持たない）

hidden プロジェクトは canonical tree に葉を持たないだけで、`projects` エントリ・
ペイン・プロセス・ノート・優先度・締切はすべて生存している(§14.7)。

**画面上に常設の hidden 表示は持たない。** 初期設計では右上固定の
「hidden shelf」(名前 pill の帯)を置いていたが、これは端末領域を恒久的に食う
常時表示 UI であり、思想 2 に反していた。加えて、抱えているプロジェクトの
全体像は visible / hidden を分けずに一箇所で読めるべきである。したがって
shelf は廃止し、**hidden プロジェクトの唯一の復帰導線を `Cmd+L` の
プロジェクト一覧(§27)へ一本化**した。`HiddenProjectShelf` view は存在しない。

一覧側の対応:

```text
- 一覧は hidden を含む全プロジェクトを 1 つの表に並べる(§27.1)
- hidden 行は序数欄が空(序数は visible にしか付かない、§7.3)
- Space で hide/show を即時トグル(§27.2)
- hidden 行の Enter は無効(画面上に focus 先が無いため、§27.3)
```

`show_project:<project-id-or-name>` action(§11.8)はモデルプリミティブとして
そのまま残る。show は台帳の hidden フラグを外すだけで、復帰位置は行順と
レイアウト型からの再導出(`relayout()`、§26.3)が決める。一覧の Space
トグルの show 経路も同じ(ただし focus は動かさない、§27.2)。

### 7.3 プロジェクト番号（1～9）と表示上限

visible project は最大 9 個まで。`WorkspaceState.maxVisibleProjects = 9` として実装。

#### 動的序数

visible project は**台帳の visible な行を上から数えた順**(§27.1、
`visibleProjectIDs` / `ordinal(of:)`)で 1～N(N = visible count)の序数を
自動付与する。序数は display-only で内部保持しない。配置は台帳から序数順に
導出される(§26.3)ため、canonical tree の葉走査順とも一致する。

枚数変化時(hide / close / show / 新規作成)や行移動(move_project・一覧の
`Cmd+↑↓`)・ソート(§24.4)の後、序数は自動的に再計算・再配置される。

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

- `new_project` ... 作成自体は拒否しない — 新規行は **hidden として**挿入される
  (§27.4。登録総数に上限は無く、同時に画面へ並ぶ数だけが 9 まで)
- `show_project`（`show_project:<name>` action、およびプロジェクト一覧の Space トグル §27.2） ... quietly no-op（行は hidden のまま残る）
- `goto_project` index form（`goto_project:1`～`goto_project:9`）... 無効な index は no-op、performability gate あり
- `goto_project` directional form ... 変わらず動作（方向移動だけでは上限に到達しない）

performability gate の扱い：

- `show_project` ... 上限到達時（または対象が hidden でないとき）は performable = false で
  keybind を消費しない
- `goto_project` index form ... 対象 index が解決できない・focused と同じ
  （zoom 中は zoomed project 自身と同じ）とき performable = false で keybind を消費しない

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
new_project

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

move_project:right
move_project:down
move_project:left
move_project:up

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

list_projects

close_project
```

2026-08-18 改訂で廃止した action:`new_project_split`(方向付き分割作成 →
`new_project` の一覧経由作成に一本化、§27.4)、`resize_project` /
`equalize_projects`(プロジェクト境界の手動操作 → レイアウト型の投影に置換、
§26)。いずれも parser・C ABI(`xghostty.h` の action enum)から削除済みで、
keybind に書けば設定エラーになる(後方互換は保証しない方針、必須対応事項 58)。

### 9.2 既存actionとの対応

```text
goto_split         -> goto_project
toggle_split_zoom  -> toggle_project_zoom
close_surface      -> close_project
```

`new_project` は既存 action に対応物を持たない(分割ではなく台帳への行挿入、
§27.4)。`move_project` は `goto_project` と同じ方向語彙で行を入れ替える。

## 10. デフォルトキー割り当て

### 10.1 ペイン分割

既存維持。

```text
Cmd+D                 -> new_split:right
Cmd+Shift+D           -> new_split:down
```

### 10.2 新規プロジェクト作成

```text
Cmd+N                 -> new_project
```

新規作成の導線はプロジェクト一覧に一本化(§27.4)。旧
`Cmd+Opt+D` / `Cmd+Opt+Shift+D`(`new_project_split`)は 2026-08-18 改訂で
action ごと廃止した。

### 10.3 プロジェクト移動

方向 focus 移動と行の入れ替え:

```text
Cmd+Ctrl+Opt+Shift+Left/Right/Up/Down   -> goto_project:left/right/up/down
Cmd+Ctrl+Shift+Left/Right/Up/Down       -> move_project:left/right/up/down
```

`move_project` は台帳上で focused プロジェクトの行を隣の visible 行と
入れ替える(§26.3。配置は再導出で追従)。

序数ジャンプ:

```text
Cmd+1〜9              -> goto_project:1〜9
```

Cmd+1～9 は physical `digit_1`～`digit_9` と unicode `1`～`9` の両方に登録し
（AZERTY 等のレイアウト対策）、`goto_project:1`～`goto_project:9` に performable 付きでバインドする。
本 fork にタブは存在せず、上流の `goto_tab` / `last_tab` は core ごと削除済みなので衝突しない。

### 10.4 プロジェクトリサイズ(廃止)

プロジェクト単位の resize / equalize は 2026-08-18 改訂で action ごと廃止した
(§26.4、必須対応事項 55)。プロジェクト境界の配置はレイアウト型(§26)が
決め、手動では動かせない。zoom 中のプロジェクト内ペインの
`resize_split` / `equalize_splits` は従来どおり有効。

### 10.5 その他

```text
Cmd+Opt+Enter         -> toggle_project_zoom
Cmd+Opt+H             -> hide_project
Cmd+Opt+R             -> rename_project
Cmd+E                 -> edit_project_note
Cmd+Opt+E             -> toggle_note_overview
Cmd+P                 -> set_primary
Cmd+S                 -> sort_projects_by_priority
Cmd+Shift+S           -> sort_projects_by_deadline
Cmd+L                 -> list_projects
Cmd+Opt+L             -> choose_project_layout
```

`Cmd+Opt+Enter` は既存 split zoom と衝突しない形で「上位レイヤーのzoom」として覚えやすい。
ノート系 2 action の仕様は §21。2026-08-18 改訂で `Cmd+N` / `Cmd+Opt+N` から
`Cmd+E` / `Cmd+Opt+E` へ移した(`Cmd+N` は新規プロジェクト作成へ、§10.2。
`Cmd+Opt+N` は無割当)。上流デフォルトの `cmd+e=search_selection` は解除済み
(action 自体は残り、ユーザー keybind で復活できる)。
`set_primary`(§22.4)は zoom 中に focused ペインをプライマリーへ指定する。素の
`Cmd+P` に既存割り当てはない(コマンドパレットは `Cmd+Shift+P`)。
ソート 2 action の仕様は §24.4。素の `Cmd+S` / `Cmd+Shift+S` にも既存割り当てが
ないことを確認済み(上流はどちらの chord も未使用)。
`hide_project`(§25)は focused プロジェクトの**即時 hide**(2026-08-18 改訂で
hide 選択画面を廃止し即時に戻した)。`list_projects`(§27)は hidden を含む
全プロジェクトの台帳オーバーレイを開き、hidden プロジェクトの唯一の
復帰導線となる(hidden シェルフは廃止、§7.2)。`choose_project_layout`(§26.2)は
レイアウト型の選択オーバーレイを開く。素の `Cmd+L` に既存割り当てはない(config
デフォルトにもメニュー key equivalent にも `l` の super chord は無いことを
確認済み)。`Cmd+L` は日々使うプロジェクト一覧に与え、レイアウト選択は
オーバーレイ系の修飾に揃えて `Cmd+Opt+L` へ移した(`Cmd+Opt+H` / `Cmd+Opt+E` と
同じ族)。`Cmd+Opt+L` にも既存割り当てはない。
また、上流デフォルトの `cmd+enter=toggle_fullscreen` は解除済み:`Cmd+Enter` は
ノート編集オーバーレイの保存確定(§21.2)に予約する。fullscreen は
`Ctrl+Cmd+F`・Window メニュー・緑ボタンから引き続き到達できる。

## 11. 状態遷移仕様

### 11.1 `new_project`

新規プロジェクト作成はプロジェクト一覧経由に一本化(§27.4。旧
`new_project_split` は廃止、§9.1)。

挙動:

```text
1. 一覧が開いていなければ開く(beginProjectList。zoom は先に解除)
2. 新規 ProjectState を作る(ProjectNameGenerator 名、初期ペイン 1 つ =
   プライマリー、新シェル)
3. 台帳のカーソル行の直下に行を挿入する(insertProject(_:after:))
4. 挿入前の visible 数が 9 未満なら visible(relayout が配置を組み直す)、
   9 なら hidden(§7.3 の上限を作成でも守る)
5. カーソルは新しい行のタイトル列に移り、その場でタイトル編集が始まる
```

作成しても focus は一覧が保持する(端末への focus 移動は `Cmd+Enter` の
役割、§27.3)。

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

### 11.4 `resize_project`(廃止)

2026-08-18 改訂で action ごと削除(§9.1、§26.4)。プロジェクト境界の配置は
レイアウト型(§26)からの投影で決まり、手動リサイズは存在しない。zoom 中の
ペイン `resize_split` は従来どおり。

### 11.5 `equalize_projects`(廃止)

2026-08-18 改訂で action ごと削除(§9.1、§26.4)。レイアウト型のスロットは
定義上等分なので、均等化アクションの出番も存在しない。zoom 中のペイン
`equalize_splits` は従来どおり。

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

`hide_project` action(既定 `Cmd+Opt+H`)は focused プロジェクトの
**即時 hide**(§25。2026-08-18 改訂で hide 選択画面を廃止)。

```text
1. focus の移動先を hide 前の配置上で解決(nearest 規則)
2. 台帳の hidden フラグを立てる(setProjectHidden(id, true)。行順は不変)
3. relayout() が記憶しているレイアウト型で残りの visible 行の配置を再導出
   → 残りの visible project がスペースを回収する(§26.3)
4. process / PTY / surface は生存(ProjectState は projects に残る)
5. zoomedProject == hidden target なら zoom解除(relayout 内)
6. focus を 1 で解決した neighbor へ移す
7. 画面上の常設表示は無い — 復帰導線はプロジェクト一覧(§7.2, §27)
```

全projectをhiddenにしようとした場合:

```text
最後の visible project は hide できない(canHideFocusedProject、§25)
```

理由: workspace が空になると操作・復帰UIが不安定になるため。同じ規則が
一覧の表示トグル(§27.2)にも適用される。

### 11.8 `show_project`

表示上限到達時は no-op(§7.3)。

```text
1. visible project 数が既に 9 個の場合は no-op(toast/beep なし)
2. 台帳の hidden フラグを外す(setProjectHidden(id, false)。行順は不変)
3. relayout() が記憶しているレイアウト型で新しい visible 数の配置を再導出
   — 復帰位置は台帳の行順が決める(hide 前と行が同じなら同じ序数位置へ戻る)
4. zoomedProject を解除
5. focus をそのprojectへ移す(show_project action の場合。一覧の表示トグルは
   focus を動かさない、§27.2)
6. project内では最後にfocusしていたpaneへ戻す
```

2026-08-18 改訂で「末尾 leaf の 50/50 分割で再接続」は廃止:配置は常に台帳と
レイアウト型からの投影なので、show は特別な再接続規則を持たない。

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
- projectOrder(台帳の行順、hidden を含む)
- hiddenProjectIDs(visibility 列 — 2026-08-18 改訂で永続へ昇格)
- layoutType(記憶しているレイアウト型)
- listColumnOrder(一覧の列順)
- projects(names / paneTree / note / priority / deadline / nextTrigger /
  primary フラグ / createdAt)
- lastPriorityResetWorkday(§28.2)
- focusedProject(復元時に検証)
- focusedSurface per project
```

### 12.2 保存しないもの

```text
- canonicalProjectTree(台帳からの投影 — decode 時に relayout() で再構築。
  旧保存の tree は行順の種としてのみ読まれる)
- zoomedProject(runtime-only。復元時は非 zoom)
```

hidden 状態は復元される(旧設計の「復元時はすべて visible」は 2026-08-18
改訂で廃止 — 一覧が台帳になった以上、visibility は台帳の永続列である)。

### 12.3 起動時pane復元

各paneは新規 shell として復元する。

```text
Before quit:
  台帳 / project / pane layout 保存

After launch:
  台帳を正規化・再投影し、同じ project / pane layout で shell を起動
```

live process / scrollback / PTY状態は復元しない。

### 12.4 台帳の正規化(normalizeLedger)

復元(`WorkspaceState.restoring`)は台帳を正規化してから再投影する:

```text
1. zoomedProject = nil
2. normalizeLedger():
   - projectOrder を projects.keys の順列に修復(未知 id は落とし、
     載っていないプロジェクトは (createdAt, id) 順で末尾に追加)
   - hiddenProjectIDs を生存プロジェクトに限定
   - visible な行が 9 を超える場合、10 個目以降の visible 行を hidden へ
     (§7.3 の表示上限)
   - 全行 hidden なら先頭行を visible に戻す(最低 1 つは visible)
3. relayout(): 台帳とレイアウト型から配置を再導出(§26.3)
4. focusedProject を検証(生存かつ visible でなければ先頭の visible 行へ
   フォールバック)
```

壊れた保存(列順の欠落・未知のレイアウト型等)は decode の寛容経路が既定値へ
落とし、`normalizeLedger` が構造を修復するため、復元は常に不変条件(§14)を
満たした状態で終わる。

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
4. projectOrder は projects.keys の順列である(§27.1。decode 後は
   normalizeLedger が修復する)
5. zoomedProject は visible project のみ
6. focusedProject は visible project のみ
7. hide_project は process を終了しない
8. close_project は process を終了する
9. Cmd+D は focused project 内の paneTree だけを変更する
10. canonicalProjectTree は台帳(projectOrder・hiddenProjectIDs・layoutType)
    からの投影であり、台帳を経由せずに変更されない(§4.1, §26.3)。
    永続化もされない(§12.2)
11. new_project は台帳のカーソル行直下に行を挿入し、新project内に初期pane
    (=プライマリー)を1つ作る。visible 数 9 未満なら visible、9 なら hidden
    (§27.4)
12. goto_project 後は対象projectの last focused pane にfocusする
13. project label はヘッダー帯であり、terminal layout を自身の高さぶん押し下げる
14. オーバーレイ(ノート編集・一望モード・レイアウト型選択・
    プロジェクト一覧)は workspace 層のものであり、project overlay ではない。
    常設の overlay は存在しない(§6.1, §7.2)
15. project zoom と pane zoom は外側から内側へ適用する
16. hidden project は focus の直接対象にならない(プロジェクト境界の
    resize / equalize は存在しない、§26.4)
17. 最後の visible project は hide できない(即時 hide・一覧トグルとも、§25)
18. project が複数あるとき、最後の pane で close_surface すると close_project
    confirmation に昇格する（唯一の project では通常の close_surface として
    window close → app 終了になる。§11.10, §18.5）
19. visible project 数は常に ≤ 9（§7.3。登録総数は無制限）
20. visible project の序数は台帳の visible な行を上から数えた順で
    1～visibleCount となり、台帳の変更時に自動 re-pack される
    (表示のみ、保存しない。§7.3, §27.1)
21. restore 時は normalizeLedger が台帳を修復し(順列・生存・上限 9・
    最低 1 visible)、relayout が配置を再導出する(§12.4)
22. 優先度・締切・次トリガー・ノートの値変更は台帳の行順を変えない
    (並び替えは明示のソート・行移動のみ、§24.4)
```

## 15. 実装フェーズ

(MVP 構築時の計画記録。`new_project_split` / `resize_project` /
`equalize_projects` は 2026-08-18 改訂で廃止済み — 現行仕様は §9〜§11 を参照。)

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

### Phase 5: zoom / hide

成功条件:

```text
- toggle_project_zoom が project単位で動く
- zoom中 Cmd+D は project内splitになる
- zoom中 new_project_split は zoom解除して隣にproject作成
- hide_project は process を殺さない
- hidden になったプロジェクトが復帰導線から visible に戻せる
  (当初は右上の hidden shelf。現在はプロジェクト一覧の Space トグル、§7.2/§27)
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
  TerminalWorkspaceView.swift
  ProjectNoteEditor.swift
  ProjectNoteOverview.swift
  NoteEditHistory.swift            (ノート編集セッションの取り消し履歴、§21.2)
  ProjectTerminatedPaneView.swift  (§23.3)
  ProjectLayoutType.swift          (レイアウト型・スロット計算・畳み込み、§26.1-26.2)
  ProjectLayoutSelector.swift      (レイアウト型選択オーバーレイ、§26.2)
  ProjectList.swift                (台帳の行/列/セル機構と日次優先度リセット、§27.1-27.2/§28.2)
  ProjectListOverlay.swift         (プロジェクト一覧(台帳)オーバーレイ、§27)
  ProjectWorkday.swift             (作業日と 06:00 境界、§28.1)
  ProjectRemoteSplit.swift         (リモート split の起動判断とレポート鮮度、§29)
  PaneForegroundProbe.swift        (pty の前景プロセス取得、§29.3)
  ProjectOverlayKeys.swift         (オーバーレイ共有のローカル keyDown モニタ、§21.2)
```

`HiddenProjectShelf.swift` は hidden シェルフの廃止に伴い削除済み(§7.2)。
`ProjectHideSelector.swift` / `ProjectLayout.swift`(登録レイアウト 11 種)は
2026-08-18 改訂の即時 hide(§25)とレイアウト型(§26)への置き換えに伴い
削除済み。

(close 確認ダイアログは専用ファイルではなく `BaseTerminalController` の既存
確認経路を流用する。§23.1)

既存 split と密接に関わるため、最終的には `Features/Splits` 配下に統合してもよい。
ただし初期実装では `Features/Projects` として分離した方が差分を追いやすい。

## 17. Action parser 追加方針

(MVP 構築時の方針記録。現行の action 集合は §9.1 が正 —
`newProjectSplit` / `resizeProject` / `equalizeProjects` は削除済みで、
`new_project` / `move_project` / ノート・ソート・一覧・レイアウト型の各 action
が加わっている。)

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

hidden な project を一覧から直接 close する機能は持たない。
close 対象は visible focused project のみ(一覧で Space により visible に
戻してから close する)。

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

### 18.4 zoomed project 中の `new_project`

```text
1. zoom解除(beginProjectList が先に解除する、§27.3)
2. 一覧が開き、カーソル行の直下に新規行が挿入される(§27.4)
3. タイトル編集がその場で始まる。focus は一覧が保持する
```

(旧 `new_project_split` の「zoom 解除して隣に作成」は action 廃止に伴い消滅。)

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

(MVP 構築時の計画記録。現行のテストは各仕様節末尾のテスト小節 —
§21.4/§22.8/§23.5/§24.5/§25/§26.5/§27.5/§28.4/§29.4 — が正。)

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
- the project list (Cmd+L) lists hidden projects too, and Space shows them again
- close_project dialog has only Cancel / Close Project
```

## 20. 最終MVP仕様サマリ

(MVP 完了時点のスナップショット。以後の改訂で置き換わった点 —
`Cmd+Opt+D` 分割作成 → `Cmd+N` 一覧作成(§27.4)、プロジェクト
resize/equalize の廃止(§26.4)、hidden 状態の永続化と台帳復元(§12)、
序数の台帳由来化(§7.3)— は各節が正。)

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
  常設表示なし（§7.2）
  プロジェクト一覧（Cmd+L、§27）が hidden を含む全プロジェクトを列挙
  一覧の Space で即show（ただし visible が 9 個では no-op）

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

MVP 時点の核は「`canonicalProjectTree` を唯一の配置 source of truth にする」
ことだった。2026-08-18 改訂でこの主従は逆転し、**台帳(§27.1)が source of
truth、tree は投影**になった(§4.1)— それでもプロジェクトが第一級レイアウト
単位であること、既存のペイン分割・surface lifetime・Ghostty の SplitTree 設計を
壊さないこと、表示上限 9 と動的序数で UI の安定性と操作性を両立することは
変わらない。

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

### 21.2 編集オーバーレイ(edit_project_note / Cmd+E)

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
- **取り消し・やり直しはセッション内の自前履歴**(`NoteEditHistory`):
  オーバーレイ表示中の `Cmd+Z` が取り消し、`Cmd+Shift+Z` がやり直しで、
  上の標準ショートカットと同じ `OverlayKeyDownMonitor` が chord を捕まえる。
  - **スコープはノート本文のみ**。優先度・締切のドラフトは履歴に入らない。
  - **寿命は 1 編集セッション**:履歴はエディタを開いた時点の本文から始まり
    (`NoteEditHistory(note)`)、保存・破棄いずれの経路でも閉じると同時に
    捨てられる。前回セッションの編集は取り消せない。
  - responder chain の `NSUndoManager` を使わない理由:それは**ウィンドウの**
    undo manager であり、プロジェクトレイヤー自身の undo エントリ
    (hide / show / apply layout)を保持している。そこへ `Cmd+Z` を流すと
    ノート編集の取り消しがワークスペース操作の取り消しに化ける。
  - **連続入力は 1 ステップに畳む**:直前の記録から `coalescingWindow`
    (0.75 秒)以内、かつ文字数差が 1 以内の変更は同じタイピング run の
    継続とみなしてステップ境界を積まない。ペースト・カット・選択置換などの
    大きい変更は常に自前のステップになるため、10 行ペーストは 1 回の
    `Cmd+Z` で戻る。undo / redo 自体は run を打ち切る
    (`lastRecordedAt = nil`)。
  - 記録は**値の変化がある場合のみ**(`record` は同値を無視)。undo の結果を
    エディタへ書き戻したときの変更通知が履歴を汚さないのは、この冪等性による。
    新しい編集を記録した時点で redo スタックは捨てられる。
- **貼り付けで 10 行を超えた場合も保存時に先頭 10 行へ切り詰める**(手入力と
  同じ §21.1 の正規化経路。CRLF / CR の行末は正規化で `\n` に統一されるため、
  ペースト由来の行末でもキャップは回避されない)。
- **ノート本文専用**:優先度・締切はプロジェクト一覧のセルで設定する
  (§24.1, §27.2)。旧 metaRow(優先度 picker + 締切フィールド)は
  2026-08-18 改訂で削除した — このオーバーレイが保存するのはノート本文のみ。
- 閉じると(保存・破棄どちらでも)first responder は端末 surface に戻る。
- オーバーレイは編集中のみ描画され、端末領域を恒久的に占有しない。
- 編集対象プロジェクトが消えた場合(undo 復元・全プロジェクト削除)はセッションを
  クリアする。

### 21.3 一望モード(toggle_note_overview / Cmd+Opt+E)

- visible な全プロジェクトの上に、それぞれのノート — 優先度・締切・次トリガー
  と併せて(§24.2, §24.6)— を同時に読み取り専用オーバーレイ表示するトグル
  モード。状態は `WorkspaceModel.noteOverviewActive`(transient、永続化
  しない)。一覧の中の `Cmd+Opt+E` は別物(全行ノート表示トグル、§27.2)—
  オーバーレイセッションは相互排他なので、一覧が開いている間このモードには
  入れず、chord は衝突しない。
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
- 退出は**再度 Cmd+Opt+E または Esc**。退出時に first responder は端末
  surface に戻る。実装上、モード中は surface が unfocused で keybind 経路が
  効かないため、Esc は捕捉層内の focused field の `onExitCommand`、
  再トグルはデフォルト chord (cmd+opt+e) を再照合する隠し
  `keyboardShortcut` ボタンで受ける(keybind を変更した場合の退出は Esc)。
- **切り詰め表示**: 各プロジェクトのパネルは `lineLimit(maxNoteLines)` +
  末尾切り詰めをプロジェクト境界内のフレームで行い、レイアウトを壊さない。
  全文表示は編集オーバーレイの役割。
- undo 復元(`restoreState`)・全プロジェクト削除はモードを終了させる
  (復元された zoom が「zoom 解除済み」不変条件と矛盾しないように)。

### 21.4 テスト(ProjectNoteTests 41 件 / ProjectNoteUndoTests 8 件)

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

取り消し履歴(ProjectNoteUndoTests):

```text
- 初期状態: 開いた直後は canUndo/canRedo とも false
- 取り消し: undo が開いた時点の本文へ戻る
- 畳み込み: 連続入力は 1 ステップ / 0.75 秒を超える間があくと新ステップ /
  ペーストは常に自前ステップ(1 回の undo で戻る)
- redo: undo の後に効き、次の編集で捨てられる
- run の打ち切り: undo 直後の入力は前ステップに畳まれない
- 冪等性: 同値の再記録は履歴を変えない(undo 結果の書き戻しが汚さない)
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

## 24. 優先度・締切・次トリガー仕様

プロジェクトごとの優先度・締切・次トリガー(§24.6)を保持・表示し、明示的な
ソートアクションで台帳の行順を並び替える層。保持・復元・ソート順・締切超過判定は
すべてモデル層に置き、`XGhosttyTests` から検証する(§24.5)。設定・変更の入口は
**プロジェクト一覧のセル**(§27.2)であり、ノート編集オーバーレイからは設定
しない(2026-08-18 改訂で入口を移設。必須対応事項 36)。

### 24.1 データモデルと入力境界

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
- **設定入口はプロジェクト一覧のセル**(§27.2):優先度・次トリガーは `Space`
  循環、締切はテキストセル編集に加えて **Space 送り**(`Space` = 今日 /
  +1 日、`Shift+Space` = -1 日・今日から未設定へ。§27.2、必須 77)で設定・
  変更する(セル確定が `setProjectDeadline(parsing:)` を通るため、セルの
  挙動と保存時判断は乖離しえない)。ノート編集オーバーレイ(§21.2)は
  ノート本文専用で、優先度・締切のコントロールを持たない(2026-08-18 改訂で
  旧 metaRow を削除。必須対応事項 36)。

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

- `priorityOrderedProjectIDs()`:high → medium → low → 未設定。
- `deadlineOrderedProjectIDs()`:近い日付順、未設定は末尾。
- 共通契約:入力は台帳の**全行**(`projectOrder`。hidden を含む —
  2026-08-18 改訂で visible-only から全行へ。必須対応事項 40〜43)、純関数で
  副作用なし、**安定性は構成で保証**(stdlib の sort は安定性を文書化しない
  ため、enumerated + offset の明示タイブレーク)。同順位・同日は現在の相対順を
  維持する。次トリガー順のソートは設けない(必須対応事項 43)。

### 24.4 ソートアクション(sort_projects_by_priority / sort_projects_by_deadline)

- `sort_projects_by_priority`(既定 `Cmd+S`)/ `sort_projects_by_deadline`
  (既定 `Cmd+Shift+S`)。§10.5 のとおり両 chord とも既存割り当てなし。
- 実行:`sortProjectsByPriority()` / `sortProjectsByDeadline()` が §24.3 の
  順序を**台帳の行順 `projectOrder` へ適用**する(2026-08-18 改訂:leaf の
  載せ替えではなく台帳の並び替え)。hidden を含む全行が並び替わり、
  `relayout()` が visible 行の新しい順で配置を再導出する(§26.3)。
- 帰結(いずれも構成から従う):
  - 序数(Cmd+1〜9)は**ソート後の並びの visible 行を上から数えた順**になり
    自動追従する。
  - focus は id ベースなので不変。
  - **一覧を開いていなくても効き**、開いていれば行が live に並び替わる
    (必須対応事項 42)。
  - **明示実行時のみソート**:優先度・締切の setter は台帳の行順に触れない
    ため、値の変更・毎朝リセット(§28)で自動再ソートは起きない。
  - ソート後の並びは次のソートまたは手動の行移動(§27.1)まで持続する。
  - zoom 中も実行可(台帳は表示非依存。zoom 解除時に新しい並びが見える)。

### 24.5 テスト(ProjectPriorityDeadlineTests、20 件)

```text
- 既定: 新規プロジェクトは優先度・締切とも未設定
- 永続化: 優先度+締切の round trip 復元 / 壊れた保存(未知 priority 文字列・
  実在しない日付)は unset として decode
- 入力境界: 不正日付は未設定へ拒否(前の値も残らない)/ 空入力は意図的
  クリア / parser は実在日付のみ受理(閏日含む)/ today 導出は時刻を捨てる
- 超過: 締切日より厳密に後のみ / 未設定は非超過 / hidden も判定対象
- 順序付け: 優先度順(安定タイ)/ 締切順(未設定末尾・同日安定)/
  hidden を含む全行・無副作用
- ソートアクション: 台帳の行順の並び替え(優先度・締切とも)/ ソート後の
  序数が visible 行を上から数えた順 / focus 不変 / 明示実行のみで次の
  ソートまで持続
- setter: 不正締切は unset へ / 未知プロジェクト setter no-op
```

### 24.6 次トリガー(ProjectNextTrigger)

- プロジェクトごとの**次トリガー = プロジェクトを次に動かす主体**。
  `ProjectNextTrigger`:String-raw の Codable enum
  (`myself` 自分 / `teamMember` チームメンバー / `externalPerson` 組織外部人 /
  `event` イベント)。未設定は値の不在(Optional)で、既定は未設定
  (必須対応事項 71)。
- 書込み口は `setProjectNextTrigger`(未知プロジェクト・無変化は no-op)。
  設定・変更は一覧のセルの `Space` 循環(§27.2)。
- 永続化は優先度と同じ ProjectState レコード(`encodeIfPresent`、不正保存は
  unset として decode)。
- **表示は一望モードのみ**:ノート・優先度・締切と併せて表示する(§21.3)。
  **ラベル帯には表示しない**(§24.2 の meta 表示は優先度・締切のみ)。
  読み出しは `displayText` の**素の値**(me / team / external / event)—
  `next:` prefix は付けない(2026-08-18 の人間実機確認で除去。一望モードでは
  ノートの隣、一覧では `next` 列ヘッダの下にあり、値だけで自明)。
- 毎朝の優先度リセット(§28)は次トリガーに**触れない**(締切・ノートと同様)。
- 人間が書き込む情報であり、端末が観測するライブ状態(非対応事項の将来候補)
  とは別物。
- テスト:ProjectNextTriggerTests(6 件)— round trip 復元・既定未設定・
  一望モードの表示内容に含まれる・リセット生存・不正保存の unset decode・
  setter no-op。

## 25. 即時 hide 仕様

`Cmd+Opt+H`(`hide_project` action)は focused プロジェクトを**即座に hidden に
する**。選択画面は開かない(2026-08-18 改訂で hide 選択画面から即時 hide へ
戻した。必須対応事項 46。旧 `ProjectHideSelector` / hide 選択モデルは削除済み)。
判断ロジックはモデル層に置き、`XGhosttyTests` から検証する(本節末尾)。

### モデル判断と実行

- `canHideFocusedProject`:hide 後も**最低 1 つは visible に残る**こと
  (visible プロジェクト 2 つ以上)。performable チェックと実行が同じ判定を
  共有し、不成立時はキー未消費で fall through する(`set_primary` と同型)。
  同じ「最低 1 つ visible」拒否は一覧の表示トグル(§27.2)にも適用される
  (必須対応事項 47)。
- 実行 `hideFocusedProject(savingOutgoingPaneTree:)`:
  1. focus の移動先を hide 前の配置上で解決する(nearest 規則)
  2. 台帳の hidden フラグを立てる(`setProjectHidden(id, true)`)—
     台帳の**行はそのまま**残り、visibility 列だけが変わる(§27.1)
  3. `relayout()` が記憶しているレイアウト型で残りの visible 行の配置を
     即座に再導出する(§26.3 の自動適用。hide 直後に選択画面もリサイズ操作も
     介在しない)
  4. process / PTY / surface は生存(`ProjectState` は `projects` に残る)
  5. zoom バックストップと `snapFocusToPrimaryInOverallView` を適用する
- 復帰導線はプロジェクト一覧のみ(§7.2, §27)。hidden シェルフは廃止済みの
  まま(必須対応事項 48)。
- controller は 1 hide につき 1 つの「Hide Project」undo を登録する。

### テスト(WorkspaceModelTests 内)

```text
- hide: focused プロジェクトだけが hidden になり、focus が生存者へ移る
- 拒否: 最後の visible プロジェクトの hide は拒否(canHideFocusedProject =
  false、実行は nil)/ 他プロジェクトが既に hidden の場合も同様
- 再配置: hide 直後に残りの行が記憶しているレイアウト型で組み直される
  (§26.3 の relayout 経由。ProjectLedgerTests の自動適用テストが検証)
```

## 26. レイアウト型仕様

全体ビューの配置を**レイアウト型 = 形 × 向き**の規則として記憶し、visible な
表示数が変わるたびに同じ型で自動適用する層(2026-08-18 改訂で登録レイアウト
11 種の一手適用を置き換えた。必須対応事項 49〜56)。「適用中のレイアウト」を
持たなかった旧設計と異なり、**型は永続状態**であり、配置は台帳(§27.1)と型から
常に再導出される投影である。スロット計算・畳み込み・導出の判断ロジックは
モデル層(`ProjectLayoutType.swift`)に置き、`XGhosttyTests` から検証する
(§26.5)。

### 26.1 レイアウト型とスロット計算(ProjectLayoutType)

- `ProjectLayoutType` = `Shape`(`wide` 横長型 / `tall` 縦長型 / `pedestal`
  台座型)× `Orientation`(`rowMajor` 行送り / `columnMajor` 列送り)。
  ユーザー定義レイアウトは存在しない(非対応事項)。
- **横長型**:行数 = √n に最も近い整数のグリッドに、上の行からできるだけ
  均等に配る(余りは上の行から 1 つずつ)— 4 = 2+2、5 = 3+2、6 = 3+3、
  7 = 3+2+2、8 = 3+3+2、9 = 3+3+3。行高・行内幅は等分。
- **縦長型**:横長型の転置。列数 = √n に最も近い整数、左の列から均等に配り、
  列幅・列内高を等分。
- **台座型**:n−1 個を上部に(行送りは横長型・列送りは縦長型の規則で)配置し、
  1 個を最下段に全幅で置く。
- **向きは序数の進み方**:行送りは上の行から左→右、列送りは左の列から上→下。
  横長型・縦長型では向きは割り当て順だけを変え、形は変えない。台座型の最下段は
  常に最後。
- `slots(forVisibleCount:)` が単位正方形上の `Slot`(frame + row/column)列を
  **割り当て順**で返す。`tree(over:)` がスロット列を入れ子の等比 split
  (`SplitTree`)として構築し、走査順は割り当て順と一致する。

### 26.2 選択肢の畳み込みと選択オーバーレイ(choose_project_layout / Cmd+Opt+L)

- 各 visible 数(1〜9)の選択肢は `choices(forVisibleCount:)`:形 3 × 向き 2 の
  6 通りから、**配置と序数の進み方が完全一致するものを 1 つに畳んだ**集合
  (例:n=9 は横長型と縦長型が形は同じでも向きが違うため畳まれず、n=3 の
  台座型・行送りは横長型・行送りと一致して畳まれる。n=1 は 1 択)。
- `choose_project_layout`(既定 `Cmd+Opt+L`、§10.5)が選択オーバーレイ
  `ProjectLayoutSelector` を開く。performability は `canBeginLayoutSelection`
  (visible プロジェクト 1 つ以上 + 他のオーバーレイなし)で、不成立時は
  キー未消費で fall through する。`beginLayoutSelection` は zoom を先に解除する
  (zoom 中呼び出しの挙動は Essence が実装に委ねた部分)。セッション状態は
  transient で、`restoreState` / `removeAllProjects` が終了する。
- オーバーレイは**現在の visible 数に対する選択肢だけ**を列挙し、矢印で選んで
  Enter で適用、Esc で何も変えずに閉じる。**プロジェクト数は一切変えない**
  (旧設計の不足分新規作成・超過分 hide-pick は廃止)。選択肢が 1 つのときは
  選ぶものが無い旨を表示するだけとする(必須対応事項 50)。
- オーバーレイは呼び出し中のみ描画され、抜ければ端末が全面に戻る。

### 26.3 台帳 → 配置の導出(relayout)

- 配置の導出は `WorkspaceState.relayout()` の 1 点:
  `canonicalProjectTree = layoutType.tree(over: visibleProjectIDs)` —
  台帳(§27.1)の visible な行を行順のまま、記憶している型のスロットへ
  割り当てる(行送りは上の行から左→右、列送りは左の列から上→下、台座型の
  最下段は最後)。序数(Cmd+1〜9)は visible 行を上から数えた順なので、
  配置は常に序数に追従する。
- **自動適用**:`projectOrder` / `hiddenProjectIDs` / `layoutType` を変える
  すべての変更(一覧の表示トグル・`Cmd+Opt+H`・新規作成・close・行移動・
  ソート・型選択)と復元の後に `relayout()` が呼ばれる。visible 数が変わらない
  操作(終了済み状態への遷移等)は台帳に触れないため発火しない
  (必須対応事項 54)。
- visible でなくなったプロジェクトへの zoom は relayout が解除する。

### 26.4 永続化と既定

- 選んだ型は `WorkspaceState.layoutType` として永続化され、再起動後も維持
  される。保存が無いとき(レガシー保存・新規ワークスペース)の既定は
  **横長型・行送り**(`ProjectLayoutType.default`)。
- `canonicalProjectTree` は台帳と型からの投影なので**永続化しない**(§12)。
  旧保存の tree は decode 時に行順の種としてのみ読まれる。
- プロジェクト単位のレイアウト resize / equalize は**廃止**
  (`resize_project` / `equalize_projects` action ごと削除、§9.1)。
  プロジェクト境界は動かせない。zoom 中のプロジェクト内ペイン(split)の
  resize / equalize は従来どおり有効(必須対応事項 55)。

### 26.5 テスト(ProjectLayoutTypeTests 13 件 / ProjectLayoutSelectionTests 10 件)

```text
- スロット計算: visible 数 1〜9 の各々で横長・縦長・台座 × 行送り・列送りの
  スロットが定義どおり(√n 行配分・転置・台座の最下段全幅・等分)
- 割り当て順: 行送りは上の行から左→右、列送りは左の列から上→下、台座の
  最下段は最後 — 序数がそれに追従する
- 畳み込み: 配置と序数の進み方が完全一致する選択肢は 1 つに畳まれる
  (n=9 の横長/縦長は畳まれない、n=3 の台座・行送りは横長・行送りへ畳まれる)
- 永続化: 型の round trip 復元 / 保存が無ければ横長型・行送り
- 自動適用: visible 数が変わる操作の後、記憶している型で新しい数の配置が
  導かれる / 変わらない操作では配置が変わらない(ProjectLedgerTests)
- 選択セッション: 現在の visible 数の選択肢だけを列挙 / 1 択のときは選ぶ
  ものが無い / Enter で適用・Esc で無変化 / プロジェクト数は変わらない
```

## 27. プロジェクト一覧仕様(台帳)

hidden を含む**全プロジェクト**を載せた一覧は、全体像を把握し統括管理する
**台帳(source of truth)**である(2026-08-18 改訂の主従逆転)。行順・列順・
各行の visibility は永続状態であり、画面配置はそこからレイアウト型(§26)で
導かれる投影にすぎない。一覧は hidden プロジェクトの**唯一の復帰導線**であり
(hidden シェルフは廃止、§7.2)、新規プロジェクト作成の**唯一の導線**でもある
(§27.4)。行の内容・並び・セル編集の確定と取り消し・締切の Space 送りの
日付計算・トグル可否・focus 可否・新規行の表示状態の判断はすべてモデル層
(`ProjectList.swift` / `WorkspaceState.swift`)に置き、`XGhosttyTests` から
検証する(§27.5)。

### 27.1 台帳と一覧の形(projectOrder / ProjectListRow / ProjectListColumn)

- 台帳の実体は `WorkspaceState` の永続フィールド 3 つ:
  - `projectOrder: [ProjectID]` — hidden を含む全プロジェクトの**単一の行順**
    (visible / hidden で区画分けしない)。`projects.keys` の順列という不変条件を
    持ち、decode 後は `normalizeLedger()` が修復する(未知 id は落ち、
    載っていないプロジェクトは作成順で末尾に足される)。
  - `hiddenProjectIDs: Set<ProjectID>` — 一覧の visibility 列。**永続化される**
    (2026-08-18 改訂で runtime-only から昇格、§12.1)。
  - `listColumnOrder: [ProjectListColumn]` — 列順。既定は
    **表示・タイトル・優先度・締切・次トリガー・ノート**の 6 列。
- **序数(Cmd+1〜9)は visible な行を上から数えた順**
  (`visibleProjectIDs = projectOrder.filter { !hidden }`、`ordinal(of:)`)。
  ツリーの走査順ではなく台帳が序数を定義し、配置が序数に追従する(§26.3)。
- `ProjectListRow` は行の純粋導出(`projectListRows`):タイトル・序数
  (hidden は nil)・優先度・締切・次トリガー・ノート 1 行目。未設定は未設定の
  まま運び、空欄に描くのは view の仕事。ノート列は通常 1 行目のみを表示し、
  全行表示トグル(§27.2)が全文を描く。
- 行順の入れ替えは `moveProjectRow(_:to:)`(一覧では `Cmd+↑`/`Cmd+↓`、端で
  クランプ)、列順の入れ替えは `moveListColumn(_:by:)`(`Cmd+←`/`Cmd+→`)。
  どちらも永続化され、閉じて開き直しても残る。セッションラッパー
  (`moveProjectListRow` / `moveProjectListColumn`)は**移動後の index を返し**
  (クランプで動かなければ nil)、セルカーソルはその報告に追従する — 連続で
  押しても常に**同じ行・列**に掛かり、端ではカーソルも動かない。view 側で
  delta を再適用しない(モデルの報告が判断)。
- オーバーレイはウィンドウの幅・高さそれぞれ**8 割程度**を占め、行が収まらない
  ときはスクロールしてセルカーソルに追従する(zoom 中に呼び出した場合の挙動は
  定めず、実装に任せる)。列幅はヘッダ帯とセルが共有する単一規則
  (`columnFrame`):タイトル・ノートは固定列の残り幅を等分する可変幅、
  表示・優先度・締切・次トリガーは各列の最長値が収まる固定幅。

### 27.2 セル機構(カーソル・編集・Space・全行ノート)

- **セルカーソル**(`ProjectListCellCursor`):`Tab` 右 / `Shift+Tab` 左 /
  `Enter` 下 / `Shift+Enter` 上(矢印キーも同じ)。行末の `Tab` は次の行の
  先頭へ折り返し、最終行の `Enter` はそこで止まる(グリッドの角は吸収)。
- **テキスト列**(タイトル・締切・ノート)は文字を打つと編集が始まる
  (`ProjectListCellEdit`:編集開始時の `original` とドラフト)。`Enter` /
  `Tab` で確定して移動、`Esc` は**その編集だけ**を取り消して元の値に戻す。
  確定は `commitListCellEdit`:タイトルは rename と同じ正規化(§9.1)、
  締切は §24.1 の保存時境界(不正入力は未設定へ)、**ノート列の確定は 1 行目
  だけを書き換え、2 行目以降は保持する**(複数行編集は `Cmd+E` の
  オーバーレイの役割、§21.2)。
- **選択式の列**(表示・優先度・次トリガー)は `Space` で値が循環する
  (`cycledSelectionValue`。優先度:未設定→high→medium→low→未設定、
  次トリガー:未設定→自分→チームメンバー→組織外部人→イベント→未設定)。
  **表示列は 2 値のトグルで即時反映**:`setProjectHidden` が台帳を書き、
  `relayout()` が背後の配置を即座に組み直す(§26.3)。確定ステップは無く、
  Esc で一覧を閉じてもトグルは残る。可否は `canToggleProjectVisibility`:
  hidden → visible は表示上限 9(§7.3)、visible → hidden は**最低 1 つは
  visible に残す**(§25 と同じ規則)。
- **締切セルの Space 送り**(2026-08-18 改訂・必須 77):編集していない状態の
  締切セルでの `Space` は**編集開始ではなく日送り** — 未設定なら今日を設定し、
  日付があればその日付から 1 日進める。`Shift+Space` は 1 日戻し、**ちょうど
  今日**の状態からさらに戻すと未設定に戻る。未設定での `Shift+Space` は何も
  しない。判断は純関数 `ProjectDeadline.stepped(_:forward:today:)`
  (日付演算は `advanced(by:)`、月末・年末を繰り上げ)、変異は
  `stepListDeadline`。各押下は選択式の列と同様に**即時確定**で編集セッションに
  属さず(`ProjectListCellEdit` は関与しない)、`Esc` でも取り消されない。
  文字入力(タイプによる編集・確定・取り消し)は従来どおり残り、**過去日の
  設定は文字入力で行う**(必須 65 のテキスト列規則は締切セルでは必須 77 が
  特定化する)。
- **全行ノート表示**(`Cmd+Opt+E`、一覧の中でのみ):全行のノートを全行表示に
  するトグル。閲覧のみ・行ごとではなく一括・状態は透過的(セッション開始時は
  常に 1 行表示、永続化しない)。一望モードの `toggle_note_overview` とは
  別物(オーバーレイセッションは相互排他なので chord は衝突しない)。
- 編集していないときの `Esc` は一覧を閉じる(§27.3)。

### 27.3 Cmd+Enter / Escape とセッション

- **focus は `Cmd+Enter`**(2026-08-18 改訂で Enter を下セル移動に譲った)。
  `canFocusProjectListRow(id)`:**visible な行のみ** true。hidden な行には
  画面上の focus 先が無いので `Cmd+Enter` は完全な no-op で、一覧も開いたまま
  残る。
- `focusProjectListRow(id)`:セッションを閉じ、対象を `focusedProject` にし、
  全体ビューに着地するので focus はそのプロジェクトの**プライマリーペイン**へ
  寄る(§22.4)。undo は登録しない(focus 変更のため)。
- Escape(`closeProjectList`)は編集中でなければ一覧を閉じる。トグル・確定済み
  セル編集・行/列移動はすべて実変更として残る。focus は「いま focused な
  プロジェクト」へ戻す。
- セッション状態 `projectListActive` は transient(永続化しない)。
  `canBeginProjectList` は「プロジェクトが 1 つ以上あり、ノートエディタも他の
  オーバーレイも出ていない」— 各オーバーレイはキーボードを単独で占有する。
  `beginProjectList` は**先に zoom を解除**する(一覧は全体ビューを説明する
  ものなので)。`restoreState` / `removeAllProjects` はセッションを終了する。

### 27.4 新規プロジェクト作成(new_project / Cmd+N)

- `new_project` action(既定 `Cmd+N`)が**唯一の作成導線**
  (`new_project_split` と `Cmd+Opt+D` / `Cmd+Opt+Shift+D` は廃止、§9.1。
  メニューの作成項目も同じ経路)。
- **一覧の中**:カーソル行の直下に新規プロジェクトを挿入
  (`insertProject(_:after:)`)し、通常の新規作成と同様に新しいシェルを起動
  (fresh `SurfaceView`、`ProjectNameGenerator` 名、初期ペインがプライマリー)。
  カーソルは新しい行のタイトル列に移り、**その場でタイトル編集が始まる**
  (`pendingTitleEdit`)。
- **一覧の外**:一覧を開いて同じ状態にする(挿入位置はカーソル初期行の直下)。
- **新規行の表示状態はモデル判断**:挿入前の visible 数が 9 未満なら visible、
  9 なら hidden(表示上限 §7.3 を作成でも守る)。visible での挿入は
  `relayout()` が配置を即座に組み直す。
- controller は作成 1 回につき 1 つの undo を登録する。

### 27.5 テスト(ProjectLedgerTests 10 件 / ProjectListCellTests 24 件 / ProjectListTests 14 件)

```text
- 台帳: 行 = hidden を含む全プロジェクトの単一順(区画分けなし)/ 序数は
  visible 行を上から数えた順で hidden を飛ばす / 既定列順 = 表示・タイトル・
  優先度・締切・次トリガー・ノート / 行順・列順の入れ替えと round trip 復元 /
  配置が台帳の全変更と復元で再導出される / 挿入はアンカー行の直下・上限では
  hidden / 連続 N 回の行・列入替の結果順と、返る index が常に移動対象の
  現在位置(カーソル追従)・端のクランプは nil
- セルカーソル: Tab/Shift+Tab/Enter/Shift+Enter の移動 / 行末の折り返し /
  最終行での停止
- セル編集: テキスト列の確定で値が反映・Esc の取り消しで元の値 / ノート列は
  1 行目だけを書き換え 2 行目以降を保持 / 不正な締切入力は未設定 /
  選択式列の Space 循環 / 表示列のトグルは即時反映・最後の visible と
  表示上限で拒否
- 締切 Space 送り: 未設定 + Space = 今日・日付 + Space = +1 日(月末・年末
  繰り上げ)/ Shift+Space = -1 日・ちょうど今日から戻すと未設定・未設定では
  no-op / 各押下は編集セッション外の即時確定(セッション gating・typed edit
  との独立)
- focus: Cmd+Enter は visible 行で focus して閉じる / hidden 行は何も起きず
  一覧が残る
- セッション: begin は zoom 解除・他オーバーレイ中は拒否 / Esc で閉じても
  実変更は残る / 全行ノートトグルは transient
```

## 28. 優先度の毎朝リセット仕様

優先度は恒久属性ではなく「今日のフォーカス」である。したがって毎朝ローカル
6:00 を境界に未設定へ戻す。判定ロジック(境界・対象・1 日 1 回)はモデル層に
置き、`XGhosttyTests` から検証する(§28.4)。

### 28.1 作業日(Workday)

```swift
struct Workday: Codable, Equatable, Hashable {
    static var boundaryHour: Int { 6 }
    let year: Int, month: Int, day: Int

    init(containing date: Date, calendar: Calendar = .current)
    static func nextBoundary(after date: Date, calendar: Calendar = .current) -> Date?
}
```

- **作業日 = ローカル 6:00 から翌 6:00 まで**。値は作業日の**開始日**の暦日
  なので、「同じ作業日か」が単純な等値比較になる。
- 6:00 より前の時刻は前日の作業日に属する。境界が深夜 0:00 ではなく 6:00 なのは、
  日付をまたいで続けた作業を始めた日の側に置くため。
- 巻き戻しは「6 時間引く」ではなく**カレンダー演算**(`byAdding: .day, -1`)。
  DST 遷移が結果を 1 日ずらさないようにするため。
- `nextBoundary(after:)` も固定秒数の加算ではなくカレンダーの
  `nextDate(matching: hour 6)`。DST でも壁時計どおりの 6:00 に着地する。
  `nil` は「スケジュールしない」を意味する。
- 永続形式は正準テキスト `YYYY-MM-DD`(保存が読めるように)。壊れた値は
  decode エラーになり、workspace 側の寛容な decode が「未リセット」に落とす —
  リセットは優先度を消すだけなので、安全側に倒れる。

### 28.2 リセット判定(1 日 1 回)

- 永続フィールドは `WorkspaceStateOf.lastPriorityResetWorkday: Workday?`
  (workspace state の Codable 経路。キー名も同じ)。
- `needsPriorityReset(at:calendar:)` は
  `lastPriorityResetWorkday != Workday(containing: now)` の 1 行。未リセット
  (新規ワークスペース、リセット導入前の保存)は常に due — 規則を文字どおり
  読んだ結果で、実害も無い。
- `resetPrioritiesIfNeeded(at:calendar:)` は due のときだけ、**hidden を含む
  全プロジェクト**の `priority` を `nil` にし、現在の作業日を刻む。実行したかを
  返す。
- **意図的に狭い**:締切・ノート・次トリガー(§24.6)は触らず、台帳の行順
  (`projectOrder`)を書かないので**並び替えは構造的に起こり得ない**。

### 28.3 トリガ(BaseTerminalController)

`startDailyPriorityResetTriggers()` が 4 つを設置する:

```text
1. 起動時       … init 末尾で 1 回チェック
2. 境界タイマ   … Workday.nextBoundary(after: now) に 1 発の Timer。
                  RunLoop.main へ .common モードで追加(メニュー追跡や
                  リサイズループが遅らせないように)。発火ごとに再武装する
3. 再アクティブ … NSApplication.didBecomeActiveNotification
4. スリープ復帰 … NSWorkspace.didWakeNotification
```

- 3・4 が要るのは、タイマだけでは足りないから:スリープ中や背面のまま 6:00 を
  跨ぐと、タイマは停止・合体されて発火時刻を大きく過ぎうる。3・4 はチェック後に
  タイマを**再武装**もする(時計が大きく進んでいる可能性があるため)。
- 重複トリガが無害なのは §28.2 の冪等性による(作業日を刻むので 2 回目は
  no-op)。「多く走りすぎる」は構造的に起こらない。
- **通知も印も出さない。並び替えもしない** — ソートは明示アクション時のみ
  (§24.4)。優先度しか変わらないので undo エントリも登録しない。
- `deinit` でタイマを invalidate し、両 observer を外す。

### 28.4 テスト(ProjectPriorityResetTests、9 件)

```text
- 作業日: ローカル 6:00 から翌 6:00 まで / 最終リセット日付と現在時刻から
  境界跨ぎを判定 / 次の境界は来たるローカル 6:00
- リセット: hidden を含む全プロジェクトの優先度が未設定になる /
  並び順は変わらない / 同じ作業日内では 2 回目が起きない /
  稼働中の跨ぎでも 1 回だけ
- 永続化: lastPriorityResetWorkday が保存・復元される /
  当該キーの無い保存は「未リセット」として decode される
```

## 29. リモート split 仕様

リモートホストで作業中のペインを split したとき、新ペインを**同じホスト・
同じパス**で開く層。判定はモデル層に閉じ、`XGhosttyTests` から検証する
(§29.4、必須対応事項 62)。判断材料の OSC 7 レポートを apprt まで運ぶために、
上流ターミナルコアには最小限の改変を入れてある(`stream_handler.reportPwd` が
非ローカル報告を捨てずに path + host を apprt へ転送し、`apprt.action.Pwd` と
`xghostty_action_pwd_s` が `host` を持つ)。VT の意味論は変えていない。

### 29.1 判断(RemoteSplit.launch)

```swift
struct PaneLocationReport: Equatable { var host: String?; var path: String? }

enum PaneSplitLaunch: Equatable {
    case local
    case ssh(host: String, path: String)
    var initialInput: String? { ... }
}

enum RemoteSplit {
    static func launch(for report: PaneLocationReport?) -> PaneSplitLaunch
    static func launch(
        for report: PaneLocationReport?,
        foreground: PaneForegroundProcess) -> PaneSplitLaunch
}
```

- `PaneLocationReport` はシェル統合(OSC 7)が報告したペインの居場所。
  `host` はローカルなら空、リモートなら報告されたホスト名。
  `OSSurfaceView.paneLocation`(`PaneLocationTracker`)が保持する(§29.3)。
- `.ssh` になるのは**すべて**満たすときだけ:
  1. レポートが存在し、
  2. `host` が空白除去後に非空で、かつ loopback 集合
     (`localhost` / `localhost.localdomain` / `127.0.0.1` / `::1`、
     大小文字無視)に含まれず、
  3. `path` が**絶対パス**(`/` 始まり)である。
- それ以外はすべて `.local`:レポート無し・ホスト情報無し・loopback・
  パス無し・相対パス。**再接続先を確定できない場合はローカル**という
  必須対応事項 61 の規則をそのまま形にしたもの。
- loopback チェックはコアが既にローカル性を解決した後の**二重の柵**である。

### 29.2 届け方(initialInput)

```text
ssh -t <quoted-host> 'cd <quoted-path> && exec ${SHELL:-/bin/sh} -l'\n
```

- この行は**新ペインのコマンドを置き換えるのではなく、通常どおり起動した
  ローカルシェルへ初期入力として流し込む**(`XGhostty.App.swift` の split 経路が
  `surfaceView.paneSplitLaunch().initialInput` を `config.initialInput` に
  載せる)。
- そうする理由は失敗経路にある:ホストが到達不能でも、ssh が無くても、リモートの
  パスが消えていても、**ペインは継承ディレクトリで動くローカルシェルのまま残る** —
  特別扱いのコードなしに「従来どおりローカルで開く」(必須対応事項 61)が
  構造的に満たされる。
- 引用は二重:ローカルシェルがスクリプトを素通しするため(同時に `${SHELL}` を
  リモートに届くまで展開させないため)と、リモートシェルがパスを 1 語として
  見るため。`-t` は tty を強制し、リモートシェルを対話的にする。
- ユーザー名・鍵・ポートは**意図的に**リモート側の ssh 設定に委ねる
  (前提事項)。使うのは報告されたホスト名だけで、元ペインの ssh コマンドラインは
  再現しない。
- 対象は **split のみ**。新規プロジェクト作成とレイアウト適用で作られる新
  プロジェクトはローカルで開く(必須対応事項 60)。

### 29.3 レポートの鮮度(PaneLocationTracker)

OSC 7 は**変わったときにしか報告されない**。bash 統合は同一 PWD の再報告を
抑止する(`_ghostty_last_reported_cwd`)ため、ssh を抜けて同じディレクトリの
ローカルシェルに戻っても新しい報告は来ない。レポートを最後に受けたまま持ち
続けると、**手元にいるペインの split が誤ってリモートへ ssh してしまう**
(成功条件 19 後半の違反)。zsh 統合は precmd ごとに無条件再報告するため自然
回復するが、bash では回復しない。上流のシェル統合スクリプトは継承資産であり
触らないので、鮮度は macOS アプリ層で担保する。

```swift
enum PaneForegroundProcess { case shell, other, unknown
    static func classify(executablePath: String?) -> PaneForegroundProcess }

struct PaneLocationTracker {
    private(set) var report: PaneLocationReport?
    mutating func record(_ report: PaneLocationReport)
    mutating func reset()
    mutating func commandFinished(foreground: PaneForegroundProcess)
    func splitLaunch(foreground: PaneForegroundProcess) -> PaneSplitLaunch
}
```

- **前景プロセス**が根拠である。ペインが本当にリモートにいる間、pty の前景に
  いるのは(ローカルの)`ssh` 等であり、手元のプロンプトに戻っていれば前景は
  ペイン自身のシェルである。前景 pid は `xghostty_surface_foreground_pid`
  (pty の `tcgetpgrp`)で得て、`proc_pidpath` で実行ファイル名を引き、
  `PaneForegroundProcess.classify` が既知のシェル名集合と照合する
  (`PaneForegroundProbe`)。取得できなければ `.unknown`。
- **split 時の柵**:前景がペイン自身のシェルなら、レポートがどれだけリモートを
  主張していても `.local`。`.unknown` は柵にしない — 前景を読めないことは
  「戻ってきた証拠」ではないので、従来どおりレポートに従う。
- **command finished(OSC 133 D)での破棄**:コマンド終了時に前景がシェルなら、
  いま終わったのは**手元で**走っていたコマンド(= ssh からの復帰)なので
  レポートを捨てる。前景がシェル以外なら、それはリモートシェル自身の
  コマンド終了報告が同じストリームを流れてきただけなので**捨てない**
  (リモート側が bash で再報告を抑止していても、リモート判定が維持される)。
  この処理は通知設定(`notifyOnCommandFinish`)の判定より**前**に行う。
- **child exit での破棄**:報告した当のシェルが消えたのだからレポートも消す。
  終了済みペインを Enter で再開した新しいシェルは手元で始まる(§23.3)。
- 観測性:pwd 報告の受信(host + path)と split の起動判断は debug ログに
  出る。実機で「報告が来ていない」のか「来たうえでローカルと判定した」のかを
  ログだけで切り分けられる。

### 29.4 テスト(ProjectRemoteSplitTests、15 件)

```text
- ローカルの pwd 報告 → .local
- リモートホストの pwd 報告 → そのホスト・パスへの .ssh
- ホスト情報なし / 空白ホスト / loopback ホスト → .local
- リモートホストでも絶対パスが無ければ .local
- ホストとパスは両シェル向けに引用される
- 再接続は新ペインのシェル内で走る(失敗してもローカルシェルが残る)
- 前景プロセスの分類(シェル / それ以外 / 取得不能)
- 前景がシェルなら、リモートのレポートがあっても .local
- 前景がシェル以外 / 取得不能なら、レポートどおり .ssh
- 生きたリモートセッション中のコマンド終了ではレポートを捨てない
- 手元のシェルに戻ってのコマンド終了ではレポートを捨てる
- 破棄後に新しい報告が来ればリモート判定が復活する
- reset(child exit)でレポートを忘れる
- ローカルのレポートは柵の影響を受けない
```

[1]: https://ghostty.org/docs/config/keybind/reference "Action Reference - Keybindings"
[2]: https://rexbrahh.github.io/ghostty-knowledge-base/reference/macos/Sources/Features/Splits/SplitTree.swift/ "macos/Sources/Features/Splits/SplitTree.swift | Ghostty Knowledge Base"
[3]: https://github.com/ghostty-org/ghostty/blob/main/macos/Sources/Features/Splits/TerminalSplitTreeView.swift "ghostty/macos/Sources/Features/Splits/TerminalSplitTreeView.swift at main · ghostty-org/ghostty · GitHub"
