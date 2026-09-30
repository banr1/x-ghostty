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
- Swift Testing の `#expect` は、ローカル変数の mutating メソッド呼び出しを包めない(コンパイルエラー)。`let applied = state.mutatingCall(...)` としてから `#expect(applied)` と書く。
- macOS 27 / Xcode 27(27A266a)環境の注意。(1) Metal Toolchain は Xcode 27 では別途ダウンロードする部品で、無いと metallib 生成が失敗する(`xcodebuild -showComponent MetalToolchain` で確認、`xcodebuild -downloadComponent MetalToolchain` で導入。2026-09-30 導入済み)。(2) MacOSX27 SDK の math.h は modules 有効時に `INFINITY` を float.h に委ねるが、zig 0.15/0.16 同梱の float.h は strict モードで定義しないため、zig 同梱 libc++ のビルドが `INFINITY` 未定義で落ちる(zig 0.16 でも再現。zig を上げても直らない)。`pkg/apple-sdk/build.zig` の `libcOverlay` が `math.h` の上書きヘッダを libc の include_dir に挟んで補っている。(3) `macos/build` に古い未署名の `xghostty.debug.dylib` が残ると CodeSign が「code object is not signed at all」で失敗する。`macos/build/Debug/XGhostty.app` を消して再ビルドすれば直る。2026-09-30 時点で 3 ゲートはこの環境で exit 0。
- テストの削除・無効化の検査(C14)の基準は Atlas Builder 移行時点の commit `9cb808d`。当時は `x-ghostty/` 配下にあったため、`git diff -M 9cb808d HEAD` とリネーム検出を付けて比べる。fork 開始時点(`5307c05`)からは、`f93d9b1`(タブ・複数ウィンドウ・非 macOS の撤去)でタブ・ウィンドウ・quick terminal・update 系のテストが消えており、Zig の `test "ghostty.h ..."` は `xghostty.h` へ改名されている。
- C ABI: `include/xghostty.h` の action enum は後続のタグ値を保つ(in-place 置換か末尾追加)。

## 実装の現状

- 描画停止は既存の C API `xghostty_surface_set_occlusion` で行っている。コア側がディスプレイリンク停止・drawFrame のスキップ・可視復帰時の即時再描画を実装済みで、`src/**` の改変は要らなかった。同期の発火点は `BaseTerminalController.syncRenderTargetOcclusion`(windowDidLoad / occlusion 変化 / surfaceTreeDidChange / workspace.$state)。コントローラは最後に適用したスナップショット `appliedRenderTarget`(初期値は空)だけを状態として持ち、`RenderTargetTransition` の stop/resume を送る。コア surface が nil で送れなかった id は `RenderTargetSnapshot.applied(except:)` で両集合から外し、次回に「誕生」として再導出させる。`surfaceTreeDidChange` は `replaceFocusedPaneTree` で workspace へ写してから同期するので、走査は workspace の全プロジェクトで足りる。
- 停止・再開・解放の集合は `macos/Sources/Features/Projects/ProjectRenderTarget.swift` の `RenderTargetTransition(from:to:)` が 2 つのスナップショットから導く。停止集合は「誕生」(after.retained − before.retained)も含む。テストは `macos/Tests/Projects/ProjectRenderTargetTests.swift`。
- エディタの SourceKit 診断(`Cannot find type 'SurfaceID'`、`No such module 'Testing'`)はプロジェクト文脈なしの索引によるもので、ビルドとは無関係。判定は `just swift-test` で行う。
- 閉じたプロジェクトの surface は、上流由来の close undo(`ExpiringUndoManager`、undo-timeout)の間だけ生き残る。スレッド数・IOSurface 数の実測(C117)は undo 期限が切れてから行う。この扱いは周回の判断であり、人間の承認はまだ無い。
- ソース内コメントの `SPEC.md §N.M` 参照は、SPEC の節番号の付け替えに追従していないことがある(§24.5 → §24.4 の例)。読み合わせでは `grep -rn "§N\.M" macos/Sources` で参照先の節見出しと突き合わせる。
- SPEC の読み合わせでは、節内の backtick 識別子を抜き出して `grep -rlw` で `macos/Sources macos/Tests src include` に在るかを一括で調べると、廃止済みの識別子(例: `isDrawing`)が機械的に見つかる。テスト件数は `grep -c '@Test'` で節見出しと突き合わせる(1 ファイルに複数 struct があるスイートは struct 単位で数える)。
- fork の機能を作る前に、上流が同等の機構を既に持っていないかを確かめる。欠けているのは API ではなく呼び出し側の走査範囲、ということがあった。

## SwiftUI / AppKit の癖

- `NSEvent.addLocalMonitorForEvents` を SwiftUI の `onAppear` で 1 度だけ入れると、その時点の View の値を掴んだまま古い closure を呼び続ける(1 回目だけ動き、2 回目から狂う)。参照型の handler box を経由させ、body の評価ごとに現在の closure へ差し替える。
- ローカル keyDown モニタは responder より先に走り、登録順に呼ばれ、nil を返すと連鎖が止まる。オーバーレイを重ねるときは、下の層のハンドラの先頭で「上の層が active なら event をそのまま返す」。
- モニタが `Cmd` 系の打鍵を素通しすると、端末 surface の `performKeyEquivalent` が先に食う(`Cmd+V` が背後の端末へ貼り付く)。編集ショートカットはモニタで捕まえて field editor に対して実行し、nil を返す。
- IME: 編集開始の打鍵はモニタが消費するので、新しいエディタが first responder になってから `interpretKeyEvents([event])` で再生する。Enter / Esc / Tab / Space の終端処理は `hasMarkedText()` が false のときだけ行う。未確定状態を読むには AppKit のエディタが要る(`NSTextField` を `NSViewRepresentable` で包む)。
- SwiftUI の `.cornerRadius` は clipShape であり、その内側に付けた overlay は zIndex では逃げられない。ポップアップは、セルが `anchorPreference` で矩形だけを公開し、コンテナの最上位が `.overlayPreferenceValue` で clip の後に描く。
