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

ideal_sha: 9f6dbfad54c29fb998d241a1a930cfc584a6ec7366d2cfb32898d228edc3a5f9

| ID | 階層 | 条件 | 状態 | 証拠 |
|----|------|------|------|------|
| C1 | 必須 | プロジェクトごとに手書きの短いノートを保持できる(検証: C91) | met | cycle 27: just swift-test exit 0 (検証は C91 のテスト成功のみ。C91 は met、failed 0 件) |
| C2 | 必須 | ノート最大 100 行、保存時超過は確認し OK で先頭 100 行へ切詰め・Cancel で編集へ戻る(検証: C91 + C97) | met | cycle 27: just swift-test exit 0 (C91 met。C97 は 2026-10-28T14:21:46Z の人間確認で met) |
| C3 | 必須 | ノートは永続化され再起動後に同じプロジェクトへ復元(検証: C91) | met | cycle 27: just swift-test exit 0 (検証は C91 のテスト成功のみ。C91 は met、failed 0 件) |
| C4 | 必須 | ノートはプロジェクトに属しペインに属さない(検証: C91) | met | cycle 27: just swift-test exit 0 (検証は C91 のテスト成功のみ。C91 は met、failed 0 件) |
| C5 | 必須 | `Cmd+E` でノート編集オーバーレイ、`Cmd+Enter` で保存して閉じる(検証: C91 + C92) | met | cycle 27: just swift-test exit 0 (C91 met。C92 は 2026-10-28T14:21:46Z の人間確認で met) |
| C6 | 必須 | オーバーレイで Esc は確認なしに破棄して閉じる(検証: C91 + C92) | met | cycle 27: just swift-test exit 0 (C91 met。C92 は 2026-10-28T14:21:46Z の人間確認で met) |
| C7 | 必須 | `Cmd+Enter` の fullscreen 既定割り当てを解除(検証: C92) | met | cycle 27: just swift-test exit 0 (検証は C92 の確認のみ。C92 は 2026-10-28T14:21:46Z の人間確認で met) |
| C8 | 必須 | `Cmd+Opt+E` で一望モードをトグル、Esc でも抜ける(検証: C92) | met | cycle 27: just swift-test exit 0 (検証は C92 の確認のみ。C92 は 2026-10-28T14:21:46Z の人間確認で met) |
| C9 | 必須 | 一望モードは visible なプロジェクトのみ表示(検証: C91) | met | cycle 27: just swift-test exit 0 (検証は C91 のテスト成功のみ。C91 は met、failed 0 件) |
| C10 | 必須 | zoom 中に一望モードへ入ると zoom 解除(検証: C91) | met | cycle 27: just swift-test exit 0 (検証は C91 のテスト成功のみ。C91 は met、failed 0 件) |
| C11 | 必須 | 一望モードは閲覧専用で編集・focus 移動しない(検証: C91) | met | cycle 27: just swift-test exit 0 (検証は C91 のテスト成功のみ。C91 は met、failed 0 件) |
| C12 | 必須 | 一望モードで収まらないノートは切詰め、編集オーバーレイはスクロールで全文(検証: C92) | met | cycle 27: just swift-test exit 0 (検証は C92 の確認のみ。C92 は 2026-10-28T14:21:46Z の人間確認で met) |
| C13 | 必須 | ノート UI は端末領域を恒久占有しない(検証: C92) | met | cycle 27: just swift-test exit 0 (検証は C92 の確認のみ。C92 は 2026-10-28T14:21:46Z の人間確認で met) |
| C14 | 必須 | 既存機能と上流動作を退行させない(列挙した意図的変更を除く。C123〜C125 を例外に追加)(検証: C88〜C90 exit 0 かつ既存テストが削除・無効化されず成功) | met | cycle 27: just swift-test exit 0 (zig build・just test も exit 0。周回 25 以降 .idd 以外の変更は無く、テストの削除・無効化は無い(周回 25 の git diff -M 9cb808d 検査のまま)。passed 701 行・failed 0 件) |
| C15 | 必須 | ノートの判断ロジックはモデル層で XGhosttyTests から検証可能(検証: C91) | met | cycle 27: just swift-test exit 0 (検証は C91 のテスト成功のみ。C91 は met、failed 0 件) |
| C16 | 必須 | SPEC.md / README.md をノート層仕様に合わせ、README の Building 節に 3 検証コマンド(検証: 周回の読み合わせ) | met | cycle 25: grep -n "Building" -A12 README.md exit 0 (zig build / just test / just swift-test の 3 行を確認。SPEC §21 と README の Notes 項は cycle 12 の読み合わせ以降、ノート層の実装変更が無い) |
| C17 | 必須 | 各ペインはプライマリーフラグを持ち最初のペインがプライマリー(検証: C93) | met | cycle 27: just swift-test exit 0 (検証は C93 のテスト成功のみ。C93 は met、failed 0 件) |
| C18 | 必須 | プライマリーはプロジェクト内で常に 1 つ(検証: C93) | met | cycle 27: just swift-test exit 0 (検証は C93 のテスト成功のみ。C93 は met、failed 0 件) |
| C19 | 必須 | 全体ビューはプライマリーのみ描画、zoom 中は全ペイン(検証: C93 + C94) | met | cycle 27: just swift-test exit 0 (C93 met。C94 は 2026-10-28T14:21:46Z の人間確認で met) |
| C20 | 必須 | 全体ビューの入力・focus はプライマリーへ、zoom 解除時に寄せる(検証: C93) | met | cycle 27: just swift-test exit 0 (検証は C93 のテスト成功のみ。C93 は met、failed 0 件) |
| C21 | 必須 | 全体ビューでペイン系操作は no-op(検証: C93) | met | cycle 27: just swift-test exit 0 (検証は C93 のテスト成功のみ。C93 は met、failed 0 件) |
| C22 | 必須 | zoom 中 `Cmd+P` で focused ペインをプライマリーへ(検証: C93 + C94) | met | cycle 27: just swift-test exit 0 (C93 met。C94 は 2026-10-28T14:21:46Z の人間確認で met) |
| C23 | 必須 | プライマリーが閉じたら最近傍 leaf を昇格(検証: C93 + C94) | met | cycle 27: just swift-test exit 0 (C93 met。C94 は 2026-10-28T14:21:46Z の人間確認で met) |
| C24 | 必須 | プライマリーフラグの永続化と復元時正規化(検証: C93) | met | cycle 27: just swift-test exit 0 (検証は C93 のテスト成功のみ。C93 は met、failed 0 件) |
| C25 | 必須 | プライマリー印は zoom 中かつ複数ペイン時のみ右上に表示(検証: C94) | met | cycle 27: just swift-test exit 0 (検証は C94 の確認のみ。C94 は 2026-10-28T14:21:46Z の人間確認で met) |
| C26 | 必須 | プライマリーの判断ロジックはモデル層(検証: C93) | met | cycle 27: just swift-test exit 0 (検証は C93 のテスト成功のみ。C93 は met、failed 0 件) |
| C27 | 必須 | SPEC.md / README.md をプライマリーペイン層仕様に合わせる(検証: 周回の読み合わせ) | met | cycle 25: grep -c "@Test" macos/Tests/Projects/ProjectPrimaryPaneTests.swift exit 0 (35 件で SPEC §22.8 と一致。§22 の読み合わせは cycle 13、以降プライマリー層の実装変更は無い) |
| C28 | 必須 | プロジェクトを閉じる操作は常に確認ダイアログ(検証: C95 + C96) | met | cycle 27: just swift-test exit 0 (C95 met。C96 は 2026-10-28T14:21:46Z の人間確認で met) |
| C29 | 必須 | 最後のペインのシェル exit でプロジェクトを閉じず終了済みで残す(検証: C95 + C96) | met | cycle 27: just swift-test exit 0 (C95 met。C96 は 2026-10-28T14:21:46Z の人間確認で met) |
| C30 | 必須 | 終了済みペインで Enter により新シェルで再開(検証: C96) | met | cycle 27: just swift-test exit 0 (検証は C96 の確認のみ。C96 は 2026-10-28T14:21:46Z の人間確認で met) |
| C31 | 必須 | プロジェクト喪失経路は確認を経た明示的 close のみ(検証: C95 + C96) | met | cycle 27: just swift-test exit 0 (C95 met。C96 は 2026-10-28T14:21:46Z の人間確認で met) |
| C32 | 必須 | ノート編集オーバーレイで標準編集ショートカットと Undo/Redo が効く(検証: C97) | met | cycle 27: just swift-test exit 0 (検証は C97 の確認のみ。C97 は 2026-10-28T14:21:46Z の人間確認で met) |
| C33 | 必須 | 貼り付けで 100 行超過も C2 の確認を経る(検証: C91 + C97) | met | cycle 27: just swift-test exit 0 (C91 met。C97 は 2026-10-28T14:21:46Z の人間確認で met) |
| C34 | 必須 | 優先度 high/medium/low/未設定(検証: C98 + C99) | met | cycle 27: just swift-test exit 0 (C98 met。C99 は 2026-10-28T14:21:46Z の人間確認で met) |
| C35 | 必須 | 締切(日付のみ)、不正入力は未設定(検証: C98 + C99) | met | cycle 27: just swift-test exit 0 (C98 met。C99 は 2026-10-28T14:21:46Z の人間確認で met) |
| C36 | 必須 | 優先度・締切は一覧セルで設定し永続化(検証: C98 + C99) | met | cycle 27: just swift-test exit 0 (C98 met。C99 は 2026-10-28T14:21:46Z の人間確認で met) |
| C37 | 必須 | ラベル帯に優先度の印と締切を表示(検証: C99) | met | cycle 27: just swift-test exit 0 (検証は C99 の確認のみ。C99 は 2026-10-28T14:21:46Z の人間確認で met) |
| C38 | 必須 | 一望モードでノートと優先度・締切・次トリガーを表示(検証: C111 + C99・C112) | met | cycle 27: just swift-test exit 0 (C111 met。C99・C112 は 2026-10-28T14:21:46Z の人間確認で met) |
| C39 | 必須 | 締切超過を控えめに強調(1 段階のみ)(検証: C98 + C99) | met | cycle 27: just swift-test exit 0 (C98 met。C99 は 2026-10-28T14:21:46Z の人間確認で met) |
| C40 | 必須 | ソートは 5 値の永続化される状態、既定は手動(検証: C107 + C108) | met | cycle 27: just swift-test exit 0 (C107 met。C108 は 2026-10-28T14:21:46Z の人間確認で met) |
| C41 | 必須 | 各ソートキーの固定の向き・安定ソート・序数は visible 行の表示順(検証: C98・C107) | met | cycle 27: just swift-test exit 0 (検証は C98・C107 のテスト成功のみ。C98・C107 は met、failed 0 件) |
| C42 | 必須 | 一覧最上部のソートバーをキーボード・マウスで操作(検証: C107 + C108) | met | cycle 27: just swift-test exit 0 (C107 met。C108 は 2026-10-28T14:21:46Z の人間確認で met) |
| C43 | 必須 | ソート有効中の即時再ソートと Opt+↑↓ の確認、ソートアクション廃止(検証: C107 + C108) | met | cycle 27: just swift-test exit 0 (C107 met。C108 は 2026-10-28T14:21:46Z の人間確認で met) |
| C44 | 必須 | 優先度・締切・次トリガー・終了済みの判断ロジックはモデル層(検証: C95・C98・C111) | met | cycle 27: just swift-test exit 0 (検証は C95・C98・C111 のテスト成功のみ。C95・C98・C111 は met、failed 0 件) |
| C45 | 必須 | SPEC.md / README.md を削除保護・ショートカット・優先度・締切層に合わせる(検証: 周回の読み合わせ) | met | cycle 25: grep -c "@Test" (ProjectTerminatedTests / ProjectPriorityDeadlineTests / ProjectSortStateTests / ProjectNextTriggerTests) exit 0 (16 / 18 / 13 / 7 件で SPEC §23.5・§24.5・§24.6 と一致。§23.1 の行選択 Delete の記述に cycle 19 で新しい focus 先へのフォーカス移動を足し、performCloseProjectListRow の実装と一致することを読み合わせた) |
| C46 | 必須 | `Cmd+Opt+H` で focused プロジェクトを即時 hidden(検証: C100 + C101) | met | cycle 27: just swift-test exit 0 (C100 met。C101 は 2026-10-28T14:21:46Z の人間確認で met) |
| C47 | 必須 | visible は最低 1 つ残る(検証: C100) | met | cycle 27: just swift-test exit 0 (検証は C100 のテスト成功のみ。C100 は met、failed 0 件) |
| C48 | 必須 | hidden の復帰導線は一覧のみ、hidden シェルフ廃止(検証: C107 + C108) | met | cycle 27: just swift-test exit 0 (C107 met。C108 は 2026-10-28T14:21:46Z の人間確認で met) |
| C49 | 必須 | レイアウト型 = 形 3 種 × 向き 2 種、余りは後半行へ(検証: C102 + C103) | met | cycle 27: just swift-test exit 0 (C102 met。C103 は 2026-10-28T14:21:46Z の人間確認で met) |
| C50 | 必須 | 完全一致する型を畳み、選択肢 1 つなら選ぶものが無い旨(検証: C102 + C103) | met | cycle 27: just swift-test exit 0 (C102 met。C103 は 2026-10-28T14:21:46Z の人間確認で met) |
| C51 | 必須 | `Cmd+Opt+L` でレイアウト型の選択オーバーレイ(検証: C103) | met | cycle 27: just swift-test exit 0 (検証は C103 の確認のみ。C103 は 2026-10-28T14:21:46Z の人間確認で met) |
| C52 | 必須 | レイアウト型は永続化、既定は横長型・行送り(検証: C102 + C103) | met | cycle 27: just swift-test exit 0 (C102 met。C103 は 2026-10-28T14:21:46Z の人間確認で met) |
| C53 | 必須 | 表示順のまま向きに従いスロットへ割当、序数が追従(検証: C102) | met | cycle 27: just swift-test exit 0 (検証は C102 のテスト成功のみ。C102 は met、failed 0 件) |
| C54 | 必須 | visible 数変化時に記憶の型で自動適用(検証: C102 + C101・C103) | met | cycle 27: just swift-test exit 0 (C102 met。C101・C103 は 2026-10-28T14:21:46Z の人間確認で met) |
| C55 | 必須 | プロジェクト単位のレイアウト resize/equalize 廃止、zoom 中ペインは存続(検証: C103) | met | cycle 27: just swift-test exit 0 (検証は C103 の確認のみ。C103 は 2026-10-28T14:21:46Z の人間確認で met) |
| C56 | 必須 | レイアウト型の判断ロジックはモデル層(検証: C102) | met | cycle 27: just swift-test exit 0 (検証は C102 のテスト成功のみ。C102 は met、failed 0 件) |
| C57 | 必須 | 「グループ」→「プロジェクト」全面改名(検証: C104) | met | cycle 27: test -d macos/Sources/Features/Projects exit 0 (test -e macos/Sources/Features/Groups は exit 1。C104 は周回 27 で取り直して met) |
| C58 | 必須 | 改名は純粋なリネームで退行なし(検証: C104 + C88〜C90) | met | cycle 27: just swift-test exit 0 (zig build・just test も exit 0。C104 は周回 27 で取り直して met) |
| C59 | 必須 | SPEC.md / README.md をレイアウト型・自動適用・hide・改名語彙に合わせる(検証: 周回の読み合わせ) | met | cycle 25: grep -c "@Test" macos/Tests/Projects/ProjectLayoutTypeTests.swift macos/Tests/Projects/ProjectLayoutSelectionTests.swift exit 0 (14 / 10 件で SPEC §26.5 と一致。test -d Projects exit 0・test -e Groups exit 1。§25・§26・§12 の読み合わせは cycle 15、以降当該層の実装変更は無い) |
| C60 | 必須 | リモートペインの split は同ホスト・同パスへ ssh(検証: C105 のテスト成功のみ。実機確認は望ましい C106) | met | cycle 27: just swift-test exit 0 (ProjectRemoteSplitTests passed、failed 0 件。fdfd8fe で検証が C105 のみに変わった) |
| C61 | 必須 | リモート判定不能・接続失敗はローカルで開く(検証: C105 のテスト成功のみ。実機確認は望ましい C106) | met | cycle 27: just swift-test exit 0 (ProjectRemoteSplitTests passed、failed 0 件。fdfd8fe で検証が C105 のみに変わった) |
| C62 | 必須 | リモート判定はモデル層(検証: C105) | met | cycle 27: just swift-test exit 0 (検証は C105 のテスト成功のみ。C105 は met、failed 0 件) |
| C63 | 必須 | `Cmd+L` で一覧をトグル(Esc で閉じない・zoom を解除しない・6 列・8 割)(検証: C107 + C108) | met | cycle 27: just swift-test exit 0 (C107 met。C108 は 2026-10-28T14:21:46Z の人間確認で met) |
| C64 | 必須 | 一覧は単一の並び、手動順・列順・ソート状態を永続化、hidden も同色(検証: C107 + C108) | met | cycle 27: just swift-test exit 0 (C107 met。C108 は 2026-10-28T14:21:46Z の人間確認で met) |
| C65 | 必須 | Notion 流儀のセルカーソル・Enter 編集・候補列挙(検証: C107 + C108) | met | cycle 27: just swift-test exit 0 (C107 met。C108 は 2026-10-28T14:21:46Z の人間確認で met) |
| C66 | 必須 | ノート列編集は全行対象、Shift+Enter で改行、一覧内 `Cmd+Opt+E` は全行表示トグル(検証: C107 + C108) | met | cycle 27: just swift-test exit 0 (C107 met。C108 は 2026-10-28T14:21:46Z の人間確認で met) |
| C67 | 必須 | `Cmd+矢印` は端移動、`Opt+矢印` で行・列並べ替え(検証: C107 + C108) | met | cycle 27: just swift-test exit 0 (C107 met。C108 は 2026-10-28T14:21:46Z の人間確認で met) |
| C68 | 必須 | `Cmd+N` は一覧での新規プロジェクト作成(検証: C107 + C108) | met | cycle 27: just swift-test exit 0 (C107 met。C108 は 2026-10-28T14:21:46Z の人間確認で met) |
| C69 | 必須 | 一覧の `Cmd+Enter` で focus(hidden 行は近傍 visible へ)(検証: C107 + C108) | met | cycle 27: just swift-test exit 0 (C107 met。C108 は 2026-10-28T14:21:46Z の人間確認で met) |
| C70 | 必須 | 一覧の判断ロジックはモデル層(検証: C107) | met | cycle 27: just swift-test exit 0 (検証は C107 のテスト成功のみ。C107 は met、failed 0 件) |
| C71 | 必須 | 次トリガー 4 値(チームメンバーは外部へ移行)(検証: C107・C111 + C112) | met | cycle 27: just swift-test exit 0 (C107・C111 met。C112 は 2026-10-28T14:21:46Z の人間確認で met) |
| C72 | 必須 | 毎日 6:00 境界で全プロジェクトの優先度を未設定へ(検証: C109 + C110) | met | cycle 27: just swift-test exit 0 (C109 met。C110 は 2026-10-28T14:40:29Z の人間の判断で met) |
| C73 | 必須 | 最終リセット日付を永続化し作業日ごとに 1 回(検証: C109 + C110) | met | cycle 27: just swift-test exit 0 (C109 met。C110 は 2026-10-28T14:40:29Z の人間の判断で met) |
| C74 | 必須 | 自動リセットの並びはソート状態に従う(検証: C109) | met | cycle 27: just swift-test exit 0 (検証は C109 のテスト成功のみ。C109 は met、failed 0 件) |
| C75 | 必須 | リセット判定はモデル層(検証: C109) | met | cycle 27: just swift-test exit 0 (検証は C109 のテスト成功のみ。C109 は met、failed 0 件) |
| C76 | 必須 | SPEC.md / README.md をリモート split〜描画停止・閉じた surface の解放(循環参照・同期解放・undo 期限後の解放・行 Delete のフォーカス移動)までの仕様に合わせる(検証: 周回の読み合わせ) | met | cycle 25: grep -c "@Test" macos/Tests/Projects/ProjectListRowSelectionTests.swift exit 0 (11 件で SPEC §27.6 と一致、ProjectRenderTargetTests 21 件で §31.5 と一致。周回 25 で SPEC §31.4 のポインタ追跡の取り直し、§7.1 の inline rename 終了時のフォーカス返却、README の描画停止の項を実装と読み合わせた。周回 24 で §31.2・§31.3 の生成直後の一律停止、cycle 21 で §27.2・§27.3、cycle 19 で §31.4・§23.1・§27.2・§27.6 を読み合わせた。周回 25 以降、実装と SPEC/README は変わっていない) |
| C77 | 必須 | 締切セルの Enter で 10 択の日付候補(検証: C107 + C108) | met | cycle 27: just swift-test exit 0 (C107 met。C108 は 2026-10-28T14:21:46Z の人間確認で met) |
| C78 | 必須 | 一覧テキスト列のセル編集が日本語 IME を受け付ける(検証: C114) | met | cycle 27: just swift-test exit 0 (検証は C114 の確認のみ。C114 は 2026-10-28T14:40:29Z の人間確認で met) |
| C79 | 必須 | セルカーソルの Delete で列ごとの値削除(検証: C107 + C108) | met | cycle 27: just swift-test exit 0 (C107 met。C108 は 2026-10-28T14:21:46Z の人間確認で met) |
| C80 | 必須 | Esc で行選択、行選択の Delete で確認付き削除(検証: C107 + C108) | met | cycle 27: just swift-test exit 0 (C107 met。C108 は 2026-10-28T14:21:46Z の人間確認で met) |
| C81 | 必須 | `Cmd+/` でショートカット一覧をトグル(検証: C115) | met | cycle 27: just swift-test exit 0 (検証は C115 の確認のみ。C115 は 2026-10-28T14:21:46Z の人間確認で met) |
| C82 | 必須 | `Cmd+K` の clear_screen 既定割り当て解除(検証: C113) | met | cycle 27: just swift-test exit 0 (検証は C113 の確認のみ。C113 は 2026-10-28T14:21:46Z の人間確認で met) |
| C83 | 必須 | 一覧セルのクリップボード操作と候補列挙中の Tab 横移動(検証: C107 + C108) | met | cycle 27: just swift-test exit 0 (C107 met。C108 は 2026-10-28T14:21:46Z の人間確認で met) |
| C84 | 必須 | 描画対象の定義(全体ビュー: visible のプライマリー / zoom: 対象の全ペイン)(検証: C116) | met | cycle 27: just swift-test exit 0 (ProjectRenderTargetTests passed、failed 0 件) |
| C85 | 必須 | 描画対象外は生成時を含めレンダラとディスプレイリンクを停止し復帰時に再開(検証: C116 + C117) | met | cycle 27: just swift-test exit 0 (C116 met。C117 は 2026-10-28T14:21:46Z の人間確認で met: (1) Release 0.6〜0.7%、(6) IOSurface 24 MB 対 24 MB) |
| C86 | 必須 | 閉じた surface を経路によらず undo 期限後に SurfaceView〜IOSurface まで解放(検証: C116・C126 + C123〜C125 の読み合わせ + C117) | met | cycle 27: just swift-test exit 0 (C116・C126 met。C123〜C125 の読み合わせは周回 26 で取り直した。C117 は 2026-10-28T14:21:46Z の人間確認で met: 行 Delete(visible・非フォーカス・マウス静止)で閉じ 65 秒後にスレッド・IOSurface が戻る) |
| C87 | 必須 | 描画対象の判定と停止・再開集合の導出はモデル層(検証: C116) | met | cycle 27: just swift-test exit 0 (ProjectRenderTargetTests passed、failed 0 件) |
| C88 | 必須 | `zig build` が exit 0 | met | cycle 27: PATH=/opt/homebrew/opt/zig@0.15/bin:$PATH zig build exit 0 |
| C89 | 必須 | `just test` が exit 0 | met | cycle 27: just test exit 0 |
| C90 | 必須 | `just swift-test` が exit 0 | met | cycle 27: just swift-test exit 0 |
| C91 | 必須 | ノートのテスト群が macos/Tests/ に存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 27: just swift-test exit 0 (項目とテストの対応は cycle 8 の記録どおり、ProjectNoteTests は削除・変更なしで passed) |
| C92 | 必須 | ノートの実機目視(検証: 人間) | met | human 2026-10-28T14:21:46Z: 第 3 回(HEAD 23df54f)で第 2 回の判定を再刻印。Cmd+E 編集→Cmd+Enter 保存、Esc 破棄、fullscreen にならない、Cmd+Opt+E 一望、切り詰め表示 |
| C93 | 必須 | プライマリーペインのテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 27: just swift-test exit 0 (項目とテストの対応は cycle 9 の記録どおり、ProjectPrimaryPaneTests 35 件は削除・変更なしで passed) |
| C94 | 必須 | プライマリーペインの実機目視(検証: 人間) | met | human 2026-10-28T14:21:46Z: 第 3 回で再刻印。全体ビューはプライマリーのみ、zoom で 2 ペインと右上の印、Cmd+P で付け替え、プライマリーの exit で昇格 |
| C95 | 必須 | 削除保護のテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 27: just swift-test exit 0 (項目とテストの対応は cycle 6 の記録どおり、ProjectTerminatedTests 16 件 passed) |
| C96 | 必須 | 削除保護の実機目視(検証: 人間) | met | human 2026-10-28T14:21:46Z: 第 3 回で再刻印。close で確認・Cancel で失われない、最終ペイン exit で終了済み、Enter で再開 |
| C97 | 必須 | ノート編集オーバーレイの編集ショートカット・100 行超過確認の実機目視(検証: 人間) | met | human 2026-10-28T14:21:46Z: 第 3 回で再刻印。Cmd+A/C/X/V/Z/Shift+Z、120 行貼り付けで確認、Cancel で編集へ、OK で 100 行に切り詰め |
| C98 | 必須 | 優先度・締切のテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 27: just swift-test exit 0 (項目とテストの対応は cycle 6 の記録どおり、ProjectPriorityDeadlineTests 18 件 passed) |
| C99 | 必須 | 優先度・締切の実機目視(検証: 人間) | met | human 2026-10-28T14:21:46Z: 第 3 回で再刻印。セルで設定、ラベル帯と一望に表示、超過が赤、deadline ソートと序数追従 |
| C100 | 必須 | hide のテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 27: just swift-test exit 0 (項目とテストの対応は cycle 5 の記録どおり passed) |
| C101 | 必須 | hide の実機目視(検証: 人間) | met | human 2026-10-28T14:21:46Z: 第 3 回で再刻印。Cmd+Opt+H で即隠れ、残りが記憶型で組み直し |
| C102 | 必須 | レイアウト型のテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 27: just swift-test exit 0 (項目とテストの対応は cycle 7 の記録どおり passed) |
| C103 | 必須 | レイアウト型の実機目視(検証: 人間) | met | human 2026-10-28T14:21:46Z: 第 3 回で再刻印。Cmd+Opt+L の型選択、自動適用、再起動後も型維持、選ぶものが無い表示、境界ドラッグ不可 |
| C104 | 必須 | 改名完了: Projects/ が在り Groups/ が無い、C88〜C90 exit 0、可視文言に Group が無いことの目視(検証: test -d / test -e + C88〜C90 + 人間) | met | cycle 27: test -d macos/Sources/Features/Projects exit 0 (test -e macos/Sources/Features/Groups は exit 1、C88〜C90 は周回 27 で exit 0、grep -rnE "hide_group\|GroupState\|\bGroups/" macos/Sources src SPEC.md README.md は exit 1(該当なし)。補足: 可視文言の目視は 2026-10-28T14:21:46Z の人間の確認でメニュー 70 項目+サブメニュー 75 項目に Group なし) |
| C105 | 必須 | リモート判定のテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 27: just swift-test exit 0 (項目とテストの対応は cycle 5 の記録どおり passed) |
| C107 | 必須 | プロジェクト一覧のテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 27: just swift-test exit 0 (項目とテストの対応は .idd/cycles/0010.md の「変更」節どおり。ProjectListRowSelectionTests は 11 件 passed) |
| C108 | 必須 | プロジェクト一覧の実機目視(検証: 人間) | met | human 2026-10-28T14:21:46Z: 第 3 回で再刻印(第 2 回の C108 の全項目 OK)。行 Delete 後の一覧操作・Cmd+L・打鍵の行き先も第 3 回で OK |
| C109 | 必須 | 優先度リセットのテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 27: just swift-test exit 0 (項目とテストの対応は cycle 5 の記録どおり passed) |
| C110 | 必須 | 優先度リセットの実機目視(検証: 人間) | met | human 2026-10-28T14:40:29Z: 人間が「OK でいい」と判断(翌朝 6:00 以降の実観測は待たずに人間の決定として刻む。明朝に戻らなければ追記される) |
| C111 | 必須 | 次トリガーのテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 27: just swift-test exit 0 (項目とテストの対応は cycle 5 の記録どおり passed) |
| C112 | 必須 | 次トリガーの実機目視(検証: 人間) | met | human 2026-10-28T14:21:46Z: 第 3 回で再刻印。次トリガー設定、一望に表示、ラベル帯には出ない |
| C113 | 必須 | キー変更の実機目視(検証: 人間) | met | human 2026-10-28T14:21:46Z: 第 3 回で再刻印。Cmd+E 編集、Cmd+Opt+E 一望、Cmd+Opt+N/D/Shift+D 無反応、Cmd+K でクリアしない |
| C114 | 必須 | 一覧セル編集の IME の実機目視(検証: 人間) | met | human 2026-10-28T14:40:29Z: ラベルのダブルクリック編集と Enter 確定後のフォーカスを人間が「大丈夫」と確認(IME の各項目は 14:21:46Z の第 3 回で再刻印、Esc 経路も同回で OK) |
| C115 | 必須 | ショートカット一覧の実機目視(検証: 人間) | met | human 2026-10-28T14:21:46Z: 第 3 回で再刻印。Cmd+/ で場面別グループ、各場面から開き Esc/再押下で復帰 |
| C116 | 必須 | 描画対象・停止/再開集合・解放・誕生時停止のテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 27: just swift-test exit 0 (ProjectRenderTargetTests 21 件 passed。全 5 項目の対応は cycle 2・3 の記録どおり) |
| C117 | 必須 | 描画停止・解放の実機観測(top / footprint、起動直後に落ちない、行 Delete 後のフォーカス、検証: 人間) | met | human 2026-10-28T14:21:46Z: 第 3 回(HEAD 23df54f)。(2) 行 Delete で閉じ 65 秒後にスレッド 19→11・IOSurface 13→7 領域、(4) 行 Delete 後の一覧・Cmd+L・打鍵 OK、(1)(3)(5)(6) は第 2 回の判定を再刻印(Release CPU 0.6〜0.7%、IOSurface 24 MB 対 24 MB) |
| C121 | 必須 | 停止集合に誕生した描画対象外の surface を含める(stop = (after.retained − after.drawn) ∩ (before.drawn ∪ born))(検証: C116) | met | cycle 27: just swift-test exit 0 (ProjectRenderTargetTests 21 件 passed) |
| C122 | 必須 | 停止・再開の適用は RenderTargetTransition のみ(唯一の例外: SurfaceView が生成直後に判断なしで一律に set_occlusion(false) を送り、すべて停止状態で生まれる。再開は resume だけ)、SurfaceView.isDrawing を持たない、未生成 surface は未適用扱い(検証: C116 + 読み合わせ) | met | cycle 25: just swift-test exit 0 (C116 の ProjectRenderTargetTests 21 件 passed。grep -rn xghostty_surface_set_occlusion macos/Sources は 2 箇所: SurfaceView_AppKit.swift の init で xghostty_surface_new 成功直後に判断なしの set_occlusion(false)、BaseTerminalController.syncRenderTargetOcclusion の RenderTargetTransition の stop/resume。grep -rn isDrawing macos/Sources は exit 1(該当なし)。周回 25 以降コードは不変) |
| C123 | 必須 | SurfaceView の `.ghosttySelectionDidChange` 購読は `object:` を渡さず `[weak self]` の filter で絞る(検証: 読み合わせ + C90) | met | cycle 27: just swift-test exit 0 (SurfaceView_AppKit.swift の publisher(for: .ghosttySelectionDidChange) に object: が無く、[weak self] の filter で notification.object === self に絞ることは周回 25 で読み合わせ、以降コードは不変) |
| C124 | 必須 | `XGhostty.Surface.deinit` はメインスレッドなら同期的に `xghostty_surface_free`(検証: 読み合わせ + C88〜C90 + C117) | met | cycle 27: just swift-test exit 0 (zig build・just test も exit 0。macos/Sources/XGhostty/XGhostty.Surface.swift の deinit が Thread.isMainThread なら xghostty_surface_free を同期で呼び return することを周回 26 で読み合わせた。C117(起動直後に落ちない)は 2026-10-28T14:21:46Z の人間確認で met) |
| C125 | 必須 | 一覧の行選択 Delete で閉じたとき新しい focus 先へキーボードフォーカスを移す(検証: C126 + 読み合わせ + C117) | met | cycle 27: just swift-test exit 0 (C126 met。BaseTerminalController.swift の 2 経路の case .switched が moveKeyboardFocus(toProjectSurface: focus) を呼ぶことを周回 26 で読み合わせた。C117 (4) は 2026-10-28T14:21:46Z の人間確認で met) |
| C126 | 必須 | 一覧セッション中の closeProject の focus 先・保持集合・セッション継続のテスト(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 27: just swift-test exit 0 (ProjectListRowSelectionTests の closingTheFocusedRowHandsTheNewFocusTargetAndKeepsTheSession と closingAnUnfocusedRowLeavesTheFocusedProjectAlone が passed) |
| C118 | 望ましい | マウスからノートを開く導線(検証: 人間) | unmet | - |
| C119 | 望ましい | ノート UI・プライマリー印の見た目の洗練(検証: 人間) | unmet | - |
| C120 | 望ましい | 全体ビューの非プライマリーペインのインジケータ(検証: 人間) | unmet | - |
| C106 | 望ましい | リモート split の実機目視(ssh で入れる別機体を用意できたとき)(検証: 人間) | unmet | - (2026-10-28 時点で ssh 先の別機体が無く、fdfd8fe で望ましいへ移った) |
