# 知見

<!-- 周回を跨いで役に立つ事実だけを書く: ビルド/テストの実行方法、ツールの制限と回避策、環境の癖。
     「次にやること」は書かない(それは周回記録の「申し送り」)。古くなった行は消す。50 行以内に保つ。
     周回のエージェントは途中で替わりうる。特定のハーネスのツール名ではなく、コマンドと事実で書く。 -->

Atlas Builder の `lessons.jsonl`(2026-08-18〜09-07)から移した事実。

## ビルドと検証

- 検証の 3 ゲートは `zig build` / `just test` / `just swift-test`。いずれもプロジェクトルートで実行する。
- Zig は 0.15.x に固定(`build.zig.zon` の minimum 0.15.2。0.16 では comptime のバージョン検査で失敗する)。Homebrew の素の `zig` は 0.16 へ上がるので、`zig build` を直接叩くときは `PATH=/opt/homebrew/opt/zig@0.15/bin:$PATH` を前置する。`just` のレシピは既定でこの zig を使う。
- exit code はパイプ越しに取らない。`cmd | tail; echo $?` は tail の状態を返す。`cmd > log 2>&1; echo EXIT=$?` の形で取る。
- `just swift-test` の passed 件数の表示は並列出力で揺れる。判定は exit code と、ログ中の failed が 0 件であること。
- `xcodebuild -only-testing:<Target>/<Suite>/<test>` は識別子が何にも一致しなくても exit 0 になる(0 件実行で「成功」)。絞り込み実行は、ログでそのテストが実際に走ったことを確かめてから通過とみなす。
- ビルドとテストは foreground で、明示的な timeout を付けて実行する。headless のセッションは手番の終了とともに background のプロセスを SIGTERM するため、background に回した検証は失われる。
- `just swift-test` のログには失敗したテスト名しか出ず、どの `#expect` が落ちたかは出ない。失敗箇所は式を分けて推測する。
- テストの `ProjectStateOf(... paneTree:)` は `focusedSurface` を nil で作る。閉じる・zoom 解除などで `snapFocusToPrimaryInOverallView` が走って初めてプライマリーが入るので、期待値は操作前の `focusedSurface` ではなくペインの id から作る。
- Swift Testing の `#expect` は、ローカル変数の mutating メソッド呼び出しを包めない(コンパイルエラー)。`let applied = state.mutatingCall(...)` としてから `#expect(applied)` と書く。
- macOS 27 / Xcode 27(27A266a)環境の注意。(1) Metal Toolchain は Xcode 27 では別途ダウンロードする部品で、無いと metallib 生成が失敗する(`xcodebuild -showComponent MetalToolchain` で確認、`xcodebuild -downloadComponent MetalToolchain` で導入。2026-09-30 導入済み)。(2) MacOSX27 SDK の math.h は modules 有効時に `INFINITY` を float.h に委ねるが、zig 0.15/0.16 同梱の float.h は strict モードで定義しないため、zig 同梱 libc++ のビルドが `INFINITY` 未定義で落ちる(zig 0.16 でも再現。zig を上げても直らない)。`pkg/apple-sdk/build.zig` の `libcOverlay` が `math.h` の上書きヘッダを libc の include_dir に挟んで補っている。(3) `macos/build` に古い未署名の `xghostty.debug.dylib` が残ると CodeSign が「code object is not signed at all」で失敗する。`macos/build/Debug/XGhostty.app` を消して再ビルドすれば直る。2026-09-30 時点で 3 ゲートはこの環境で exit 0。
- テストの削除・無効化の検査(C14)の基準は Atlas Builder 移行時点の commit `9cb808d`。当時は `x-ghostty/` 配下にあったため、`git diff -M 9cb808d HEAD` とリネーム検出を付けて比べる。fork 開始時点(`5307c05`)からは、`f93d9b1`(タブ・複数ウィンドウ・非 macOS の撤去)でタブ・ウィンドウ・quick terminal・update 系のテストが消えており、Zig の `test "ghostty.h ..."` は `xghostty.h` へ改名されている。
- `.idd/` の台帳・記録はシェルコマンド(grep 等)からは読めない(hook が拒否する)。ファイルとして直接読む。
- 実機観測(サンドボックス off の周回で使える): `zig build` 後、`(nohup zig-out/XGhostty.app/Contents/MacOS/xghostty > /tmp/app.log 2>&1 &)` で別プロセスとして起動できる(`open -n` は -54 で失敗した)。保存状態を復元して起動する。打鍵は Swift の小さなツールで `NSRunningApplication(processIdentifier:).activate` の後 `CGEvent(keyboardEventSource:virtualKey:keyDown:)` を `.cghidEventTap` へ post、窓 ID は `CGWindowListCopyWindowInfo` で pid から引き、`screencapture -x -l <窓ID> out.png` で撮る(swiftc のコンパイルは数分かかる)。終わったら自分の pid だけ kill する。
- `zig-out/XGhostty.app` の bundle id は `com.mitchellh.xghostty`、Xcode の `macos/build/Debug/XGhostty.app` は `com.mitchellh.xghostty.debug`。保存状態が別なので、人間が残した Debug アプリを起動したまま zig-out 版を並行して起動・kill できる。
- 解放の確認は `heap <pid> -addresses 'XGhostty.SurfaceView' | grep -c '^0x'` で生存 `SurfaceView` を数えるのが最も直接的(スレッド・IOSurface より揺れない)。`leaks <pid> --traceTree=<addr>` は保守的走査で弱参照やスタック上の古いポインタまで並べるので、所有者の特定にはほぼ使えない。仮説は挙動の差(どの操作で解放されるか)で切り分ける。`lldb -p <pid> --batch -s cmds.txt` で自分の起動したプロセスに ObjC の式を打てる(合成イベントの送信など)。
- 合成のマウス操作: `CGEvent(mouseEventSource:mouseType:mouseCursorPosition:mouseButton:)` を `.cghidEventTap` へ post(座標はグローバルの左上原点ポイント、ダブルクリックは `.mouseEventClickState` を 1→2)。この環境では window のスクショ 1px = 1pt で、左右 56px・上 37px が影。合成ダブルクリックでラベルの名前編集に入ると、入力欄が first responder にならないことがある(もう一度クリックすると入る)。
- C ABI: `include/xghostty.h` の action enum は後続のタグ値を保つ(in-place 置換か末尾追加)。

