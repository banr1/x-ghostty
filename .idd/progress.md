# 進捗台帳

<!-- 周回エージェントが保守する。IDEAL.md「実現する状態」の各条件を 1 行ずつ。
     状態は unmet / met / blocked の 3 値。met にできるのは証拠を記録した周回だけ。
     証拠列は、最初に現れる出典を idd が読む:
       cycle N: <コマンド> exit 0   周回 N(1 以上、現在の周回以下)で検証が通った
       human <at>: <要点>           台帳(journal.jsonl)の human resume 行 <at> を出典とする人間の確認
       observed N: <要点>           周回 N のエージェントが実画面の観測(Computer Use 等)で検証した。IDEAL.md が
                                    その条件で観測を認めている場合だけ。記録 NNNN.md の「## 検証」表に observed 行が要る
     IDEAL.md が変わったら(sha が下と違う)条件を投影し直し、消えた条件は行ごと消す。
     階層は 必須 / 望ましい。ID 列は IDEAL.md の番号を装飾なしで書く(`C1`。`**C1**` にしない)。
     列は 5 つ固定: | ID | 階層 | 条件 | 状態 | 証拠 |。idd はこの形で met / unmet を数え、完了を検算する。 -->

ideal_sha: e792278f1d0827210c7f2e87954bdbdcc14d0095824a3065f1d060be2e1cadc8

