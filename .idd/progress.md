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

ideal_sha: 3e6f1e8a2583a52baaea243bc260ba44b7f166443bd7862b4ffb344d2d1cbed2

| ID | 階層 | 条件 | 状態 | 証拠 |
|----|------|------|------|------|
| C1 | 必須 | プロジェクトごとに手書きの短いノートを保持できる(検証: C91) | met | cycle 53: just swift-test exit 0 (C91 は met、failed 0 件) |
| C2 | 必須 | ノート最大 100 行、保存時超過は確認し OK で先頭 100 行へ切詰め・Cancel で編集へ戻る(検証: C91 + C97) | unmet | - (C97 が周回 50 の対象ファイル変更で失効) |
| C3 | 必須 | ノートは永続化され再起動後に同じプロジェクトへ復元(検証: C91) | met | cycle 53: just swift-test exit 0 (C91 は met、failed 0 件) |
| C4 | 必須 | ノートはプロジェクトに属しペインに属さない(検証: C91) | met | cycle 53: just swift-test exit 0 (C91 は met、failed 0 件) |
| C5 | 必須 | `Cmd+E` でノート編集オーバーレイ、`Cmd+Enter` で保存して閉じる(検証: C91 + C92) | unmet | - (C92 が周回 50 の対象ファイル変更で失効) |
| C6 | 必須 | オーバーレイで Esc は確認なしに破棄して閉じる(検証: C91 + C92) | unmet | - (C92 が周回 50 の対象ファイル変更で失効) |
| C7 | 必須 | `Cmd+Enter` の fullscreen 既定割り当てを解除(検証: C92) | unmet | - (C92 が周回 50 の対象ファイル変更で失効) |
| C8 | 必須 | `Cmd+Opt+E` で一望モードをトグル、Esc でも抜ける(検証: C92) | unmet | - (C92 が周回 50 の対象ファイル変更で失効) |
| C9 | 必須 | 一望モードは visible なプロジェクトのみ表示(検証: C91) | met | cycle 53: just swift-test exit 0 (C91 は met) |
| C10 | 必須 | zoom 中に一望モードへ入ると zoom 解除(検証: C91) | met | cycle 53: just swift-test exit 0 (C91 は met) |
| C11 | 必須 | 一望モードは閲覧専用で編集・focus 移動しない(検証: C91) | met | cycle 53: just swift-test exit 0 (C91 は met) |
| C12 | 必須 | 一望モードで収まらないノートは切詰め、編集オーバーレイはスクロールで全文(検証: C92) | unmet | - (C92 が周回 50 の対象ファイル変更で失効) |
| C13 | 必須 | ノート UI は端末領域を恒久占有しない(検証: C92) | unmet | - (C92 が周回 50 の対象ファイル変更で失効) |
| C14 | 必須 | 既存機能と上流動作を退行させない(列挙した意図的変更を除く。台座型の廃止・種別列の追加(8 列化)・上限 24 と序数の配置順追従を例外に追加)(検証: C88〜C90 exit 0 かつ既存テストが削除・無効化されず成功) | met | cycle 53: just swift-test exit 0 (zig build・just test も周回 53 で exit 0。failed 0 件。周回 53 はテストを 2 件足しただけで削除は無い。周回 51 で削除したテストは台座型の 2 件(pedestalStacksTheTopRuleOverAFullWidthBottom・pedestalAssignsTheBottomSlotLast)だけで、C14 の例外「台座型の廃止」に当たる。周回 52 は上限 9 を名に持つ 2 件を改名(restoringPrunesALegacyTreeWithMoreLeavesThanTheCap・decodingCapsTheVisibleProjects)し、上限の例外に合わせて期待値を直した。削除・無効化は無い) |
| C15 | 必須 | ノートの判断ロジックはモデル層で XGhosttyTests から検証可能(検証: C91) | met | cycle 53: just swift-test exit 0 (C91 は met) |
| C16 | 必須 | SPEC.md / README.md をノート層仕様に合わせ、README の Building 節に 3 検証コマンド(検証: 周回の読み合わせ) | met | cycle 53: grep -n "Building" -A12 README.md exit 0 (zig build / just test / just swift-test の 3 行を確認。周回 53 の SPEC の差分はノート層に触れていない) |
| C17 | 必須 | 各ペインはプライマリーフラグを持ち最初のペインがプライマリー(検証: C93) | met | cycle 53: just swift-test exit 0 (C93 は met) |
| C18 | 必須 | プライマリーはプロジェクト内で常に 1 つ(検証: C93) | met | cycle 53: just swift-test exit 0 (C93 は met) |
| C19 | 必須 | 全体ビューはプライマリーのみ描画、zoom 中は全ペイン(検証: C93 + C94) | unmet | - (C94 が周回 50 の対象ファイル変更で失効) |
| C20 | 必須 | 全体ビューの入力・focus はプライマリーへ、zoom 解除時に寄せる(検証: C93) | met | cycle 53: just swift-test exit 0 (C93 は met) |
| C21 | 必須 | 全体ビューでペイン系操作は no-op(検証: C93) | met | cycle 53: just swift-test exit 0 (C93 は met) |
| C22 | 必須 | zoom 中 `Cmd+P` で focused ペインをプライマリーへ(検証: C93 + C94) | unmet | - (C94 が周回 50 の対象ファイル変更で失効) |
| C23 | 必須 | プライマリーが閉じたら最近傍 leaf を昇格(検証: C93 + C94) | unmet | - (C94 が周回 50 の対象ファイル変更で失効) |
| C24 | 必須 | プライマリーフラグの永続化と復元時正規化(検証: C93) | met | cycle 53: just swift-test exit 0 (C93 は met) |
| C25 | 必須 | プライマリー印は zoom 中かつ複数ペイン時のみ右上に表示(検証: C94) | unmet | - (C94 が周回 50 の対象ファイル変更で失効) |
| C26 | 必須 | プライマリーの判断ロジックはモデル層(検証: C93) | met | cycle 53: just swift-test exit 0 (C93 は met) |
| C27 | 必須 | SPEC.md / README.md をプライマリーペイン層仕様に合わせる(検証: 周回の読み合わせ) | met | cycle 53: grep -c "@Test" macos/Tests/Projects/ProjectPrimaryPaneTests.swift exit 0 (35 件で SPEC §22.8 と一致。周回 53 の差分は当該層に触れていない) |
| C28 | 必須 | プロジェクトを閉じる操作は常に確認ダイアログ(検証: C95 + C96) | unmet | - (C96 が周回 50 の対象ファイル変更で失効) |
| C29 | 必須 | 最後のペインのプロセス(tmux 化後は tmux クライアント / ssh)が exit してもプロジェクトを閉じず終了済みで残す(検証: C95 + C96) | unmet | - (C96 が周回 50 の対象ファイル変更で失効) |
| C30 | 必須 | 終了済みペインで Enter によりペインのコマンド(tmux 化後は C129 の attach)を再起動(検証: C96) | unmet | - (C96 が周回 50 の対象ファイル変更で失効) |
| C31 | 必須 | プロジェクト喪失経路は確認を経た明示的 close のみ(検証: C95 + C96) | unmet | - (C96 が周回 50 の対象ファイル変更で失効) |
| C32 | 必須 | ノート編集オーバーレイで標準編集ショートカットと Undo/Redo が効く(検証: C97) | unmet | - (C97 が周回 50 の対象ファイル変更で失効) |
| C33 | 必須 | 貼り付けで 100 行超過も C2 の確認を経る(検証: C91 + C97) | unmet | - (C97 が周回 50 の対象ファイル変更で失効) |
| C34 | 必須 | 優先度 high/medium/low/未設定(検証: C98 + C99) | unmet | - (C98 は序数の改訂で未達、C99 は周回 50 で失効) |
| C35 | 必須 | 締切(日付のみ)、不正入力は未設定(検証: C98 + C99) | unmet | - (C98 は序数の改訂で未達、C99 は周回 50 で失効) |
| C36 | 必須 | 優先度・締切は一覧セルで設定し永続化(検証: C98 + C99) | unmet | - (C98 は序数の改訂で未達、C99 は周回 50 で失効) |
| C37 | 必須 | ラベル帯に優先度の印と締切を表示(検証: C99) | unmet | - (C99 が周回 50 の対象ファイル変更で失効) |
| C38 | 必須 | 一望モードでノートと優先度・締切・次トリガーを表示(検証: C111 + C99・C112) | unmet | - (C99・C112 が周回 50 の対象ファイル変更で失効) |
| C39 | 必須 | 締切超過を控えめに強調(1 段階のみ)(検証: C98 + C99) | unmet | - (C98 は序数の改訂で未達、C99 は周回 50 で失効) |
| C40 | 必須 | ソートは 5 値の永続化される状態、既定は手動(検証: C107 + C108) | unmet | - (C107 は周回 52 で met。C108 は人間の確認待ち) |
| C41 | 必須 | 各ソートキーの固定の向き・安定ソート・序数は配置順(Core → Side、各種別内は表示順)の visible(検証: C98・C107) | met | cycle 53: just swift-test exit 0 (C98・C107 は met。序数は onlyTheFirstNineInPlacementOrderHaveANumber が先頭 9 つを確かめる) |
| C42 | 必須 | 一覧最上部のソートバーをキーボード・マウスで操作(検証: C107 + C108) | unmet | - (C107 は周回 52 で met。C108 は人間の確認待ち) |
| C43 | 必須 | ソート有効中の即時再ソートと Opt+↑↓ の確認、ソートアクション廃止(検証: C107 + C108) | unmet | - (C107 は周回 52 で met。C108 は人間の確認待ち) |
| C44 | 必須 | 優先度・締切・次トリガー・終了済みの判断ロジックはモデル層(検証: C95・C98・C111) | met | cycle 53: just swift-test exit 0 (C95・C98・C111 は met) |
| C45 | 必須 | SPEC.md / README.md を削除保護・ショートカット・優先度・締切層に合わせる(検証: 周回の読み合わせ) | met | cycle 53: grep -c "@Test" (ProjectTerminatedTests / ProjectPriorityDeadlineTests / ProjectSortStateTests / ProjectNextTriggerTests) exit 0 (18 / 19 / 13 / 7 件で SPEC §23.5・§24.5・§24.6 と一致。周回 51 で §24.5 の件数と序数の配置順の記述を更新した) |
| C46 | 必須 | `Cmd+Opt+H` で focused プロジェクトを即時 hidden(検証: C100 + C101) | unmet | - (C101 が周回 50 の対象ファイル変更で失効) |
| C47 | 必須 | visible は最低 1 つ残る(検証: C100) | met | cycle 53: just swift-test exit 0 (C100 は met) |
| C48 | 必須 | hidden の復帰導線は一覧のみ、hidden シェルフ廃止(検証: C107 + C108) | unmet | - (C107 は周回 52 で met。C108 は人間の確認待ち) |
| C49 | 必須 | レイアウト型 = 形 2 種 × 向き 2 種(台座型廃止)、余りは後半行へ、行内幅は Core 1・Side 1/2 の重み、縦長型は転置(検証: C102 + C103・C139) | unmet | - (周回 51 で実装し C102 は met。C103 は人間の確認待ち、C139 は実機観測待ち) |
| C50 | 必須 | visible 1〜24 で完全一致する型を畳み、選択肢 1 つなら選ぶものが無い旨(検証: C102 + C103) | unmet | - (周回 51 で実装し C102 は met。C103 は人間の確認待ち) |
| C51 | 必須 | `Cmd+Opt+L` でレイアウト型の選択オーバーレイ(検証: C103) | unmet | - (C103 が周回 50 の対象ファイル変更で失効) |
| C52 | 必須 | レイアウト型は永続化、既定は横長型・行送り、保存された台座型は横長型へ移行(検証: C102 + C103) | unmet | - (周回 51 で実装し C102 は met。C103 は人間の確認待ち) |
| C53 | 必須 | Core → Side の順(各種別内は表示順)に向きに従いスロットへ割当、序数が追従(検証: C102) | met | cycle 53: just swift-test exit 0 (C102 は met。coreComesBeforeSideEachKindInRowOrder・theSlotsAssignCoreThenSideFollowingTheOrientation が passed) |
| C54 | 必須 | visible 数または visible の種別の変化時に記憶の型で自動適用(検証: C102 + C101・C103) | unmet | - (周回 51 で実装し C102 は met。C101・C103 は人間の確認待ち) |
| C55 | 必須 | プロジェクト単位のレイアウト resize/equalize 廃止、zoom 中ペインは存続(検証: C103) | unmet | - (C103 が周回 50 の対象ファイル変更で失効) |
| C56 | 必須 | レイアウト型の判断ロジックはモデル層(検証: C102) | met | cycle 53: just swift-test exit 0 (C102 は met。判断は ProjectLayoutType.swift と WorkspaceState.visibleProjectIDs にある) |
| C57 | 必須 | 「グループ」→「プロジェクト」全面改名(検証: C104) | met | cycle 53: test -d macos/Sources/Features/Projects exit 0 (test -e macos/Sources/Features/Groups は exit 1。C104 は met) |
| C58 | 必須 | 改名は純粋なリネームで退行なし(検証: C104 + C88〜C90) | met | cycle 53: just swift-test exit 0 (zig build・just test も exit 0。C104 は met) |
| C59 | 必須 | SPEC.md / README.md をレイアウト型・自動適用・hide・改名語彙に合わせる(検証: 周回の読み合わせ) | met | cycle 53: grep -n "台座\|pedestal" SPEC.md README.md exit 0 (廃止と移行の記述だけが残る。SPEC §26 全節・§7.3 の序数・§24.4・§27.1 と README の Layout types を実装と読み合わせ、テスト件数 31 / 10 も §26.5 と一致。上限 24 は周回 52 で §7.3 と一緒に直した) |
| C63 | 必須 | `Cmd+L` で一覧をトグル(Esc で閉じない・zoom を解除しない・種別と端末を含む 8 列・8 割)(検証: C107 + C108) | unmet | - (8 列は周回 50 で実装。C107 は周回 52 で met。C108 は人間の確認待ち) |
| C64 | 必須 | 一覧は単一の並び、手動順・列順・ソート状態を永続化、hidden も同色、序数は C41 の配置順(検証: C107 + C108) | unmet | - (序数の配置順は周回 51・52 で実装。C107 は周回 52 で met。C108 は人間の確認待ち) |
| C65 | 必須 | Notion 流儀のセルカーソル・Enter 編集・候補列挙(端末・種別列を含む)(検証: C107 + C108) | unmet | - (種別列の候補は周回 50 で実装。C107 は周回 52 で met。C108 は人間の確認待ち) |
| C66 | 必須 | ノート列編集は全行対象、Shift+Enter で改行、一覧内 `Cmd+Opt+E` は全行表示トグル(検証: C107 + C108) | unmet | - (C107 は周回 52 で met。C108 は人間の確認待ち) |
| C67 | 必須 | `Cmd+矢印` は端移動、`Opt+矢印` で行・列並べ替え(検証: C107 + C108) | unmet | - (C107 は周回 52 で met。C108 は人間の確認待ち) |
| C68 | 必須 | `Cmd+N` は一覧での新規プロジェクト作成、visible 24 未満なら visible・24 なら hidden、種別は Core(検証: C107 + C108) | unmet | - (周回 52 で上限 24 を実装し C107 は met。周回 53 の実機で、一覧内の Cmd+N でカーソルが新しい行へ移らない不具合を見つけて直した。C108 は人間の確認待ち) |
| C69 | 必須 | 一覧の `Cmd+Enter` で focus(hidden 行は近傍 visible へ)(検証: C107 + C108) | unmet | - (C107 は周回 52 で met。C108 は人間の確認待ち) |
| C70 | 必須 | 一覧の判断ロジック(端末・種別の候補を含む)はモデル層(検証: C107) | met | cycle 53: just swift-test exit 0 (C107 は met) |
| C71 | 必須 | 次トリガー 4 値(チームメンバーは外部へ移行)(検証: C107・C111 + C112) | unmet | - (C107 は改訂で未達、C112 は周回 50 で失効) |
| C72 | 必須 | 毎日 6:00 境界で全プロジェクトの優先度を未設定へ(検証: C109 + C110) | unmet | - (C110 が周回 50 の対象ファイル変更で失効) |
| C73 | 必須 | 最終リセット日付を永続化し作業日ごとに 1 回(検証: C109 + C110) | unmet | - (C110 が周回 50 の対象ファイル変更で失効) |
| C74 | 必須 | 自動リセットの並びはソート状態に従う(検証: C109) | met | cycle 53: just swift-test exit 0 (C109 は met) |
| C75 | 必須 | リセット判定はモデル層(検証: C109) | met | cycle 53: just swift-test exit 0 (C109 は met) |
| C76 | 必須 | SPEC.md / README.md を端末登録・tmux セッション・OSC 7 検出の廃止〜閉じた surface の解放・種別と重み付きレイアウト・台座型の廃止・上限 24・序数の配置順までの仕様に合わせる(検証: 周回の読み合わせ) | met | cycle 53: grep -c "project-terminal\|ProjectKind\|maxVisibleProjects\|set_occlusion\|ProjectListTitleSeat\|OSC 7" SPEC.md exit 0 (該当 16 行。上限 9 の語の grep と「フォーカスは一覧に残る」の grep は 0 件。§27.4 に ProjectListTitleSeat を足し、§27.6 の ProjectListCellTests を 30 件へ更新した。§7.3・§26・§27.8 の読み合わせは周回 52 から当該箇所の変更なし) |
| C77 | 必須 | 締切セルの Enter で 10 択の日付候補(検証: C107 + C108) | unmet | - (C107 は周回 52 で met。C108 は人間の確認待ち) |
| C78 | 必須 | 一覧テキスト列のセル編集が日本語 IME を受け付ける(検証: C114) | unmet | - (C114 が周回 50 の対象ファイル変更で失効) |
| C79 | 必須 | セルカーソルの Delete で列ごとの値削除(端末は手元へ・種別は Core へ)(検証: C107 + C108) | unmet | - (種別の Delete は周回 50 で実装。C107 は周回 52 で met。C108 は人間の確認待ち) |
| C80 | 必須 | Esc で行選択、行選択の Delete で確認付き削除(検証: C107 + C108) | unmet | - (C107 は周回 52 で met。C108 は人間の確認待ち) |
| C81 | 必須 | `Cmd+/` でショートカット一覧をトグル(検証: C115) | unmet | - (C115 が周回 50 の対象ファイル変更で失効) |
| C82 | 必須 | `Cmd+K` の clear_screen 既定割り当て解除(検証: C113) | unmet | - (C113 が周回 50 の対象ファイル変更で失効) |
| C83 | 必須 | 一覧セルのクリップボード操作(端末列は登録名のみ、種別列は Core / Side のみ)と候補列挙中の Tab 横移動(検証: C107 + C108) | unmet | - (種別の貼り付けは周回 50 で実装。C107 は周回 52 で met。C108 は人間の確認待ち) |
| C84 | 必須 | 描画対象の定義(全体ビュー: visible のプライマリー / zoom: 対象の全ペイン)(検証: C116) | met | cycle 53: just swift-test exit 0 (ProjectRenderTargetTests passed、failed 0 件) |
| C85 | 必須 | 描画対象外は生成時を含めレンダラとディスプレイリンクを停止し復帰時に再開(検証: C116 + C117) | unmet | - (C117 が周回 50 の対象ファイル変更で失効) |
| C86 | 必須 | 閉じた surface を経路によらず undo 期限後に SurfaceView〜IOSurface まで解放(検証: C116・C126 + C123〜C125 の読み合わせ + C117) | unmet | - (C117 が周回 50 の対象ファイル変更で失効) |
| C87 | 必須 | 描画対象の判定と停止・再開集合の導出はモデル層(検証: C116) | met | cycle 53: just swift-test exit 0 (ProjectRenderTargetTests passed) |
| C88 | 必須 | `zig build` が exit 0 | met | cycle 53: PATH=/opt/homebrew/opt/zig@0.15/bin:$PATH zig build exit 0 (Xcode 27.2 で確認) |
| C89 | 必須 | `just test` が exit 0 | met | cycle 53: just test exit 0 |
| C90 | 必須 | `just swift-test` が exit 0 | met | cycle 53: just swift-test exit 0 (failed 0 件、TEST SUCCEEDED) |
| C91 | 必須 | ノートのテスト群が macos/Tests/ に存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 53: just swift-test exit 0 (項目とテストの対応は cycle 8 の記録どおり、ProjectNoteTests は削除・変更なしで passed) |
| C92 | 必須 | ノートの実機目視(検証: 人間) | unmet | - (周回 50 で対象ファイルを変えたので失効。前回は 2026-10-30T16:21:09Z に合格) |
| C93 | 必須 | プライマリーペインのテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 53: just swift-test exit 0 (項目とテストの対応は cycle 9 の記録どおり、ProjectPrimaryPaneTests 35 件 passed) |
| C94 | 必須 | プライマリーペインの実機目視(検証: 人間) | unmet | - (周回 50 で対象ファイルを変えたので失効。前回は 2026-10-30T16:21:09Z に合格) |
| C95 | 必須 | 削除保護のテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 53: just swift-test exit 0 (項目とテストの対応は cycle 6 の記録どおり、ProjectTerminatedTests 18 件 passed) |
| C96 | 必須 | 削除保護の実機目視(検証: 人間) | unmet | - (周回 50 で対象ファイルを変えたので失効。前回は 2026-10-30T16:21:09Z に合格) |
| C97 | 必須 | ノート編集オーバーレイの編集ショートカット・100 行超過確認の実機目視(検証: 人間) | unmet | - (周回 50 で対象ファイルを変えたので失効。前回は 2026-10-30T16:21:09Z に合格) |
| C98 | 必須 | 優先度・締切のテスト群(ソート後の序数は C41 の配置順)が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 53: just swift-test exit 0 (既存の項目は従来どおり ProjectPriorityDeadlineTests で passed。ソート後の序数は ordinalsAfterASortFollowThePlacementOrder が passed) |
| C99 | 必須 | 優先度・締切の実機目視(検証: 人間) | unmet | - (周回 50 で対象ファイルを変えたので失効。前回は 2026-10-30T16:21:09Z に合格) |
| C100 | 必須 | hide のテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 53: just swift-test exit 0 (項目とテストの対応は cycle 5 の記録どおり passed) |
| C101 | 必須 | hide の実機目視(検証: 人間) | unmet | - (周回 50 で対象ファイルを変えたので失効。前回は 2026-10-30T16:21:09Z に合格) |
| C102 | 必須 | レイアウト型のテスト群(1〜24・重み・Core → Side・台座型の移行・種別変化での再導出)が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 53: just swift-test exit 0 (ProjectLayoutTypeTests 31 件 passed。項目 1: tierCountsAttachTheLeftoverToTheTrailingTiers・wideSlotsMatchTheDefinitionForEveryCount・tallIsTheExactTransposeOfWide・weightsHoldInEveryTierForEveryCountAndMix・theTreeRealizesTheSlotFramesForEveryTypeCountAndMix。項目 2: choiceSetsCollapseExactMatchesPerCount・choiceSetsMatchTheSlotFrameCollapseForEveryCount。項目 3: rowMajorAssignsTopRowLeftToRight・columnMajorAssignsLeftColumnTopToBottom・coreComesBeforeSideEachKindInRowOrder・theSlotsAssignCoreThenSideFollowingTheOrientation。項目 4: ProjectLedgerTests の 2 件・aSavedPedestalReadsAsWideKeepingItsOrientation・aWorkspaceSavedOnPedestalComesBackWideWithItsOrientation。項目 5: visibleCountChangesReapplyTheRememberedType・countPreservingOperationsDoNotChangeTheArrangement・aVisibleKindChangeReappliesTheRememberedType) |
| C103 | 必須 | レイアウト型の実機目視(検証: 人間) | unmet | - (周回 50 で対象ファイルを変えたので失効。前回は 2026-10-30T16:21:09Z に合格) |
| C104 | 必須 | 改名完了: Projects/ が在り Groups/ が無い、C88〜C90 exit 0、可視文言に Group が無いことの目視(検証: test -d / test -e + C88〜C90 + 人間) | met | cycle 53: test -d macos/Sources/Features/Projects exit 0 (test -e macos/Sources/Features/Groups は exit 1、C88〜C90 は周回 53 で exit 0。補足: 可視文言の目視は 2026-10-28T14:21:46Z の人間の確認でメニューに Group なし。周回 50 で足した可視文言は列見出し「kind」・値「Core」「Side」・ヒント「↩ lists kinds」で Group を含まず、周回 51・52 は可視文言を足していない) |
| C107 | 必須 | プロジェクト一覧のテスト群(既定列順 8 列、端末・種別の候補・Delete・貼り付け、visible 24 の拒否を含む)が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 53: just swift-test exit 0 (failed 0 件。既存の項目は従来どおり ProjectListTests ほかで passed。序数: onlyTheFirstNineInPlacementOrderHaveANumber・aHiddenRowFreesItsNumberForTheNextProject・coreComesBeforeSideEachKindInRowOrder。新規行: aNewRowIsVisibleCoreWhileBelowTheCap・aNewRowIsHiddenCoreAtTheCap。種別: aProjectIsCoreByDefault・theKindPersistsAndRestores・aSaveWithoutAKnownKindRestoresAsCore・theKindIsNotASortKey・theCandidatesAreCoreThenSide・deleteReturnsTheKindToCore。visible 24 の拒否: theToggleIsRejectedWithTwentyFourVisible) |
| C108 | 必須 | プロジェクト一覧の実機目視(検証: 人間) | unmet | - (周回 50 で対象ファイルを変えたので失効。前回は 2026-10-30T16:21:09Z に合格) |
| C109 | 必須 | 優先度リセットのテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 53: just swift-test exit 0 (項目とテストの対応は cycle 5 の記録どおり passed) |
| C110 | 必須 | 優先度リセットの実機目視(検証: 人間) | unmet | - (周回 50 で対象ファイルを変えたので失効。前回は 2026-10-30T16:21:09Z に人間の判断で合格) |
| C111 | 必須 | 次トリガーのテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 53: just swift-test exit 0 (項目とテストの対応は cycle 5 の記録どおり passed) |
| C112 | 必須 | 次トリガーの実機目視(検証: 人間) | unmet | - (周回 50 で対象ファイルを変えたので失効。前回は 2026-10-30T16:21:09Z に合格) |
| C113 | 必須 | キー変更の実機目視(検証: 人間) | unmet | - (周回 50 で対象ファイルを変えたので失効。前回は 2026-10-30T16:21:09Z に合格) |
| C114 | 必須 | 一覧セル編集の IME の実機目視(検証: 人間) | unmet | - (周回 50 で対象ファイルを変えたので失効。前回は 2026-10-30T16:21:09Z に合格) |
| C115 | 必須 | ショートカット一覧の実機目視(検証: 人間) | unmet | - (周回 50 で対象ファイルを変えたので失効。前回は 2026-10-30T16:21:09Z に合格) |
| C116 | 必須 | 描画対象・停止/再開集合・解放・誕生時停止のテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 53: just swift-test exit 0 (ProjectRenderTargetTests 21 件 passed。全 5 項目の対応は cycle 2・3 の記録どおり) |
| C117 | 必須 | 描画停止・解放の実機観測(top / footprint、起動直後に落ちない、行 Delete 後のフォーカス、検証: 人間) | unmet | - (周回 50 で対象ファイルを変えたので失効。前回は 2026-10-30T16:21:09Z に合格) |
| C121 | 必須 | 停止集合に誕生した描画対象外の surface を含める(stop = (after.retained − after.drawn) ∩ (before.drawn ∪ born))(検証: C116) | met | cycle 53: just swift-test exit 0 (ProjectRenderTargetTests 21 件 passed) |
| C122 | 必須 | 停止・再開の適用は RenderTargetTransition のみ(生成直後の一律 set_occlusion(false) が唯一の例外)、SurfaceView.isDrawing を持たない(検証: C116 + 読み合わせ) | met | cycle 53: just swift-test exit 0 (C116 passed。grep -rn xghostty_surface_set_occlusion macos/Sources は 2 箇所(SurfaceView_AppKit.swift:383 の init 直後の一律停止と BaseTerminalController.swift:2506 の syncRenderTargetOcclusion)、grep -rn isDrawing macos/Sources は 0 件。周回 53 で取り直した) |
| C123 | 必須 | SurfaceView の `.ghosttySelectionDidChange` 購読は `object:` を渡さず `[weak self]` の filter で絞る(検証: 読み合わせ + C90) | met | cycle 53: just swift-test exit 0 (SurfaceView_AppKit.swift:295 の publisher(for: .ghosttySelectionDidChange) に object: が無く、296 行の [weak self] の filter で絞ることを周回 53 で読み合わせた) |
| C124 | 必須 | `XGhostty.Surface.deinit` はメインスレッドなら同期的に `xghostty_surface_free`(検証: 読み合わせ + C88〜C90 + C117) | unmet | - (C117 が周回 50 の対象ファイル変更で失効。読み合わせと C88〜C90 は周回 50 で確認済み) |
| C125 | 必須 | 一覧の行選択 Delete で閉じたとき新しい focus 先へキーボードフォーカスを移す(検証: C126 + 読み合わせ + C117) | unmet | - (C117 が周回 50 の対象ファイル変更で失効) |
| C126 | 必須 | 一覧セッション中の closeProject の focus 先・保持集合・セッション継続のテスト(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 53: just swift-test exit 0 (ProjectListRowSelectionTests の 2 件が passed) |
| C127 | 必須 | 端末を設定ファイルに登録(表示名・ホスト・色)、hostname 一致を手元、登録なしは暗黙の手元、再読み込みで反映(検証: C136 + C137) | unmet | - (C137 が周回 50 の対象ファイル変更で失効) |
| C128 | 必須 | プロジェクトの端末(既定は手元)、一覧の端末列で候補選択・Delete で手元・登録名のみ貼り付け、永続化、欠落は手元扱い、変更は以後の新しいペインだけに効き終了済みの再開は元の端末の同じセッションへ(検証: C136 + C137) | unmet | - (C137 が周回 50 の対象ファイル変更で失効) |
| C129 | 必須 | 全ペインを端末上の tmux セッションへ attach するコマンドで起動、セッション名 `<ID>-<n>`、ペインごとの端末・セッション名を永続化(検証: C136 + C137) | unmet | - (C137 が周回 50 の対象ファイル変更で失効) |
| C130 | 必須 | 開始ディレクトリ `~/workspace/<タイトル>` → `~/workspace` → ホーム、split は `#{pane_current_path}` を引き継ぐ(検証: C136 + C137) | unmet | - (C137 が周回 50 の対象ファイル変更で失効) |
| C131 | 必須 | attach 時にそのセッションだけへ status-style・status-left・prefix C-s を設定、リネームで status-left を更新(検証: C136 + C137) | unmet | - (C137 が周回 50 の対象ファイル変更で失効) |
| C132 | 必須 | tmux / ssh の終了でペインは終了済み、Enter で同じ attach を再実行(検証: C136 + C137) | unmet | - (C137 が周回 50 の対象ファイル変更で失効) |
| C133 | 必須 | 閉じたペインのセッションを undo 期限後に kill、undo で戻せば kill しない(検証: C136 + C137) | unmet | - (C137 が周回 50 の対象ファイル変更で失効) |
| C134 | 必須 | 手元でない端末への ssh に TERM=xterm-256color を渡す(検証: C136 + C137) | unmet | - (C137 が周回 50 の対象ファイル変更で失効) |
| C135 | 必須 | 端末・セッション・コマンド・候補・kill 対象の判断ロジックはモデル層(検証: C136) | met | cycle 53: just swift-test exit 0 (C136 は met。配置は周回 43 の記録どおりで、周回 50 の差分は端末の判断に触れていない) |
| C136 | 必須 | 端末登録と tmux セッションのテスト群(9 項目)が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 53: just swift-test exit 0 (failed 0 件。項目とテストの対応は cycle 39 の台帳どおり。ProjectTerminalColumnTests は既定列順の期待値だけを 8 列へ更新した) |
| C137 | 必須 | 端末登録と tmux セッションの実機観測(Mac mini、ssh ループバック、screencapture と tmux の出力)(検証: 周回の実機観測) | unmet | - (周回 50 で対象ファイルを変えたので observed 44 は失効。全実装の後に取り直す) |
| C138 | 必須 | 2 台の実機での目視(Mac mini の tmux・再起動後の再 attach・切断後の再 attach)(検証: 人間) | unmet | - (2026-10-30T16:21:09Z の刻印で「後日行う」とされ未確認のまま) |
| C139 | 必須 | 種別と重み付きレイアウトの実機観測(8 列・候補・重みの幅と高さ・Core → Side の序数・種別変更で組み直し・台座型なし・24 と 25 個目の hidden・Side に印なし)(検証: 周回の実機観測) | unmet | - (周回 53 に修正前の HEAD で全 7 項目を観測し、期待どおりだった。ただし同じ周回で対象ファイルを変えたので出典にならない。次の周回の冒頭で取り直す) |
| C140 | 必須 | 種別 Core / Side、既定 Core、一覧の種別列(候補 Core → Side・Delete で Core・Core / Side のみ貼り付け)、永続化、ソートキーにしない、大きさ以外に差を付けない(検証: C107 + C139) | unmet | - (モデル・列・保存は周回 50、全体ビューの大きさは周回 51 で実装し、C107 は周回 52 で met。C139 は実機観測待ち) |
| C141 | 必須 | 同時 visible は最大 24、24 で表示トグルを拒否、序数は配置順の先頭 9 つ(検証: C107 + C139) | unmet | - (周回 52 で実装し C107 は met。C139 は実機観測待ち) |
| C118 | 望ましい | マウスからノートを開く導線(検証: 人間) | unmet | - |
| C119 | 望ましい | ノート UI・プライマリー印の見た目の洗練(検証: 人間) | unmet | - |
| C120 | 望ましい | 全体ビューの非プライマリーペインのインジケータ(検証: 人間) | unmet | - |