## 実装の現状

- 描画停止は既存の C API `xghostty_surface_set_occlusion` で行っている。コア側がディスプレイリンク停止・drawFrame のスキップ・可視復帰時の即時再描画を実装済みで、`src/**` の改変は要らなかった。同期の発火点は `BaseTerminalController.syncRenderTargetOcclusion`(windowDidLoad / occlusion 変化 / surfaceTreeDidChange / workspace.$state)。コントローラは最後に適用したスナップショット `appliedRenderTarget`(初期値は空)だけを状態として持ち、`RenderTargetTransition` の stop/resume を送る。コア surface が nil で送れなかった id は `RenderTargetSnapshot.applied(except:)` で両集合から外し、次回に「誕生」として再導出させる。`surfaceTreeDidChange` は `replaceFocusedPaneTree` で workspace へ写してから同期するので、走査は workspace の全プロジェクトで足りる。
- コアの renderer thread は起動直後に自分へ wakeup を送り、最初の 1 フレームをすぐ描く(`src/renderer/Thread.zig` の `threadMain_`)。その描画で swap chain が実サイズに広がるため、誕生時の停止は「スレッドが mailbox を最初に drain する前」に積まれていないと効かない。状態復元では全 surface が `TerminalRestorableState(coder:)` のデコード(`SurfaceView.init(from:)` → `xghostty_surface_new`)で生まれ、コントローラと最初の `syncRenderTargetOcclusion` はその後になる。`xghostty_surface_config_s` に初期 occlusion の欄は無いので、`SurfaceView_AppKit.swift` の init が `xghostty_surface_new` の直後に判断なしで `set_occlusion(false)` を送り、全 surface を停止状態で生ませている(IDEAL C122 の唯一の例外)。`SurfaceView_UIKit.swift`(iOS)には入れていない。
- 停止・再開・解放の集合は `macos/Sources/Features/Projects/ProjectRenderTarget.swift` の `RenderTargetTransition(from:to:)` が 2 つのスナップショットから導く。停止集合は「誕生」(after.retained − before.retained)も含む。テストは `macos/Tests/Projects/ProjectRenderTargetTests.swift`。
- エディタの SourceKit 診断(`Cannot find type 'SurfaceID'`、`No such module 'Testing'`)はプロジェクト文脈なしの索引によるもので、ビルドとは無関係。判定は `just swift-test` で行う。
- 閉じたプロジェクトの surface は、上流由来の close undo(`ExpiringUndoManager`、undo-timeout)の間だけ生き残る。スレッド数・IOSurface 数の実測(C117)は undo 期限が切れてから行う。この扱いは周回の判断であり、人間の承認はまだ無い。
- ソース内コメントの `SPEC.md §N.M` 参照は、SPEC の節番号の付け替えに追従していないことがある(§24.5 → §24.4 の例)。読み合わせでは `grep -rn "§N\.M" macos/Sources` で参照先の節見出しと突き合わせる。
- SPEC の読み合わせでは、節内の backtick 識別子を抜き出して `grep -rlw` で `macos/Sources macos/Tests src include` に在るかを一括で調べると、廃止済みの識別子(例: `isDrawing`)が機械的に見つかる。テスト件数は `grep -c '@Test'` で節見出しと突き合わせる(1 ファイルに複数 struct があるスイートは struct 単位で数える)。
- `ProjectListRow` は memberwise init をテストが 30 箇所以上で使う。列を足すときは `var <field>: T? = nil` で宣言すると既存の呼び出しを変えずに済む。端末の登録は `WorkspaceModel.terminalRegistry` が持ち(永続化しない)、一覧の候補・表示・コピー・貼り付けは `terminals:` 引数でこれを受け取る。プロジェクトが保存するのは表示名だけ(手元は `nil`)。
- ペインの tmux セッションは `ProjectState.paneBindings`(pane ID → 端末の保存名と連番)と `lastPaneIndex`(永続化する最大連番)が持つ。`bindPane` は初回だけプロジェクトの現在の端末で割り当てる。木から外れたペインの割り当てはメモリ上に残し(undo と kill のため)、保存は木にあるペインだけ。終了済みからの再開は割り当てを新しいペインへ移す。kill 対象は `TmuxSession.killTargets(closed:open:registry:)`。
- ペインの surface は生成時の `SurfaceConfiguration.command` で tmux の attach コマンドを走らせる。surface の id(`SurfaceView(app, baseConfig:, uuid:)`)を先に決めて割り当ててから surface を作る(`BaseTerminalController.makePane`、`ProjectState.new` / `splitLaunchCommand` / `restartLaunchCommand`)。復元では `ProjectState` の decode が保存済みセッションを先に読み、木の decode を `TmuxPaneRestore.decoding` の中で行い、`SurfaceView.init(from:)` が `TmuxPaneRestore.command(for:)` を引く。この文脈は `@TaskLocal`(Swift Testing は並列に走るので、static 変数だとテスト間で漏れて落ちた)。登録の参照先は `ProjectTerminalRegistry.shared`(workspace が無い復元中にも引ける)。
- 閉じたペインのセッションの kill は、`BaseTerminalController` の `workspace.$state` の sink が `TmuxOpenPanes.advance` で「前の状態にあって今は無い」割り当て済みペインを集め、`undoExpiration` + 1 秒後に `TmuxOpenPanes.killTargets`(その時点で開いているペインの id とセッションを除く)を走らせる。閉じる経路ごとのフックではないので、子プロセス終了で複数ペインの 1 つが閉じた場合も対象になる。`removeAllSurfaces`(窓を閉じる・終了)の後は kill しない。
- リネーム時の `status-left` 更新も同じ sink で、`TmuxOpenPanes.retitles(to:)`(前後とも開いているペインのうちタイトルが変わったプロジェクトのもの)に `TmuxSession.retitleArguments` を走らせる。実機では一覧(`Cmd+L`、keycode 37)の初期カーソルが 1 行目の表示列なので、`→`(124)・Return(36)・文字・Return でタイトルを変え、`tmux show-options -t "=<session>:" status-left` で確かめられる。
- 実機の打鍵: zoom は `Cmd+Opt+Enter`(keycode 36)、split は zoom 中の `Cmd+D`(2)、close は `Cmd+W`(13)の後に確認ダイアログへ Return、undo は `Cmd+Z`(6)。
- zig-out 版を起動すると、復元された全ペインが既定ソケットの tmux に `<uuid>-<n>` のセッションを作る。起動前の `tmux ls -F '#{session_name}'` を控え、終了後にそれ以外の `^[0-9a-f-]{36}-[0-9]+$` だけを kill すれば人間のセッションに触れない。
- 保存済みの列順に無い列は `ProjectListColumn.normalizedOrder` が既定順の直前の列の後ろへ挿入する(6 列の保存は端末列がタイトルの後に入る)。
- fork の機能を作る前に、上流が同等の機構を既に持っていないかを確かめる。欠けているのは API ではなく呼び出し側の走査範囲、ということがあった。