| ID | 階層 | 条件 | 状態 | 証拠 |
|----|------|------|------|------|
| C1 | 必須 | プロジェクトごとに手書きの短いノートを保持できる(検証: C91) | met | cycle 25: just swift-test exit 0 (検証は C91 のテスト成功のみ。C91 は met、failed 0 件) |
| C2 | 必須 | ノート最大 100 行、保存時超過は確認し OK で先頭 100 行へ切詰め・Cancel で編集へ戻る(検証: C91 + C97) | unmet | - |
| C3 | 必須 | ノートは永続化され再起動後に同じプロジェクトへ復元(検証: C91) | met | cycle 25: just swift-test exit 0 (検証は C91 のテスト成功のみ。C91 は met、failed 0 件) |
| C4 | 必須 | ノートはプロジェクトに属しペインに属さない(検証: C91) | met | cycle 25: just swift-test exit 0 (検証は C91 のテスト成功のみ。C91 は met、failed 0 件) |
| C5 | 必須 | `Cmd+E` でノート編集オーバーレイ、`Cmd+Enter` で保存して閉じる(検証: C91 + C92) | unmet | - |
| C6 | 必須 | オーバーレイで Esc は確認なしに破棄して閉じる(検証: C91 + C92) | unmet | - |
| C7 | 必須 | `Cmd+Enter` の fullscreen 既定割り当てを解除(検証: C92) | unmet | - |
| C8 | 必須 | `Cmd+Opt+E` で一望モードをトグル、Esc でも抜ける(検証: C92) | unmet | - |
| C9 | 必須 | 一望モードは visible なプロジェクトのみ表示(検証: C91) | met | cycle 25: just swift-test exit 0 (検証は C91 のテスト成功のみ。C91 は met、failed 0 件) |
| C10 | 必須 | zoom 中に一望モードへ入ると zoom 解除(検証: C91) | met | cycle 25: just swift-test exit 0 (検証は C91 のテスト成功のみ。C91 は met、failed 0 件) |
| C11 | 必須 | 一望モードは閲覧専用で編集・focus 移動しない(検証: C91) | met | cycle 25: just swift-test exit 0 (検証は C91 のテスト成功のみ。C91 は met、failed 0 件) |
| C12 | 必須 | 一望モードで収まらないノートは切詰め、編集オーバーレイはスクロールで全文(検証: C92) | unmet | - |
| C13 | 必須 | ノート UI は端末領域を恒久占有しない(検証: C92) | unmet | - |
| C14 | 必須 | 既存機能と上流動作を退行させない(列挙した意図的変更を除く。C123〜C125 を例外に追加)(検証: C88〜C90 exit 0 かつ既存テストが削除・無効化されず成功) | met | cycle 25: just swift-test exit 0 (zig build・just test も exit 0。git diff -M 9cb808d HEAD --diff-filter=D で削除された .swift/.zig は 0 件、作業木の削除も 0 件。この周回の変更は BaseTerminalController.swift の refreshPointerTracking、TerminalWorkspaceView.swift の rename 終了時のフォーカス返却、SPEC/README だけでテストに触れていない。failed 0 件・passed 701 行) |
| C15 | 必須 | ノートの判断ロジックはモデル層で XGhosttyTests から検証可能(検証: C91) | met | cycle 25: just swift-test exit 0 (検証は C91 のテスト成功のみ。C91 は met、failed 0 件) |
| C16 | 必須 | SPEC.md / README.md をノート層仕様に合わせ、README の Building 節に 3 検証コマンド(検証: 周回の読み合わせ) | met | cycle 25: grep -n "Building" -A12 README.md exit 0 (zig build / just test / just swift-test の 3 行を確認。SPEC §21 と README の Notes 項は cycle 12 の読み合わせ以降、ノート層の実装変更が無い) |
| C17 | 必須 | 各ペインはプライマリーフラグを持ち最初のペインがプライマリー(検証: C93) | met | cycle 25: just swift-test exit 0 (検証は C93 のテスト成功のみ。C93 は met、failed 0 件) |
| C18 | 必須 | プライマリーはプロジェクト内で常に 1 つ(検証: C93) | met | cycle 25: just swift-test exit 0 (検証は C93 のテスト成功のみ。C93 は met、failed 0 件) |
| C19 | 必須 | 全体ビューはプライマリーのみ描画、zoom 中は全ペイン(検証: C93 + C94) | unmet | - |
| C20 | 必須 | 全体ビューの入力・focus はプライマリーへ、zoom 解除時に寄せる(検証: C93) | met | cycle 25: just swift-test exit 0 (検証は C93 のテスト成功のみ。C93 は met、failed 0 件) |
| C21 | 必須 | 全体ビューでペイン系操作は no-op(検証: C93) | met | cycle 25: just swift-test exit 0 (検証は C93 のテスト成功のみ。C93 は met、failed 0 件) |
| C22 | 必須 | zoom 中 `Cmd+P` で focused ペインをプライマリーへ(検証: C93 + C94) | unmet | - |
| C23 | 必須 | プライマリーが閉じたら最近傍 leaf を昇格(検証: C93 + C94) | unmet | - |
| C24 | 必須 | プライマリーフラグの永続化と復元時正規化(検証: C93) | met | cycle 25: just swift-test exit 0 (検証は C93 のテスト成功のみ。C93 は met、failed 0 件) |
| C25 | 必須 | プライマリー印は zoom 中かつ複数ペイン時のみ右上に表示(検証: C94) | unmet | - |
| C26 | 必須 | プライマリーの判断ロジックはモデル層(検証: C93) | met | cycle 25: just swift-test exit 0 (検証は C93 のテスト成功のみ。C93 は met、failed 0 件) |
| C27 | 必須 | SPEC.md / README.md をプライマリーペイン層仕様に合わせる(検証: 周回の読み合わせ) | met | cycle 25: grep -c "@Test" macos/Tests/Projects/ProjectPrimaryPaneTests.swift exit 0 (35 件で SPEC §22.8 と一致。§22 の読み合わせは cycle 13、以降プライマリー層の実装変更は無い) |
| C28 | 必須 | プロジェクトを閉じる操作は常に確認ダイアログ(検証: C95 + C96) | unmet | - |
| C29 | 必須 | 最後のペインのシェル exit でプロジェクトを閉じず終了済みで残す(検証: C95 + C96) | unmet | - |
| C30 | 必須 | 終了済みペインで Enter により新シェルで再開(検証: C96) | unmet | - |
| C31 | 必須 | プロジェクト喪失経路は確認を経た明示的 close のみ(検証: C95 + C96) | unmet | - |
| C32 | 必須 | ノート編集オーバーレイで標準編集ショートカットと Undo/Redo が効く(検証: C97) | unmet | - |
| C33 | 必須 | 貼り付けで 100 行超過も C2 の確認を経る(検証: C91 + C97) | unmet | - |
| C34 | 必須 | 優先度 high/medium/low/未設定(検証: C98 + C99) | unmet | - |
| C35 | 必須 | 締切(日付のみ)、不正入力は未設定(検証: C98 + C99) | unmet | - |
| C36 | 必須 | 優先度・締切は一覧セルで設定し永続化(検証: C98 + C99) | unmet | - |
| C37 | 必須 | ラベル帯に優先度の印と締切を表示(検証: C99) | unmet | - |
| C38 | 必須 | 一望モードでノートと優先度・締切・次トリガーを表示(検証: C111 + C99・C112) | unmet | - |
| C39 | 必須 | 締切超過を控えめに強調(1 段階のみ)(検証: C98 + C99) | unmet | - |
| C40 | 必須 | ソートは 5 値の永続化される状態、既定は手動(検証: C107 + C108) | unmet | - |
| C41 | 必須 | 各ソートキーの固定の向き・安定ソート・序数は visible 行の表示順(検証: C98・C107) | met | cycle 25: just swift-test exit 0 (検証は C98・C107 のテスト成功のみ。C98・C107 は met、failed 0 件) |
| C42 | 必須 | 一覧最上部のソートバーをキーボード・マウスで操作(検証: C107 + C108) | unmet | - |
| C43 | 必須 | ソート有効中の即時再ソートと Opt+↑↓ の確認、ソートアクション廃止(検証: C107 + C108) | unmet | - |
| C44 | 必須 | 優先度・締切・次トリガー・終了済みの判断ロジックはモデル層(検証: C95・C98・C111) | met | cycle 25: just swift-test exit 0 (検証は C95・C98・C111 のテスト成功のみ。C95・C98・C111 は met、failed 0 件) |
| C45 | 必須 | SPEC.md / README.md を削除保護・ショートカット・優先度・締切層に合わせる(検証: 周回の読み合わせ) | met | cycle 25: grep -c "@Test" (ProjectTerminatedTests / ProjectPriorityDeadlineTests / ProjectSortStateTests / ProjectNextTriggerTests) exit 0 (16 / 18 / 13 / 7 件で SPEC §23.5・§24.5・§24.6 と一致。§23.1 の行選択 Delete の記述に cycle 19 で新しい focus 先へのフォーカス移動を足し、performCloseProjectListRow の実装と一致することを読み合わせた) |
| C46 | 必須 | `Cmd+Opt+H` で focused プロジェクトを即時 hidden(検証: C100 + C101) | unmet | - |
| C47 | 必須 | visible は最低 1 つ残る(検証: C100) | met | cycle 25: just swift-test exit 0 (検証は C100 のテスト成功のみ。C100 は met、failed 0 件) |
| C48 | 必須 | hidden の復帰導線は一覧のみ、hidden シェルフ廃止(検証: C107 + C108) | unmet | - |
| C49 | 必須 | レイアウト型 = 形 3 種 × 向き 2 種、余りは後半行へ(検証: C102 + C103) | unmet | - |
| C50 | 必須 | 完全一致する型を畳み、選択肢 1 つなら選ぶものが無い旨(検証: C102 + C103) | unmet | - |
| C51 | 必須 | `Cmd+Opt+L` でレイアウト型の選択オーバーレイ(検証: C103) | unmet | - |
| C52 | 必須 | レイアウト型は永続化、既定は横長型・行送り(検証: C102 + C103) | unmet | - |
| C53 | 必須 | 表示順のまま向きに従いスロットへ割当、序数が追従(検証: C102) | met | cycle 25: just swift-test exit 0 (検証は C102 のテスト成功のみ。C102 は met、failed 0 件) |
| C54 | 必須 | visible 数変化時に記憶の型で自動適用(検証: C102 + C101・C103) | unmet | - |
| C55 | 必須 | プロジェクト単位のレイアウト resize/equalize 廃止、zoom 中ペインは存続(検証: C103) | unmet | - |
| C56 | 必須 | レイアウト型の判断ロジックはモデル層(検証: C102) | met | cycle 25: just swift-test exit 0 (検証は C102 のテスト成功のみ。C102 は met、failed 0 件) |
| C57 | 必須 | 「グループ」→「プロジェクト」全面改名(検証: C104) | unmet | - |
| C58 | 必須 | 改名は純粋なリネームで退行なし(検証: C104 + C88〜C90) | unmet | - |
| C59 | 必須 | SPEC.md / README.md をレイアウト型・自動適用・hide・改名語彙に合わせる(検証: 周回の読み合わせ) | met | cycle 25: grep -c "@Test" macos/Tests/Projects/ProjectLayoutTypeTests.swift macos/Tests/Projects/ProjectLayoutSelectionTests.swift exit 0 (14 / 10 件で SPEC §26.5 と一致。test -d Projects exit 0・test -e Groups exit 1。§25・§26・§12 の読み合わせは cycle 15、以降当該層の実装変更は無い) |
| C60 | 必須 | リモートペインの split は同ホスト・同パスへ ssh(検証: C105 + C106) | unmet | - |
| C61 | 必須 | リモート判定不能・接続失敗はローカルで開く(検証: C105 + C106) | unmet | - |
| C62 | 必須 | リモート判定はモデル層(検証: C105) | met | cycle 25: just swift-test exit 0 (検証は C105 のテスト成功のみ。C105 は met、failed 0 件) |
| C63 | 必須 | `Cmd+L` で一覧をトグル(Esc で閉じない・zoom を解除しない・6 列・8 割)(検証: C107 + C108) | unmet | - |
| C64 | 必須 | 一覧は単一の並び、手動順・列順・ソート状態を永続化、hidden も同色(検証: C107 + C108) | unmet | - |
| C65 | 必須 | Notion 流儀のセルカーソル・Enter 編集・候補列挙(検証: C107 + C108) | unmet | - |
| C66 | 必須 | ノート列編集は全行対象、Shift+Enter で改行、一覧内 `Cmd+Opt+E` は全行表示トグル(検証: C107 + C108) | unmet | - |
| C67 | 必須 | `Cmd+矢印` は端移動、`Opt+矢印` で行・列並べ替え(検証: C107 + C108) | unmet | - |
| C68 | 必須 | `Cmd+N` は一覧での新規プロジェクト作成(検証: C107 + C108) | unmet | - |
| C69 | 必須 | 一覧の `Cmd+Enter` で focus(hidden 行は近傍 visible へ)(検証: C107 + C108) | unmet | - |
| C70 | 必須 | 一覧の判断ロジックはモデル層(検証: C107) | met | cycle 25: just swift-test exit 0 (検証は C107 のテスト成功のみ。C107 は met、failed 0 件) |
| C71 | 必須 | 次トリガー 4 値(チームメンバーは外部へ移行)(検証: C107・C111 + C112) | unmet | - |
| C72 | 必須 | 毎日 6:00 境界で全プロジェクトの優先度を未設定へ(検証: C109 + C110) | unmet | - |
| C73 | 必須 | 最終リセット日付を永続化し作業日ごとに 1 回(検証: C109 + C110) | unmet | - |
| C74 | 必須 | 自動リセットの並びはソート状態に従う(検証: C109) | met | cycle 25: just swift-test exit 0 (検証は C109 のテスト成功のみ。C109 は met、failed 0 件) |
| C75 | 必須 | リセット判定はモデル層(検証: C109) | met | cycle 25: just swift-test exit 0 (検証は C109 のテスト成功のみ。C109 は met、failed 0 件) |
| C76 | 必須 | SPEC.md / README.md をリモート split〜描画停止・閉じた surface の解放(循環参照・同期解放・undo 期限後の解放・行 Delete のフォーカス移動)までの仕様に合わせる(検証: 周回の読み合わせ) | met | cycle 25: grep -c "@Test" macos/Tests/Projects/ProjectListRowSelectionTests.swift exit 0 (11 件で SPEC §27.6 と一致、ProjectRenderTargetTests 21 件で §31.5 と一致。周回 25 で SPEC §31.4 に「ポインタ追跡を閉じた後に取り直す」(released が空でないとき refreshPointerTracking が合成 mouse-moved を送る)、§7.1 に inline rename 終了時のフォーカス返却を、README の描画停止の項に pointer tracking の取り直しを書き、BaseTerminalController.swift と TerminalWorkspaceView.swift の実装と一致することを読み合わせた。周回 24 で C122 の生成直後の一律停止を実装し、SPEC §31.2 の誕生の説明・§31.3 に「唯一の例外は生成直後の一律の停止」の項と「コアの状態は生成直後の一律の停止とその後送った値だけを既知とする」を、README の描画停止の項に「すべての surface は停止して生まれ resume でだけ描き始める」を書き、SurfaceView_AppKit.swift の xghostty_surface_new 直後の set_occlusion(false) と一致することを読み合わせた。cycle 21 で §27.2 に行 Delete 後の catcher の first responder 奪還・シート中のキー監視の素通し、§27.3 に一覧内での Cmd+L の自前照合と list_projects の実行可否を書き足し、実装と一致することを読み合わせた。cycle 19 で SPEC §31.4 に循環参照の解消(C123)・同期解放(C124)・行 Delete のフォーカス移動(C125)・経路によらない undo 期限後の解放(C86)を、§23.1・§27.2・§27.6 と README の一覧・描画停止の項にフォーカス移動と解放を書き足し、旧「focus を動かさない経路」の記述を消した。識別子は grep で実装に在ることを確認。§27〜§31 の他の記述は cycle 16 の読み合わせ以降変わっていない) |
| C77 | 必須 | 締切セルの Enter で 10 択の日付候補(検証: C107 + C108) | unmet | - |
| C78 | 必須 | 一覧テキスト列のセル編集が日本語 IME を受け付ける(検証: C114) | unmet | - |
| C79 | 必須 | セルカーソルの Delete で列ごとの値削除(検証: C107 + C108) | unmet | - |
| C80 | 必須 | Esc で行選択、行選択の Delete で確認付き削除(検証: C107 + C108) | unmet | - |
| C81 | 必須 | `Cmd+/` でショートカット一覧をトグル(検証: C115) | unmet | - |
| C82 | 必須 | `Cmd+K` の clear_screen 既定割り当て解除(検証: C113) | unmet | - |
| C83 | 必須 | 一覧セルのクリップボード操作と候補列挙中の Tab 横移動(検証: C107 + C108) | unmet | - |
| C84 | 必須 | 描画対象の定義(全体ビュー: visible のプライマリー / zoom: 対象の全ペイン)(検証: C116) | met | cycle 25: just swift-test exit 0 (ProjectRenderTargetTests 21 件 passed) |
| C85 | 必須 | 描画対象外は生成時を含めレンダラとディスプレイリンクを停止し復帰時に再開(検証: C116 + C117) | unmet | - (C116 は met。2026-10-28 の実機確認で C117(6) が NG: 復元経路では surface がコントローラより先にデコードで生まれ、最初の同期より前に 1 フレーム描く。周回 22 で ask、人間が案 A を採り、周回 24 で生成直後の一律停止を実装。2026-10-28 第 2 回の人間確認で C117 (1)(6) は OK だったが、周回 25 のコード変更で失効したため C117 の再確認待ち) |
| C86 | 必須 | 閉じた surface を経路によらず undo 期限後に SurfaceView〜IOSurface まで解放(検証: C116・C126 + C123〜C125 の読み合わせ + C117) | unmet | - (C116・C126・C123 は met。不具合 E(マウス静止中にキーボードで閉じると、最後のマウスイベント時にポインタ下にあった view を SwiftUI の hover 追跡が保持し解放されない)を周回 25 で refreshPointerTracking により修正し、自前の実機再現で SurfaceView 5→3・スレッド 27→17・IOSurface 19→13 領域を確認。C124・C125 と C117 の人間確認待ち) |
| C87 | 必須 | 描画対象の判定と停止・再開集合の導出はモデル層(検証: C116) | met | cycle 25: just swift-test exit 0 (ProjectRenderTargetTests 21 件 passed) |
| C88 | 必須 | `zig build` が exit 0 | met | cycle 25: PATH=/opt/homebrew/opt/zig@0.15/bin:$PATH zig build exit 0 |
| C89 | 必須 | `just test` が exit 0 | met | cycle 25: just test exit 0 |
| C90 | 必須 | `just swift-test` が exit 0 | met | cycle 25: just swift-test exit 0 |
| C91 | 必須 | ノートのテスト群が macos/Tests/ に存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 25: just swift-test exit 0 (項目とテストの対応は cycle 8 の記録どおり、ProjectNoteTests のテストは今周回も削除・変更なしで passed) |
| C92 | 必須 | ノートの実機目視(検証: 人間) | unmet | - |
| C93 | 必須 | プライマリーペインのテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 25: just swift-test exit 0 (項目とテストの対応は cycle 9 の記録どおり、ProjectPrimaryPaneTests 35 件は今周回も削除・変更なしで passed) |
| C94 | 必須 | プライマリーペインの実機目視(検証: 人間) | unmet | - |
| C95 | 必須 | 削除保護のテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 25: just swift-test exit 0 (項目とテストの対応は cycle 6 の記録どおり、ProjectTerminatedTests 16 件 passed) |
| C96 | 必須 | 削除保護の実機目視(検証: 人間) | unmet | - |
| C97 | 必須 | ノート編集オーバーレイの編集ショートカット・100 行超過確認の実機目視(検証: 人間) | unmet | - |
| C98 | 必須 | 優先度・締切のテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 25: just swift-test exit 0 (項目とテストの対応は cycle 6 の記録どおり、ProjectPriorityDeadlineTests 18 件 passed) |
| C99 | 必須 | 優先度・締切の実機目視(検証: 人間) | unmet | - |
| C100 | 必須 | hide のテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 25: just swift-test exit 0 (項目とテストの対応は cycle 5 の記録どおり passed) |
| C101 | 必須 | hide の実機目視(検証: 人間) | unmet | - |
| C102 | 必須 | レイアウト型のテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 25: just swift-test exit 0 (項目とテストの対応は cycle 7 の記録どおり passed) |
| C103 | 必須 | レイアウト型の実機目視(検証: 人間) | unmet | - |
| C104 | 必須 | 改名完了: Projects/ が在り Groups/ が無い、C88〜C90 exit 0、可視文言に Group が無いことの目視(検証: test -d / test -e + C88〜C90 + 人間) | unmet | - (機械検査部分は周回 25 で test -d exit 0・test -e exit 1、C88〜C90 exit 0。可視文言は 2026-10-28 第 2 回の人間確認で Group なしだったが、周回 25 のコード変更で失効。再確認待ち) |
| C105 | 必須 | リモート判定のテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 25: just swift-test exit 0 (項目とテストの対応は cycle 5 の記録どおり passed) |
| C106 | 必須 | リモート split の実機目視(検証: 人間) | unmet | - |
| C107 | 必須 | プロジェクト一覧のテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 25: just swift-test exit 0 (項目とテストの対応は .idd/cycles/0010.md の「変更」節どおり。ProjectListRowSelectionTests は 11 件 passed、cycle 19 はテスト不変) |
| C108 | 必須 | プロジェクト一覧の実機目視(検証: 人間) | unmet | - |
| C109 | 必須 | 優先度リセットのテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 25: just swift-test exit 0 (項目とテストの対応は cycle 5 の記録どおり passed) |
| C110 | 必須 | 優先度リセットの実機目視(検証: 人間) | unmet | - |
| C111 | 必須 | 次トリガーのテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 25: just swift-test exit 0 (項目とテストの対応は cycle 5 の記録どおり passed) |
| C112 | 必須 | 次トリガーの実機目視(検証: 人間) | unmet | - |
| C113 | 必須 | キー変更の実機目視(検証: 人間) | unmet | - |
| C114 | 必須 | 一覧セル編集の IME の実機目視(検証: 人間) | unmet | - |
| C115 | 必須 | ショートカット一覧の実機目視(検証: 人間) | unmet | - |
| C116 | 必須 | 描画対象・停止/再開集合・解放・誕生時停止のテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 25: just swift-test exit 0 (ProjectRenderTargetTests 21 件 passed。全 5 項目の対応は cycle 2・3 の記録どおり) |
| C117 | 必須 | 描画停止・解放の実機観測(top / footprint、起動直後に落ちない、行 Delete 後のフォーカス、検証: 人間) | unmet | - (2026-10-28 第 2 回の人間確認で (1)(3)〜(6) は OK、(2) は不具合 E で例外。周回 25 で D・E を修正しコードが変わったため確認は失効。再確認待ち) |
| C121 | 必須 | 停止集合に誕生した描画対象外の surface を含める(stop = (after.retained − after.drawn) ∩ (before.drawn ∪ born))(検証: C116) | met | cycle 25: just swift-test exit 0 (ProjectRenderTargetTests 21 件 passed) |
| C122 | 必須 | 停止・再開の適用は RenderTargetTransition のみ(唯一の例外: SurfaceView が生成直後に判断なしで一律に set_occlusion(false) を送り、すべて停止状態で生まれる。再開は resume だけ)、SurfaceView.isDrawing を持たない、未生成 surface は未適用扱い(検証: C116 + 読み合わせ) | met | cycle 25: just swift-test exit 0 (C116 の ProjectRenderTargetTests 21 件 passed。grep -rn xghostty_surface_set_occlusion macos/Sources は 2 箇所: SurfaceView_AppKit.swift の init で xghostty_surface_new 成功直後に判断なしの set_occlusion(false)、BaseTerminalController.syncRenderTargetOcclusion の RenderTargetTransition の stop/resume。grep -rn isDrawing macos/Sources は exit 1(該当なし)。送れなかった id は applied(except:) で外す実装は不変。周回 25 の refreshPointerTracking は occlusion を送らず判断も持たないので適用経路は増えていない) |
| C123 | 必須 | SurfaceView の `.ghosttySelectionDidChange` 購読は `object:` を渡さず `[weak self]` の filter で絞る(検証: 読み合わせ + C90) | met | cycle 25: just swift-test exit 0 (SurfaceView_AppKit.swift の publisher(for: .ghosttySelectionDidChange) に object: が無く、debounce の前の filter が [weak self] で notification.object === self に絞ることを読み合わせた) |
| C124 | 必須 | `XGhostty.Surface.deinit` はメインスレッドなら同期的に `xghostty_surface_free`(検証: 読み合わせ + C88〜C90 + C117) | unmet | - (deinit の Thread.isMainThread 分岐は周回 25 でも読み合わせ済み、C88〜C90 は周回 25 で exit 0。C117 の起動直後に落ちない確認待ち) |
| C125 | 必須 | 一覧の行選択 Delete で閉じたとき新しい focus 先へキーボードフォーカスを移す(検証: C126 + 読み合わせ + C117) | unmet | - (C126 met、performCloseProjectListRow の .switched が moveKeyboardFocus を呼ぶことは読み合わせ済み。不具合 A/B/C は周回 21 で修正、2026-10-28 第 2 回の人間確認で解消を確認(周回 25 のコード変更で失効)。C117 の再確認待ち) |
| C126 | 必須 | 一覧セッション中の closeProject の focus 先・保持集合・セッション継続のテスト(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 25: just swift-test exit 0 (ProjectListRowSelectionTests の closingTheFocusedRowHandsTheNewFocusTargetAndKeepsTheSession(.switched と新 focus 先 surface・閉じた surface が retainedSurfaceIDs から消える・projectListActive 継続)と closingAnUnfocusedRowLeavesTheFocusedProjectAlone が passed) |
| C118 | 望ましい | マウスからノートを開く導線(検証: 人間) | unmet | - |
| C119 | 望ましい | ノート UI・プライマリー印の見た目の洗練(検証: 人間) | unmet | - |
| C120 | 望ましい | 全体ビューの非プライマリーペインのインジケータ(検証: 人間) | unmet | - |
