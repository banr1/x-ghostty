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

ideal_sha: 814061b7a04bc3e47283962b1f80ccf60f622a8d1f5d4321875cfaa48b57252b

| ID | 階層 | 条件 | 状態 | 証拠 |
|----|------|------|------|------|
| C1 | 必須 | プロジェクトごとに手書きの短いノートを保持できる(検証: C91) | met | cycle 38: just swift-test exit 0 (C91 は met、failed 0 件) |
| C2 | 必須 | ノート最大 100 行、保存時超過は確認し OK で先頭 100 行へ切詰め・Cancel で編集へ戻る(検証: C91 + C97) | unmet | - (C91 は cycle 34 で met。C97 の人間の確認が失効) |
| C3 | 必須 | ノートは永続化され再起動後に同じプロジェクトへ復元(検証: C91) | met | cycle 38: just swift-test exit 0 (C91 は met、failed 0 件) |
| C4 | 必須 | ノートはプロジェクトに属しペインに属さない(検証: C91) | met | cycle 38: just swift-test exit 0 (C91 は met、failed 0 件) |
| C5 | 必須 | `Cmd+E` でノート編集オーバーレイ、`Cmd+Enter` で保存して閉じる(検証: C91 + C92) | unmet | - (C92 の人間の確認が失効) |
| C6 | 必須 | オーバーレイで Esc は確認なしに破棄して閉じる(検証: C91 + C92) | unmet | - (C92 の人間の確認が失効) |
| C7 | 必須 | `Cmd+Enter` の fullscreen 既定割り当てを解除(検証: C92) | unmet | - (C92 の人間の確認が失効) |
| C8 | 必須 | `Cmd+Opt+E` で一望モードをトグル、Esc でも抜ける(検証: C92) | unmet | - (C92 の人間の確認が失効) |
| C9 | 必須 | 一望モードは visible なプロジェクトのみ表示(検証: C91) | met | cycle 38: just swift-test exit 0 (C91 は met) |
| C10 | 必須 | zoom 中に一望モードへ入ると zoom 解除(検証: C91) | met | cycle 38: just swift-test exit 0 (C91 は met) |
| C11 | 必須 | 一望モードは閲覧専用で編集・focus 移動しない(検証: C91) | met | cycle 38: just swift-test exit 0 (C91 は met) |
| C12 | 必須 | 一望モードで収まらないノートは切詰め、編集オーバーレイはスクロールで全文(検証: C92) | unmet | - (C92 の人間の確認が失効) |
| C13 | 必須 | ノート UI は端末領域を恒久占有しない(検証: C92) | unmet | - (C92 の人間の確認が失効) |
| C14 | 必須 | 既存機能と上流動作を退行させない(列挙した意図的変更を除く。OSC 7 検出の廃止・tmux 化・端末列を例外に追加)(検証: C88〜C90 exit 0 かつ既存テストが削除・無効化されず成功) | met | cycle 38: just swift-test exit 0 (zig build・just test も exit 0。failed 0 件。周回 38 で git diff HEAD -- macos/Tests src から消えた @Test は 15 件で、すべて C14 が意図的変更として列挙する ProjectRemoteSplitTests(OSC 7 検出の廃止)。Zig の test は消えていない。コアの reportPwd / apprt.surface.Message.pwd_change / Surface.zig の pwd_change / apprt.action.Pwd / xghostty_action_pwd_s は 5307c05 との差分が改名だけになり、C14 が列挙する「上流の形への復元」に当たる) |
| C15 | 必須 | ノートの判断ロジックはモデル層で XGhosttyTests から検証可能(検証: C91) | met | cycle 38: just swift-test exit 0 (C91 は met) |
| C16 | 必須 | SPEC.md / README.md をノート層仕様に合わせ、README の Building 節に 3 検証コマンド(検証: 周回の読み合わせ) | met | cycle 38: grep -n "Building" -A12 README.md exit 0 (zig build / just test / just swift-test の 3 行を確認。ノート層の実装は周回 12 の読み合わせ以降変わっていない) |
| C17 | 必須 | 各ペインはプライマリーフラグを持ち最初のペインがプライマリー(検証: C93) | met | cycle 38: just swift-test exit 0 (C93 は met) |
| C18 | 必須 | プライマリーはプロジェクト内で常に 1 つ(検証: C93) | met | cycle 38: just swift-test exit 0 (C93 は met) |
| C19 | 必須 | 全体ビューはプライマリーのみ描画、zoom 中は全ペイン(検証: C93 + C94) | unmet | - (C94 の人間の確認が失効) |
| C20 | 必須 | 全体ビューの入力・focus はプライマリーへ、zoom 解除時に寄せる(検証: C93) | met | cycle 38: just swift-test exit 0 (C93 は met) |
| C21 | 必須 | 全体ビューでペイン系操作は no-op(検証: C93) | met | cycle 38: just swift-test exit 0 (C93 は met) |
| C22 | 必須 | zoom 中 `Cmd+P` で focused ペインをプライマリーへ(検証: C93 + C94) | unmet | - (C94 の人間の確認が失効) |
| C23 | 必須 | プライマリーが閉じたら最近傍 leaf を昇格(検証: C93 + C94) | unmet | - (C94 の人間の確認が失効) |
| C24 | 必須 | プライマリーフラグの永続化と復元時正規化(検証: C93) | met | cycle 38: just swift-test exit 0 (C93 は met) |
| C25 | 必須 | プライマリー印は zoom 中かつ複数ペイン時のみ右上に表示(検証: C94) | unmet | - (C94 の人間の確認が失効) |
| C26 | 必須 | プライマリーの判断ロジックはモデル層(検証: C93) | met | cycle 38: just swift-test exit 0 (C93 は met) |
| C27 | 必須 | SPEC.md / README.md をプライマリーペイン層仕様に合わせる(検証: 周回の読み合わせ) | met | cycle 38: grep -c "@Test" macos/Tests/Projects/ProjectPrimaryPaneTests.swift exit 0 (35 件で SPEC §22.8 と一致。§22 の読み合わせは cycle 13、以降当該層は不変) |
| C28 | 必須 | プロジェクトを閉じる操作は常に確認ダイアログ(検証: C95 + C96) | unmet | - (C96 の人間の確認が失効) |
| C29 | 必須 | 最後のペインのプロセス(tmux 化後は tmux クライアント / ssh)が exit してもプロジェクトを閉じず終了済みで残す(検証: C95 + C96) | unmet | - (条件文が tmux 化で変わった。C96 の確認も失効) |
| C30 | 必須 | 終了済みペインで Enter によりペインのコマンド(tmux 化後は C129 の attach)を再起動(検証: C96) | unmet | - (周回 34 で再開のペインを同じ attach コマンドで起動するよう接続した。C96 の確認が要る) |
| C31 | 必須 | プロジェクト喪失経路は確認を経た明示的 close のみ(検証: C95 + C96) | unmet | - (C96 の人間の確認が失効) |
| C32 | 必須 | ノート編集オーバーレイで標準編集ショートカットと Undo/Redo が効く(検証: C97) | unmet | - (C97 の人間の確認が失効) |
| C33 | 必須 | 貼り付けで 100 行超過も C2 の確認を経る(検証: C91 + C97) | unmet | - (C97 の人間の確認が失効) |
| C34 | 必須 | 優先度 high/medium/low/未設定(検証: C98 + C99) | unmet | - (C99 の人間の確認が失効) |
| C35 | 必須 | 締切(日付のみ)、不正入力は未設定(検証: C98 + C99) | unmet | - (C99 の人間の確認が失効) |
| C36 | 必須 | 優先度・締切は一覧セルで設定し永続化(検証: C98 + C99) | unmet | - (C99 の人間の確認が失効) |
| C37 | 必須 | ラベル帯に優先度の印と締切を表示(検証: C99) | unmet | - (C99 の人間の確認が失効) |
| C38 | 必須 | 一望モードでノートと優先度・締切・次トリガーを表示(検証: C111 + C99・C112) | unmet | - (C99・C112 の人間の確認が失効) |
| C39 | 必須 | 締切超過を控えめに強調(1 段階のみ)(検証: C98 + C99) | unmet | - (C99 の人間の確認が失効) |
| C40 | 必須 | ソートは 5 値の永続化される状態、既定は手動(検証: C107 + C108) | unmet | - (C107 は cycle 34 で met。C108 の確認が失効) |
| C41 | 必須 | 各ソートキーの固定の向き・安定ソート・序数は visible 行の表示順(検証: C98・C107) | met | cycle 38: just swift-test exit 0 (C98・C107 は met) |
| C42 | 必須 | 一覧最上部のソートバーをキーボード・マウスで操作(検証: C107 + C108) | unmet | - (C107 は met、C108 の確認が失効) |
| C43 | 必須 | ソート有効中の即時再ソートと Opt+↑↓ の確認、ソートアクション廃止(検証: C107 + C108) | unmet | - (C107 は met、C108 の確認が失効) |
| C44 | 必須 | 優先度・締切・次トリガー・終了済みの判断ロジックはモデル層(検証: C95・C98・C111) | met | cycle 38: just swift-test exit 0 (C95・C98・C111 は met) |
| C45 | 必須 | SPEC.md / README.md を削除保護・ショートカット・優先度・締切層に合わせる(検証: 周回の読み合わせ) | met | cycle 38: grep -c "@Test" (ProjectTerminatedTests / ProjectPriorityDeadlineTests / ProjectSortStateTests / ProjectNextTriggerTests) exit 0 (16 / 18 / 13 / 7 件で SPEC §23.5・§24.5・§24.6 と一致。当該層は周回 19 の読み合わせ以降不変) |
| C46 | 必須 | `Cmd+Opt+H` で focused プロジェクトを即時 hidden(検証: C100 + C101) | unmet | - (C101 の人間の確認が失効) |
| C47 | 必須 | visible は最低 1 つ残る(検証: C100) | met | cycle 38: just swift-test exit 0 (C100 は met) |
| C48 | 必須 | hidden の復帰導線は一覧のみ、hidden シェルフ廃止(検証: C107 + C108) | unmet | - (C107 は met、C108 の確認が失効) |
| C49 | 必須 | レイアウト型 = 形 3 種 × 向き 2 種、余りは後半行へ(検証: C102 + C103) | unmet | - (C103 の人間の確認が失効) |
| C50 | 必須 | 完全一致する型を畳み、選択肢 1 つなら選ぶものが無い旨(検証: C102 + C103) | unmet | - (C103 の人間の確認が失効) |
| C51 | 必須 | `Cmd+Opt+L` でレイアウト型の選択オーバーレイ(検証: C103) | unmet | - (C103 の人間の確認が失効) |
| C52 | 必須 | レイアウト型は永続化、既定は横長型・行送り(検証: C102 + C103) | unmet | - (C103 の人間の確認が失効) |
| C53 | 必須 | 表示順のまま向きに従いスロットへ割当、序数が追従(検証: C102) | met | cycle 38: just swift-test exit 0 (C102 は met) |
| C54 | 必須 | visible 数変化時に記憶の型で自動適用(検証: C102 + C101・C103) | unmet | - (C101・C103 の人間の確認が失効) |
| C55 | 必須 | プロジェクト単位のレイアウト resize/equalize 廃止、zoom 中ペインは存続(検証: C103) | unmet | - (C103 の人間の確認が失効) |
| C56 | 必須 | レイアウト型の判断ロジックはモデル層(検証: C102) | met | cycle 38: just swift-test exit 0 (C102 は met) |
| C57 | 必須 | 「グループ」→「プロジェクト」全面改名(検証: C104) | met | cycle 38: test -d macos/Sources/Features/Projects exit 0 (test -e macos/Sources/Features/Groups は exit 1。C104 は周回 34 で取り直して met) |
| C58 | 必須 | 改名は純粋なリネームで退行なし(検証: C104 + C88〜C90) | met | cycle 38: just swift-test exit 0 (zig build・just test も exit 0。C104 は met) |
| C59 | 必須 | SPEC.md / README.md をレイアウト型・自動適用・hide・改名語彙に合わせる(検証: 周回の読み合わせ) | met | cycle 38: grep -c "@Test" macos/Tests/Projects/ProjectLayoutTypeTests.swift macos/Tests/Projects/ProjectLayoutSelectionTests.swift exit 0 (14 / 10 件で SPEC §26.5 と一致。当該層は周回 15 の読み合わせ以降不変) |
| C63 | 必須 | `Cmd+L` で一覧をトグル(Esc で閉じない・zoom を解除しない・端末列を含む 7 列・8 割)(検証: C107 + C108) | unmet | - (周回 32 で端末列を足して 7 列化、C107 は met。C108 の人間の確認が要る) |
| C64 | 必須 | 一覧は単一の並び、手動順・列順・ソート状態を永続化、hidden も同色(検証: C107 + C108) | unmet | - (C107 は met、C108 の確認が失効) |
| C65 | 必須 | Notion 流儀のセルカーソル・Enter 編集・候補列挙(端末列を含む)(検証: C107 + C108) | unmet | - (周回 32 で端末列の候補列挙を実装、C107 は met。C108 の人間の確認が要る) |
| C66 | 必須 | ノート列編集は全行対象、Shift+Enter で改行、一覧内 `Cmd+Opt+E` は全行表示トグル(検証: C107 + C108) | unmet | - (C107 は met、C108 の確認が失効) |
| C67 | 必須 | `Cmd+矢印` は端移動、`Opt+矢印` で行・列並べ替え(検証: C107 + C108) | unmet | - (C107 は met、C108 の確認が失効) |
| C68 | 必須 | `Cmd+N` は一覧での新規プロジェクト作成(検証: C107 + C108) | unmet | - (C107 は met、C108 の確認が失効) |
| C69 | 必須 | 一覧の `Cmd+Enter` で focus(hidden 行は近傍 visible へ)(検証: C107 + C108) | unmet | - (C107 は met、C108 の確認が失効) |
| C70 | 必須 | 一覧の判断ロジック(端末の候補を含む)はモデル層(検証: C107) | met | cycle 38: just swift-test exit 0 (C107 は met。端末列の候補・Delete・コピー・貼り付けは ProjectListCandidateMenu.opened / deleteListCellValue / ProjectListClipboard にあり ProjectTerminalColumnTests 14 件が passed) |
| C71 | 必須 | 次トリガー 4 値(チームメンバーは外部へ移行)(検証: C107・C111 + C112) | unmet | - (C107・C111 は met、C112 の確認が失効) |
| C72 | 必須 | 毎日 6:00 境界で全プロジェクトの優先度を未設定へ(検証: C109 + C110) | unmet | - (C110 の人間の確認が失効) |
| C73 | 必須 | 最終リセット日付を永続化し作業日ごとに 1 回(検証: C109 + C110) | unmet | - (C110 の人間の確認が失効) |
| C74 | 必須 | 自動リセットの並びはソート状態に従う(検証: C109) | met | cycle 38: just swift-test exit 0 (C109 は met) |
| C75 | 必須 | リセット判定はモデル層(検証: C109) | met | cycle 38: just swift-test exit 0 (C109 は met) |
| C76 | 必須 | SPEC.md / README.md を端末登録・tmux セッション・OSC 7 検出の廃止〜閉じた surface の解放までの仕様に合わせる(検証: 周回の読み合わせ) | unmet | - (条件文に端末登録と tmux セッションが加わった。SPEC/README は未更新。§27.1 の列は 6 列のまま。周回 38 で OSC 7 検出(PaneLocationTracker・前景プロセス判定・ProjectRemoteSplitTests)とコアのホスト転送を撤去したので、SPEC §29 のリモート split の記述は実装と食い違っている) |
| C77 | 必須 | 締切セルの Enter で 10 択の日付候補(検証: C107 + C108) | unmet | - (C107 は met、C108 の確認が失効) |
| C78 | 必須 | 一覧テキスト列のセル編集が日本語 IME を受け付ける(検証: C114) | unmet | - (C114 の人間の確認が失効) |
| C79 | 必須 | セルカーソルの Delete で列ごとの値削除(端末は手元へ)(検証: C107 + C108) | unmet | - (周回 32 で端末列の Delete(手元へ戻す)を実装、C107 は met。C108 の人間の確認が要る) |
| C80 | 必須 | Esc で行選択、行選択の Delete で確認付き削除(検証: C107 + C108) | unmet | - (C107 は met、C108 の確認が失効) |
| C81 | 必須 | `Cmd+/` でショートカット一覧をトグル(検証: C115) | unmet | - (C115 の人間の確認が失効) |
| C82 | 必須 | `Cmd+K` の clear_screen 既定割り当て解除(検証: C113) | unmet | - (C113 の人間の確認が失効) |
| C83 | 必須 | 一覧セルのクリップボード操作(端末列は登録名のみ)と候補列挙中の Tab 横移動(検証: C107 + C108) | unmet | - (周回 32 で端末列のコピーと登録名のみの貼り付けを実装、C107 は met。C108 の人間の確認が要る) |
| C84 | 必須 | 描画対象の定義(全体ビュー: visible のプライマリー / zoom: 対象の全ペイン)(検証: C116) | met | cycle 38: just swift-test exit 0 (ProjectRenderTargetTests passed、failed 0 件) |
| C85 | 必須 | 描画対象外は生成時を含めレンダラとディスプレイリンクを停止し復帰時に再開(検証: C116 + C117) | unmet | - (C116 は met。C117 の人間の確認が失効) |
| C86 | 必須 | 閉じた surface を経路によらず undo 期限後に SurfaceView〜IOSurface まで解放(検証: C116・C126 + C123〜C125 の読み合わせ + C117) | unmet | - (C116・C126 は met。C117 の人間の確認が失効) |
| C87 | 必須 | 描画対象の判定と停止・再開集合の導出はモデル層(検証: C116) | met | cycle 38: just swift-test exit 0 (ProjectRenderTargetTests passed) |
| C88 | 必須 | `zig build` が exit 0 | met | cycle 38: PATH=/opt/homebrew/opt/zig@0.15/bin:$PATH zig build exit 0 |
| C89 | 必須 | `just test` が exit 0 | met | cycle 38: just test exit 0 |
| C90 | 必須 | `just swift-test` が exit 0 | met | cycle 38: just swift-test exit 0 |
| C91 | 必須 | ノートのテスト群が macos/Tests/ に存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 38: just swift-test exit 0 (項目とテストの対応は cycle 8 の記録どおり、ProjectNoteTests は削除・変更なしで passed) |
| C92 | 必須 | ノートの実機目視(検証: 人間) | unmet | - (2026-10-28T15:01:16Z の刻印は周回 31 の対象ファイル変更で失効。tmux 化の実装が揃った後に再確認を問う) |
| C93 | 必須 | プライマリーペインのテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 38: just swift-test exit 0 (項目とテストの対応は cycle 9 の記録どおり、ProjectPrimaryPaneTests 35 件 passed) |
| C94 | 必須 | プライマリーペインの実機目視(検証: 人間) | unmet | - (刻印が周回 31 で失効。tmux 化の後に再確認を問う) |
| C95 | 必須 | 削除保護のテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 38: just swift-test exit 0 (項目とテストの対応は cycle 6 の記録どおり、ProjectTerminatedTests 16 件 passed) |
| C96 | 必須 | 削除保護の実機目視(検証: 人間) | unmet | - (刻印が周回 31 で失効。tmux 化で終了済みと再開の経路が変わるので、その後に再確認を問う) |
| C97 | 必須 | ノート編集オーバーレイの編集ショートカット・100 行超過確認の実機目視(検証: 人間) | unmet | - (刻印が周回 31 で失効。tmux 化の後に再確認を問う) |
| C98 | 必須 | 優先度・締切のテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 38: just swift-test exit 0 (項目とテストの対応は cycle 6 の記録どおり、ProjectPriorityDeadlineTests 18 件 passed) |
| C99 | 必須 | 優先度・締切の実機目視(検証: 人間) | unmet | - (刻印が周回 31 で失効。tmux 化の後に再確認を問う) |
| C100 | 必須 | hide のテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 38: just swift-test exit 0 (項目とテストの対応は cycle 5 の記録どおり passed) |
| C101 | 必須 | hide の実機目視(検証: 人間) | unmet | - (刻印が周回 31 で失効。tmux 化の後に再確認を問う) |
| C102 | 必須 | レイアウト型のテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 38: just swift-test exit 0 (項目とテストの対応は cycle 7 の記録どおり passed) |
| C103 | 必須 | レイアウト型の実機目視(検証: 人間) | unmet | - (刻印が周回 31 で失効。tmux 化の後に再確認を問う) |
| C104 | 必須 | 改名完了: Projects/ が在り Groups/ が無い、C88〜C90 exit 0、可視文言に Group が無いことの目視(検証: test -d / test -e + C88〜C90 + 人間) | met | cycle 38: test -d macos/Sources/Features/Projects exit 0 (test -e macos/Sources/Features/Groups は exit 1、C88〜C90 は周回 38 で exit 0。補足: 可視文言の目視は 2026-10-28T14:21:46Z の人間の確認でメニューに Group なし。周回 32 で足した可視文言は列見出し「terminal」とヒント「↩ lists terminals」で Group を含まない。周回 34〜38 は可視文言を足していない) |
| C107 | 必須 | プロジェクト一覧のテスト群が存在し成功(既定列順に端末を含む 7 列、端末列の候補・Delete・貼り付けを含む)(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 38: just swift-test exit 0 (既定列順 7 列は ProjectLedgerTests と ProjectTerminalColumnTests.theTerminalColumnIsASelectionColumnAfterTheTitle、端末列の候補・Delete・コピー・貼り付けは ProjectTerminalColumnTests、6 列の保存からの移行は ProjectLedgerTests.columnOrderRoundTripsAndNormalizesCorruptSaves。他の項目の対応は cycle 6 の記録どおり。failed 0 件) |
| C108 | 必須 | プロジェクト一覧の実機目視(7 列)(検証: 人間) | unmet | - (条件文が 7 列に変わり、刻印も周回 31 で失効) |
| C109 | 必須 | 優先度リセットのテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 38: just swift-test exit 0 (項目とテストの対応は cycle 5 の記録どおり passed) |
| C110 | 必須 | 優先度リセットの実機目視(検証: 人間) | unmet | - (刻印が周回 31 で失効。tmux 化の後に再確認を問う) |
| C111 | 必須 | 次トリガーのテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 38: just swift-test exit 0 (項目とテストの対応は cycle 5 の記録どおり passed) |
| C112 | 必須 | 次トリガーの実機目視(検証: 人間) | unmet | - (刻印が周回 31 で失効。tmux 化の後に再確認を問う) |
| C113 | 必須 | キー変更の実機目視(検証: 人間) | unmet | - (刻印が周回 31 で失効。tmux 化の後に再確認を問う) |
| C114 | 必須 | 一覧セル編集の IME の実機目視(検証: 人間) | unmet | - (刻印が周回 31 で失効。tmux 化の後に再確認を問う) |
| C115 | 必須 | ショートカット一覧の実機目視(検証: 人間) | unmet | - (刻印が周回 31 で失効。tmux 化の後に再確認を問う) |
| C116 | 必須 | 描画対象・停止/再開集合・解放・誕生時停止のテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 38: just swift-test exit 0 (ProjectRenderTargetTests 21 件 passed。全 5 項目の対応は cycle 2・3 の記録どおり) |
| C117 | 必須 | 描画停止・解放の実機観測(top / footprint、起動直後に落ちない、行 Delete 後のフォーカス、検証: 人間) | unmet | - (刻印が周回 31 で失効。tmux 化でペインのプロセス構成が変わるので、その後に再観測を問う) |
| C121 | 必須 | 停止集合に誕生した描画対象外の surface を含める(stop = (after.retained − after.drawn) ∩ (before.drawn ∪ born))(検証: C116) | met | cycle 38: just swift-test exit 0 (ProjectRenderTargetTests 21 件 passed) |
| C122 | 必須 | 停止・再開の適用は RenderTargetTransition のみ(生成直後の一律 set_occlusion(false) が唯一の例外)、SurfaceView.isDrawing を持たない(検証: C116 + 読み合わせ) | met | cycle 38: just swift-test exit 0 (C116 passed。grep -rn xghostty_surface_set_occlusion macos/Sources は 2 箇所(SurfaceView_AppKit.swift の init 直後の一律停止と BaseTerminalController.syncRenderTargetOcclusion)、grep -rn isDrawing macos/Sources は exit 1。周回 38 で取り直した。周回 38 が OSSurfaceView から外したのは OSC 7 の位置追跡だけで、停止の経路には触れていない) |
| C123 | 必須 | SurfaceView の `.ghosttySelectionDidChange` 購読は `object:` を渡さず `[weak self]` の filter で絞る(検証: 読み合わせ + C90) | met | cycle 38: just swift-test exit 0 (SurfaceView_AppKit.swift:295 の publisher(for: .ghosttySelectionDidChange) に object: が無く [weak self] の filter で絞ることを周回 38 で読み合わせた) |
| C124 | 必須 | `XGhostty.Surface.deinit` はメインスレッドなら同期的に `xghostty_surface_free`(検証: 読み合わせ + C88〜C90 + C117) | unmet | - (読み合わせと C88〜C90 は揃う。C117 の人間の確認が失効) |
| C125 | 必須 | 一覧の行選択 Delete で閉じたとき新しい focus 先へキーボードフォーカスを移す(検証: C126 + 読み合わせ + C117) | unmet | - (C126 と読み合わせは揃う。C117 の人間の確認が失効) |
| C126 | 必須 | 一覧セッション中の closeProject の focus 先・保持集合・セッション継続のテスト(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 38: just swift-test exit 0 (ProjectListRowSelectionTests の 2 件が passed) |
| C127 | 必須 | 端末を設定ファイルに登録(表示名・ホスト・色)、hostname 一致を手元、登録なしは暗黙の手元、再読み込みで反映(検証: C136 + C137) | unmet | - (周回 37 で設定キー `project-terminal = <name>,<host>[,<color>]`(繰り返し可、src/config/Config.zig の ProjectTerminals、C へは改行区切りの 1 文字列)を足し、AppDelegate の init と設定変更で ProjectTerminalRegistry.shared を、BaseTerminalController の設定変更で workspace.terminalRegistry を差し替えるよう接続した。--config-file で登録した手元の端末の色が新しいセッションの status-style に乗ることを早期確認(この周回の変更後なので出典にしない)。C137 の観測が残る) |
| C128 | 必須 | プロジェクトの端末(既定は手元)、一覧の端末列で候補選択・Delete で手元・登録名のみ貼り付け、永続化、欠落は手元扱い(検証: C136 + C137) | unmet | - (周回 32 で ProjectState.terminalName と一覧の端末列を実装。周回 34 で split と再開のペインがプロジェクトの現在の端末で起動するよう接続した。C137 の観測が残る) |
| C129 | 必須 | 全ペインを端末上の tmux セッションへ attach するコマンドで起動、セッション名 `<ID>-<n>`、ペインごとの端末・セッション名を永続化(検証: C136 + C137) | unmet | - (周回 34 で起動時の初期ペイン・新規プロジェクト(newProjectSplit / createProjectFromList)・split・終了済みからの再開・復元の全経路で surface の command を attach コマンドにした(ProjectState.new / launchCommand / splitLaunchCommand / restartLaunchCommand、復元は TmuxPaneRestore)。ProjectTmuxLaunchTests 11 件 passed。C137 の観測が残る) |
| C130 | 必須 | 開始ディレクトリ `~/workspace/<タイトル>` → `~/workspace` → ホーム、split は `#{pane_current_path}` を引き継ぐ(検証: C136 + C137) | unmet | - (規則は TmuxSession.attachCommand、周回 34 で split は元ペインのセッションから .inherit で起動するよう接続した。C137 の観測が残る) |
| C131 | 必須 | attach 時にそのセッションだけへ status-style・status-left・prefix C-s を設定、リネームで status-left を更新(検証: C136 + C137) | unmet | - (attach 時の設定は周回 34 の接続で attach コマンドに乗る。周回 36 でリネーム時の更新を接続した: BaseTerminalController の workspace.$state の sink が TmuxOpenPanes.retitles で前後とも開いているペインのうちプロジェクトのタイトルが変わったものを導き、TmuxSession.retitleArguments を Process 実行する(全リネーム経路を拾う)。ProjectTmuxPaneTests に 3 件。C137 の観測が残る) |
| C132 | 必須 | tmux / ssh の終了でペインは終了済み、Enter で同じ attach を再実行(検証: C136 + C137) | unmet | - (周回 34 で Enter の再開が終了済みペインのセッションの attach コマンドで起動するよう接続した。C137 の観測が残る) |
| C133 | 必須 | 閉じたペインのセッションを undo 期限後に kill、undo で戻せば kill しない(検証: C136 + C137) | unmet | - (周回 35 で接続した: BaseTerminalController が workspace.$state の変化ごとに TmuxOpenPanes.advance で木から消えたペインを記録し、undoExpiration + 1 秒後に TmuxOpenPanes.killTargets(戻ったペインと、開いているペインが使うセッションを除く)を killArguments で Process 実行する。窓を閉じる(removeAllSurfaces)と止める。ProjectTmuxPaneTests に 5 件。C137 の観測が残る) |
| C134 | 必須 | 手元でない端末への ssh に TERM=xterm-256color を渡す(検証: C136 + C137) | unmet | - (TmuxSession.attachCommand に組み込み済みで、周回 34 でペインに接続した。C137 の観測が残る) |
| C135 | 必須 | 端末・セッション・コマンド・候補・kill 対象の判断ロジックはモデル層(検証: C136) | met | cycle 38: just swift-test exit 0 (C136 は met。端末の読み込みと手元判定は ProjectTerminalRegistry、プロジェクトの端末は ProjectState.terminalName、セッション名・attach コマンド・開始ディレクトリ・セッションオプションは TmuxSession、ペインごとの起動コマンドは ProjectState.launchCommand / splitLaunchCommand / restartLaunchCommand と TmuxPaneRestore、端末列の候補・Delete・貼り付けは ProjectListCandidateMenu / ProjectListClipboard、kill 対象は TmuxSession.killTargets と、状態の変化から閉じたペインと生き残るセッションを導く TmuxOpenPanes にあり、すべて XGhosttyTests から検証している) |
| C136 | 必須 | 端末登録と tmux セッションのテスト群(9 項目)が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 38: just swift-test exit 0 (failed 0 件。項目 1・3・4・5・6 は ProjectTerminalTests 23 件(周回 37 で設定の行分割 configLinesSplitIntoRegistrations と再読み込み reloadedRegistrationsReplaceTheRegistry を追加)、項目 2・7 は ProjectTerminalColumnTests 14 件、項目 8 は ProjectTmuxPaneTests の killTargetsAreSessionNamesGroupedByTerminal / aPaneBroughtBackByUndoIsNotKilled / aTerminatedPaneIsAKillTargetWhenItsProjectCloses と周回 35 の TmuxOpenPanes の 5 件、項目 6 の retitle は周回 36 の TmuxOpenPanes.retitles の 3 件、項目 9 は paneTerminalsAndSessionNamesRoundTrip / saveKeepsOnlyPanesInTheTreeButKeepsTheHighestIndex と ProjectTmuxLaunchTests.restoredPanesReattachToTheirSavedSessions。いずれのファイルも削除・変更なしで passed) |
| C137 | 必須 | 端末登録と tmux セッションの実機観測(Mac mini、ssh ループバック、screencapture と tmux の出力)(検証: 周回の実機観測) | unmet | - (周回 38 時点で C127〜C134 の実装と OSC 7 検出の撤去は揃った。ssh ループバックの準備は、IDEAL の前提が許す ~/.ssh の編集を、周回のハーネスの権限設定が読み書きとも拒否するため未着手) |
| C138 | 必須 | 2 台の実機での目視(Mac mini の tmux・再起動後の再 attach・切断後の再 attach)(検証: 人間) | unmet | - |
| C118 | 望ましい | マウスからノートを開く導線(検証: 人間) | unmet | - |
| C119 | 望ましい | ノート UI・プライマリー印の見た目の洗練(検証: 人間) | unmet | - |
| C120 | 望ましい | 全体ビューの非プライマリーペインのインジケータ(検証: 人間) | unmet | - |