## tmux

- Mac mini の tmux は `/opt/homebrew/bin/tmux`(3.8)。hostname は `Mac-mini-M6.local`。人間の常用セッション(`main` など)が既定ソケットに居るので、実験は名前で絞ったセッションだけを作り・kill する。
- `set-option -t` は pane target を取るので、セッションの完全一致は `=<name>:`(末尾の `:` が要る)。`=<name>` だけだと「no such session」。`kill-session -t` / `has-session -t` は `=<name>` で効く。
- zsh では行頭の `=word` が equals 展開(コマンドのパスへの置換)になる。zsh から tmux を叩くときは `-t "=name:"` と引用する。生成するスクリプトは `/bin/sh -c` で走らせているので影響しない。
- attach コマンドを tty 無しで試すには、`(perl -e 'sleep 15' \| script -q /dev/null /bin/zsh -c "<cmd>" > out.txt 2>&1 &)` で擬似端末を与える(stdin を開いておかないと client が即 detach する)。`tmux new-session -A ... ';' set-option ...` の連鎖は、新規作成と再 attach のどちらでも後続の set-option が走る。
- Mac mini の ssh ループバックは未設定(`ssh 127.0.0.1` は Host key verification failed)。

## SwiftUI / AppKit の癖

- SwiftUI(macOS)の hover / pointer-style の追跡は、最後のマウスイベントの時点でポインタの下にあった responder 連鎖を次のマウスイベントまで保持する。キーボードだけで view を消すと、その view(とそれが持つ `SurfaceView`)がマウスを動かすまで解放されない。ポインタ位置への合成 mouse-moved を window に `sendEvent` すれば取り直される(`BaseTerminalController.refreshPointerTracking`)。この保持は「マウスの位置」に依存するので、解放の実機再現ではポインタの置き場所を固定しないと結果が揺れる。

- `NSEvent.addLocalMonitorForEvents` を SwiftUI の `onAppear` で 1 度だけ入れると、その時点の View の値を掴んだまま古い closure を呼び続ける(1 回目だけ動き、2 回目から狂う)。参照型の handler box を経由させ、body の評価ごとに現在の closure へ差し替える。
- ローカル keyDown モニタは responder より先に走り、登録順に呼ばれ、nil を返すと連鎖が止まる。オーバーレイを重ねるときは、下の層のハンドラの先頭で「上の層が active なら event をそのまま返す」。
- モニタが `Cmd` 系の打鍵を素通しすると、端末 surface の `performKeyEquivalent` が先に食う(`Cmd+V` が背後の端末へ貼り付く)。編集ショートカットはモニタで捕まえて field editor に対して実行し、nil を返す。
- ローカル keyDown モニタは、ウィンドウに付いたシート(`beginSheetModal` の確認)宛ての打鍵も見る。オーバーレイのモニタはシート・モーダル宛て(`event.window` が sheet / `sheetParent` あり / `NSApp.modalWindow`)を素通しする(`OverlayKeyDownMonitor`)。
- 一覧などのオーバーレイが開いている間は不可視の catcher が first responder なので、surface の keybind(`Cmd+L` 等)は働かない。閉じる chord はオーバーレイのハンドラで自前に照合する。
- IME: 編集開始の打鍵はモニタが消費するので、新しいエディタが first responder になってから `interpretKeyEvents([event])` で再生する。Enter / Esc / Tab / Space の終端処理は `hasMarkedText()` が false のときだけ行う。未確定状態を読むには AppKit のエディタが要る(`NSTextField` を `NSViewRepresentable` で包む)。
- SwiftUI の `.cornerRadius` は clipShape であり、その内側に付けた overlay は zIndex では逃げられない。ポップアップは、セルが `anchorPreference` で矩形だけを公開し、コンテナの最上位が `.overlayPreferenceValue` で clip の後に描く。
