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

ideal_sha: 33b4a3729ce2b76ff62b3d4a2d96ed88cdcc24a83944a9f81ffef0c278a28e6b

| ID | 階層 | 条件 | 状態 | 証拠 |
|----|------|------|------|------|
| C1 | 必須 | プロジェクトごとに手書きの短いノートを保持できる(検証: C91) | met | cycle 79: just swift-test exit 0 (failed 0 件。周回 79 で復元の decode を直した後に実行) |
| C2 | 必須 | ノート最大 100 行、保存時超過は確認し OK で先頭 100 行へ切詰め・Cancel で編集へ戻る(検証: C91 + C97) | met | cycle 79: just swift-test exit 0 (C91 passed、failed 0 件。C97 は human 2026-11-11T12:35:08Z で確認) |
| C3 | 必須 | ノートは永続化され再起動後に同じプロジェクトへ復元(検証: C91) | met | cycle 79: just swift-test exit 0 (failed 0 件) |
| C4 | 必須 | ノートはプロジェクトに属しペインに属さない(検証: C91) | met | cycle 79: just swift-test exit 0 (failed 0 件) |
| C5 | 必須 | `Cmd+E` でノート編集オーバーレイ、`Cmd+Enter` で保存して閉じる(検証: C91 + C92) | met | cycle 79: just swift-test exit 0 (C91 passed、failed 0 件。C92 は human 2026-11-11T12:35:08Z で確認) |
| C6 | 必須 | オーバーレイで Esc は確認なしに破棄して閉じる(検証: C91 + C92) | met | cycle 79: just swift-test exit 0 (C91 passed、failed 0 件。C92 は human 2026-11-11T12:35:08Z で確認) |
| C7 | 必須 | `Cmd+Enter` の fullscreen 既定割り当てを解除(検証: C92) | met | cycle 85: PATH=/opt/homebrew/opt/zig@0.15/bin:$PATH zig build exit 0 (この zig-out 版での代行結果を C92 として human 2026-11-11T12:35:08Z が確認) |
| C8 | 必須 | `Cmd+Opt+E` で一望モードをトグル、Esc でも抜ける(検証: C92) | met | cycle 85: PATH=/opt/homebrew/opt/zig@0.15/bin:$PATH zig build exit 0 (この zig-out 版での代行結果を C92 として human 2026-11-11T12:35:08Z が確認) |
| C9 | 必須 | 一望モードは visible なプロジェクトのみ表示(検証: C91) | met | cycle 79: just swift-test exit 0 (failed 0 件) |
| C10 | 必須 | zoom 中に一望モードへ入ると zoom 解除(検証: C91) | met | cycle 79: just swift-test exit 0 (failed 0 件) |
| C11 | 必須 | 一望モードは閲覧専用で編集・focus 移動しない(検証: C91) | met | cycle 79: just swift-test exit 0 (failed 0 件) |
| C12 | 必須 | 一望モードで収まらないノートは切詰め、編集オーバーレイはスクロールで全文(検証: C92) | met | cycle 85: PATH=/opt/homebrew/opt/zig@0.15/bin:$PATH zig build exit 0 (この zig-out 版での代行結果を C92 として human 2026-11-11T12:35:08Z が確認) |
| C13 | 必須 | ノート UI は端末領域を恒久占有しない(検証: C92) | met | cycle 85: PATH=/opt/homebrew/opt/zig@0.15/bin:$PATH zig build exit 0 (この zig-out 版での代行結果を C92 として human 2026-11-11T12:35:08Z が確認) |
| C14 | 必須 | 既存機能と上流動作を退行させない(列挙した意図的変更を除く。優先度・締切・次トリガー・ソート等の削除と 5 列化(C144)、レイアウト型の向きの廃止と 2 種化・関連テストの削除と書き換え(C49〜C53)、focus 移動のキーの統一(`Opt+Tab` / `Cmd+Opt+矢印`、`Cmd+1〜9`・`Cmd+[` / `Cmd+]`・`Cmd+Ctrl+Opt+Shift+矢印` と `goto_project` の序数形式の廃止)・序数を visible すべてに付けること・関連テストの削除と書き換え(C146〜C149)を例外に含む)(検証: C88〜C90 exit 0 かつ既存テストが削除・無効化されず成功) | unmet | - (周回 86 の改訂で例外が増えた。周回 87 で 3 ゲートは exit 0 だが、C146〜C148 の実装後に削除・書き換えが例外の範囲に収まるかを照合し直す) |
| C15 | 必須 | ノートの判断ロジックはモデル層で XGhosttyTests から検証可能(検証: C91) | met | cycle 79: just swift-test exit 0 (failed 0 件) |
| C16 | 必須 | SPEC.md / README.md をノート層仕様に合わせ、README の Building 節に 3 検証コマンド(検証: 周回の読み合わせ) | met | cycle 79: grep -n "Building" -A12 README.md exit 0 (zig build / just test / just swift-test の 3 行を確認。ノート層の記述は周回 79 で変えていない) |
| C17 | 必須 | 各ペインはプライマリーフラグを持ち最初のペインがプライマリー(検証: C93) | met | cycle 79: just swift-test exit 0 (failed 0 件) |
| C18 | 必須 | プライマリーはプロジェクト内で常に 1 つ(検証: C93) | met | cycle 79: just swift-test exit 0 (failed 0 件) |
| C19 | 必須 | 全体ビューはプライマリーのみ描画、zoom 中は全ペイン(検証: C93 + C94) | met | cycle 79: just swift-test exit 0 (C93 passed、failed 0 件。C94 は human 2026-11-11T12:35:08Z で確認) |
| C20 | 必須 | 全体ビューの入力・focus はプライマリーへ、zoom 解除時に寄せる(検証: C93) | met | cycle 79: just swift-test exit 0 (failed 0 件) |
| C21 | 必須 | 全体ビューでペイン系操作は no-op(検証: C93) | met | cycle 79: just swift-test exit 0 (failed 0 件) |
| C22 | 必須 | zoom 中 `Cmd+P` で focused ペインをプライマリーへ(検証: C93 + C94) | met | cycle 79: just swift-test exit 0 (C93 passed、failed 0 件。C94 は human 2026-11-11T12:35:08Z で確認) |
| C23 | 必須 | プライマリーが `Cmd+W` で閉じたら最近傍 leaf を昇格、コマンド終了では昇格せず終了済みでプライマリーに留まる(検証: C93・C95 + C94 + C142) | met | cycle 79: just swift-test exit 0 (C93・C95 passed、failed 0 件。C142 は observed 83、C94 は human 2026-11-11T12:35:08Z で確認) |
| C24 | 必須 | プライマリーフラグの永続化と復元時正規化(検証: C93) | met | cycle 79: just swift-test exit 0 (failed 0 件) |
| C25 | 必須 | プライマリー印は zoom 中かつ複数ペイン時のみ右上に表示(検証: C94) | met | cycle 85: PATH=/opt/homebrew/opt/zig@0.15/bin:$PATH zig build exit 0 (この zig-out 版での代行結果を C94 として human 2026-11-11T12:35:08Z が確認) |
| C26 | 必須 | プライマリーの判断ロジックはモデル層(検証: C93) | met | cycle 79: just swift-test exit 0 (failed 0 件) |
| C27 | 必須 | SPEC.md / README.md をプライマリーペイン層仕様に合わせる(検証: 周回の読み合わせ) | met | cycle 79: grep -c "terminatedPanes" SPEC.md exit 0 (§22 のプライマリーペイン層と README の Primary panes は周回 79 で変えていない) |
| C28 | 必須 | プロジェクトを閉じる操作は常に確認ダイアログ(検証: C95 + C96) | met | cycle 79: just swift-test exit 0 (C95 passed、failed 0 件。C96 は human 2026-11-11T12:35:08Z で確認) |
| C29 | 必須 | ペインのプロセス(tmux クライアント / ssh)が exit したら兄弟の有無によらず閉じず終了済みで分割木に残す、最後でもプロジェクトは閉じない、状態は保存せず復元で全ペインが再 attach(検証: C95 + C96 + C142) | met | cycle 79: just swift-test exit 0 (C95 passed、failed 0 件。C142 は observed 83、C96 は human 2026-11-11T12:35:08Z で確認) |
| C30 | 必須 | 終了済みペインで Enter を押すとプロジェクト内の終了済みペインすべてが同じペインで再開、配置とプライマリーは不変、生きているペインに触れない(検証: C95 + C96 + C142) | met | cycle 79: just swift-test exit 0 (C95 passed、failed 0 件。C142 は observed 83、C96 は human 2026-11-11T12:35:08Z で確認) |
| C31 | 必須 | プロジェクト喪失経路は確認を経た明示的 close のみ(検証: C95 + C96) | met | cycle 79: just swift-test exit 0 (C95 passed、failed 0 件。C96 は human 2026-11-11T12:35:08Z で確認) |
| C32 | 必須 | ノート編集オーバーレイで標準編集ショートカットと Undo/Redo が効く(検証: C97) | met | cycle 85: PATH=/opt/homebrew/opt/zig@0.15/bin:$PATH zig build exit 0 (この zig-out 版での代行結果を C97 として human 2026-11-11T12:35:08Z が確認) |
| C33 | 必須 | 貼り付けで 100 行超過も C2 の確認を経る(検証: C91 + C97) | met | cycle 79: just swift-test exit 0 (C91 passed、failed 0 件。C97 は human 2026-11-11T12:35:08Z で確認) |
| C41 | 必須 | 序数は配置順(Core → Side、各種別内は表示順)の visible すべてに 1 から(9 で止めず最大 24)、ラベル帯と一覧の序数欄に表示、hidden には付けない、序数で飛ぶキーは持たない(検証: C107・C149 + C150) | unmet | - (周回 87 で序数の 9 個上限を撤去し just swift-test exit 0。C149・C150 と、序数で飛ぶキー(goto_project の序数形式)の削除 C148 が残る) |
| C44 | 必須 | 終了済み状態の判断ロジックはモデル層(検証: C95) | met | cycle 79: just swift-test exit 0 (failed 0 件) |
| C45 | 必須 | SPEC.md / README.md を削除保護・ショートカット対応の仕様に合わせる(検証: 周回の読み合わせ) | met | cycle 79: grep -c "terminatedPanes" SPEC.md exit 0 (§23 の削除保護・§30 のショートカット一覧と README の該当節は周回 79 で変えていない。§30.4 の件数 ShortcutCatalogTests 7 件 / ShortcutListSessionTests 2 件は @Test を struct ごとに数えて一致) |
| C46 | 必須 | `Cmd+Opt+H` で focused プロジェクトを即時 hidden(検証: C100 + C101) | met | cycle 79: just swift-test exit 0 (C100 passed、failed 0 件。C101 は human 2026-11-11T12:35:08Z で確認) |
| C47 | 必須 | visible は最低 1 つ残る(検証: C100) | met | cycle 79: just swift-test exit 0 (failed 0 件) |
| C48 | 必須 | hidden の復帰導線は一覧のみ、hidden シェルフ廃止(検証: C107 + C108) | met | cycle 79: just swift-test exit 0 (C107 passed、failed 0 件。C108 は human 2026-11-11T12:35:08Z で確認) |
| C49 | 必須 | レイアウト型は横長型・縦長型の 2 種(台座型と向きは廃止)、余りは後半行へ、行内幅は Core 1・Side 1/2 の重み、縦長型は転置、序数は横長型が行ごと・縦長型が列ごと(検証: C102 + C103・C139) | met | cycle 79: just swift-test exit 0 (C102 passed、failed 0 件。C139 は observed 81、C103 は human 2026-11-11T12:35:08Z で確認) |
| C50 | 必須 | visible 1〜24 で配置と序数の進み方が完全一致する型を畳み(実際の種別の組み合わせで比べる)、選択肢 1 つなら選ぶものが無い旨(検証: C102 + C103) | met | cycle 79: just swift-test exit 0 (C102 passed、failed 0 件。C103 は human 2026-11-11T12:35:08Z で確認) |
| C51 | 必須 | `Cmd+Opt+L` でレイアウト型の選択オーバーレイ、表示は「Wide」「Tall」(検証: C103) | met | cycle 85: PATH=/opt/homebrew/opt/zig@0.15/bin:$PATH zig build exit 0 (この zig-out 版での代行結果を C103 として human 2026-11-11T12:35:08Z が確認) |
| C52 | 必須 | レイアウト型は永続化、既定は横長型、保存された向きは捨てて形を保ち、台座型は横長型へ、再保存に向きを書かない(検証: C102 + C103) | met | cycle 79: just swift-test exit 0 (C102 passed、failed 0 件。C103 は human 2026-11-11T12:35:08Z で確認) |
| C53 | 必須 | Core → Side の順(各種別内は表示順)に型に従いスロットへ割当(横長型は行ごと、縦長型は列ごと)、序数が追従(検証: C102) | met | cycle 79: just swift-test exit 0 (failed 0 件。ProjectLayoutTypeTests は passed) |
| C54 | 必須 | visible 数または visible の種別の変化時に記憶の型で自動適用(検証: C102 + C101・C103) | met | cycle 79: just swift-test exit 0 (C102 passed、failed 0 件。C101・C103 は human 2026-11-11T12:35:08Z で確認) |
| C55 | 必須 | プロジェクト単位のレイアウト resize/equalize 廃止、zoom 中ペインは存続(検証: C103) | met | cycle 85: PATH=/opt/homebrew/opt/zig@0.15/bin:$PATH zig build exit 0 (この zig-out 版での代行結果を C103 として human 2026-11-11T12:35:08Z が確認) |
| C56 | 必須 | レイアウト型の判断ロジックはモデル層(検証: C102) | met | cycle 79: just swift-test exit 0 (failed 0 件) |
| C57 | 必須 | 「グループ」→「プロジェクト」全面改名(検証: C104) | met | cycle 79: test -d macos/Sources/Features/Projects exit 0 (test -e macos/Sources/Features/Groups は exit 1。C104 は cycle 79 で met) |
| C58 | 必須 | 改名は純粋なリネームで退行なし(検証: C104 + C88〜C90) | met | cycle 79: just swift-test exit 0 (zig build・just test も周回 79 で exit 0。C104 は cycle 79 で met) |
| C59 | 必須 | SPEC.md / README.md をレイアウト型・自動適用・hide・改名語彙に合わせる(検証: 周回の読み合わせ) | met | cycle 79: grep -n "向き\|行送り\|列送り" SPEC.md exit 0 (6 行で、§26.1 の廃止の記述と §26.4・§26.5 の旧保存の移行だけ。周回 79 はレイアウト型・hide・改名の記述を変えていない) |
| C63 | 必須 | `Cmd+L` で一覧をトグル(Esc で閉じない・zoom を解除しない・表示・種別・タイトル・端末・ノートの 5 列・8 割)(検証: C107 + C108) | met | cycle 79: just swift-test exit 0 (C107 passed、failed 0 件。C108 は human 2026-11-11T12:35:08Z で確認) |
| C64 | 必須 | 一覧は単一の並びで常に手動順、手動順・列順を永続化、hidden も同色、序数は C41 の配置順(検証: C107 + C108) | met | cycle 79: just swift-test exit 0 (C107 passed、failed 0 件。C108 は human 2026-11-11T12:35:08Z で確認) |
| C65 | 必須 | Notion 流儀のセルカーソル・Enter 編集・候補列挙(端末・種別)・Space 循環の廃止(検証: C107 + C108) | met | cycle 79: just swift-test exit 0 (C107 passed、failed 0 件。C108 は human 2026-11-11T12:35:08Z で確認) |
| C66 | 必須 | ノート列編集は全行対象、Shift+Enter で改行、一覧内 `Cmd+Opt+E` は全行表示トグル(検証: C107 + C108) | met | cycle 79: just swift-test exit 0 (C107 passed、failed 0 件。C108 は human 2026-11-11T12:35:08Z で確認) |
| C67 | 必須 | `Cmd+矢印` は端移動、`Opt+矢印` で行・列並べ替え(検証: C107 + C108) | met | cycle 79: just swift-test exit 0 (C107 passed、failed 0 件。C108 は human 2026-11-11T12:35:08Z で確認) |
| C68 | 必須 | `Cmd+N` は一覧での新規プロジェクト作成、visible 24 未満なら visible・24 なら hidden、種別は Core(検証: C107 + C108) | met | cycle 79: just swift-test exit 0 (C107 passed、failed 0 件。C108 は human 2026-11-11T12:35:08Z で確認) |
| C69 | 必須 | 一覧の `Cmd+Enter` で focus(hidden 行は近傍 visible へ)(検証: C107 + C108) | met | cycle 79: just swift-test exit 0 (C107 passed、failed 0 件。C108 は human 2026-11-11T12:35:08Z で確認) |
| C70 | 必須 | 一覧の判断ロジック(端末・種別の候補・Delete・行選択・クリップボード等)はモデル層(検証: C107) | met | cycle 79: just swift-test exit 0 (failed 0 件) |
| C76 | 必須 | SPEC.md / README.md を端末登録・tmux セッション〜優先度等の削除(記述を残さない)・レイアウト型の向きの廃止と 2 種化(向きの記述を残さない)・focus 移動のキーの統一(廃止したキーと序数ジャンプの記述を残さない)・序数を visible すべてに付けることまでの仕様に合わせる(検証: 周回の読み合わせ) | unmet | - (周回 86 の改訂で範囲が増えた。SPEC §7.3・§26.3 ほか・README の Cmd+1-9 と「先頭 9 つ」の記述が残っている。以下は改訂前の証拠) cycle 79: grep -n "Wide or its" README.md exit 0 (README の Layout types は Wide / Tall の 2 種で、grep -niE "row-major\|column-major\|ordinal direction" README.md は無出力。SPEC の「向き・行送り・列送り」は §26.1 の廃止と §26.4・§26.5 の移行だけ。周回 79 は SPEC §12.3 に復元で旧互換の surfaceTree を読まない旨を足しただけで、C76 の各仕様の記述は変えていない) |
| C78 | 必須 | 一覧テキスト列のセル編集が日本語 IME を受け付ける(検証: C114) | met | cycle 85: PATH=/opt/homebrew/opt/zig@0.15/bin:$PATH zig build exit 0 (この zig-out 版での代行結果を C114 として human 2026-11-11T12:35:08Z が確認) |
| C79 | 必須 | セルカーソルの Delete で列ごとの値削除(タイトル空・端末は手元へ・種別は Core へ・ノートは確認・表示は何もしない)(検証: C107 + C108) | met | cycle 79: just swift-test exit 0 (C107 passed、failed 0 件。C108 は human 2026-11-11T12:35:08Z で確認) |
| C80 | 必須 | Esc で行選択、行選択の Delete で確認付き削除(検証: C107 + C108) | met | cycle 79: just swift-test exit 0 (C107 passed、failed 0 件。C108 は human 2026-11-11T12:35:08Z で確認) |
| C81 | 必須 | `Cmd+/` でショートカット一覧をトグル(検証: C115) | met | cycle 85: PATH=/opt/homebrew/opt/zig@0.15/bin:$PATH zig build exit 0 (この zig-out 版での代行結果を C115 として human 2026-11-11T12:35:08Z が確認) |
| C82 | 必須 | `Cmd+K` の clear_screen 既定割り当て解除(検証: C113) | met | cycle 85: PATH=/opt/homebrew/opt/zig@0.15/bin:$PATH zig build exit 0 (この zig-out 版での代行結果を C113 として human 2026-11-11T12:35:08Z が確認) |
| C83 | 必須 | 一覧セルのクリップボード操作(端末列は登録名のみ、種別列は Core / Side のみ)と候補列挙中の Tab 横移動(検証: C107 + C108) | met | cycle 79: just swift-test exit 0 (C107 passed、failed 0 件。C108 は human 2026-11-11T12:35:08Z で確認) |
| C84 | 必須 | 描画対象の定義(全体ビュー: visible のプライマリー / zoom: 対象の全ペイン)(検証: C116) | met | cycle 79: just swift-test exit 0 (failed 0 件) |
| C85 | 必須 | 描画対象外は生成時を含めレンダラとディスプレイリンクを停止し復帰時に再開(検証: C116 + C117) | met | cycle 79: just swift-test exit 0 (C116 passed、failed 0 件。C117 は human 2026-11-11T12:35:08Z で確認) |
| C86 | 必須 | 閉じた surface を経路によらず undo 期限後に SurfaceView〜IOSurface まで解放(検証: C116・C126 + C123〜C125 の読み合わせ + C117) | met | cycle 79: just swift-test exit 0 (C116・C126 passed、failed 0 件。C123〜C125 は読み合わせ済み。周回 79 で復元時に旧互換の surfaceTree を decode しないようにし、「起動時の復元で置き換えられた初期 surface」はそもそも生まれなくなった。C117 は human 2026-11-11T12:35:08Z で確認) |
| C87 | 必須 | 描画対象の判定と停止・再開集合の導出はモデル層(検証: C116) | met | cycle 79: just swift-test exit 0 (failed 0 件) |
| C88 | 必須 | `zig build` が exit 0 | met | cycle 79: PATH=/opt/homebrew/opt/zig@0.15/bin:$PATH zig build exit 0 (周回 79 の変更をすべて終えた後に実行) |
| C89 | 必須 | `just test` が exit 0 | met | cycle 79: just test exit 0 |
| C90 | 必須 | `just swift-test` が exit 0 | met | cycle 79: just swift-test exit 0 (TEST SUCCEEDED、passed 742 行・failed 0 件) |
| C91 | 必須 | ノートのテスト群が macos/Tests/ に存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 79: just swift-test exit 0 (failed 0 件。ProjectNoteTests は変更なしで passed) |
| C92 | 必須 | ノートの実機目視(検証: 人間) | met | human 2026-11-11T12:35:08Z: 周回 85 の pair で、HEAD caddb02(対象ファイルは周回 79 の a051690 と同じ)の zig-out 版の代行結果を人間が確認した(Cmd+E・Cmd+Enter の保存・Esc の破棄・fullscreen にならない・Cmd+Opt+E の一望・切り詰めとスクロール。記録 0085) |
| C93 | 必須 | プライマリーペインのテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 79: just swift-test exit 0 (failed 0 件。ProjectPrimaryPaneTests は変更なしで passed) |
| C94 | 必須 | プライマリーペインの実機目視(Cmd+W で閉じたときの昇格を含む)(検証: 人間) | met | human 2026-11-11T12:35:08Z: 周回 85 の pair で、HEAD caddb02(対象ファイルは周回 79 の a051690 と同じ)の zig-out 版の代行結果(この条件の項目はすべて期待どおり。項目と計測は記録 0085)を人間が確認した |
| C95 | 必須 | 削除保護のテスト群(兄弟ペインの exit で閉じない・複数の終了済みの再開・終了済みを含む複数ペインの復元を含む)が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 79: just swift-test exit 0 (failed 0 件。ProjectTerminatedTests は変更なしで passed) |
| C96 | 必須 | 削除保護の実機目視(検証: 人間) | met | human 2026-11-11T12:35:08Z: 周回 85 の pair で、HEAD caddb02(対象ファイルは周回 79 の a051690 と同じ)の zig-out 版の代行結果(この条件の項目はすべて期待どおり。項目と計測は記録 0085)を人間が確認した |
| C97 | 必須 | ノート編集オーバーレイの編集ショートカット・100 行超過確認の実機目視(検証: 人間) | met | human 2026-11-11T12:35:08Z: 周回 85 の pair で、HEAD caddb02(対象ファイルは周回 79 の a051690 と同じ)の zig-out 版の代行結果(この条件の項目はすべて期待どおり。項目と計測は記録 0085)を人間が確認した |
| C100 | 必須 | hide のテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 79: just swift-test exit 0 (failed 0 件) |
| C101 | 必須 | hide の実機目視(検証: 人間) | met | human 2026-11-11T12:35:08Z: 周回 85 の pair で、HEAD caddb02(対象ファイルは周回 79 の a051690 と同じ)の zig-out 版の代行結果(この条件の項目はすべて期待どおり。項目と計測は記録 0085)を人間が確認した |
| C102 | 必須 | レイアウト型のテスト群(1〜24 の横長型・縦長型、畳み込み(n=9 は畳まれない・n=1 は 1 つ)、横長型は行ごと・縦長型は列ごとの割当、永続化と既定・向きを捨てる移行・台座型の移行・再保存に向きなし、自動適用)が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 79: just swift-test exit 0 (failed 0 件。ProjectLayoutTypeTests は周回 73 から変えておらず passed。項目の対応は周回 73 の記録のとおり) |
| C103 | 必須 | レイアウト型の実機目視(「Wide」「Tall」の 2 つだけ、6 → 5 の縦長型の組み直し、n=8 の 2+3+3 ほか)(検証: 人間) | met | human 2026-11-11T12:35:08Z: 周回 85 の pair で、HEAD caddb02(対象ファイルは周回 79 の a051690 と同じ)の zig-out 版の代行結果(この条件の項目はすべて期待どおり。項目と計測は記録 0085)を人間が確認した |
| C104 | 必須 | 改名完了: Projects/ が在り Groups/ が無い、C88〜C90 exit 0、可視文言に Group が無いことの目視(検証: test -d / test -e + C88〜C90 + 人間) | met | cycle 79: test -d macos/Sources/Features/Projects exit 0 (test -e macos/Sources/Features/Groups は exit 1、C88〜C90 は周回 79 で exit 0。周回 79 は可視文言を足しておらず、grep -rnE "\"[^\"]*\bGroup\b" macos/Sources/Features/Projects macos/Sources/App は無出力) |
| C107 | 必須 | プロジェクト一覧のテスト群(既定列順 5 列、端末・種別の候補・Delete・貼り付け、visible 24 の拒否、削除した値を含む保存の読み込みを含む)が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 79: just swift-test exit 0 (failed 0 件。一覧のテスト群は周回 79 で変えていない。項目の対応は周回 73 の記録のとおり) |
| C108 | 必須 | プロジェクト一覧の実機目視(5 列を含む)(検証: 人間) | met | human 2026-11-11T12:35:08Z: 周回 85 の pair で、HEAD caddb02(対象ファイルは周回 79 の a051690 と同じ)の zig-out 版の代行結果(この条件の項目はすべて期待どおり。項目と計測は記録 0085)を人間が確認した |
| C113 | 必須 | キー変更の実機目視(検証: 人間) | met | human 2026-11-11T12:35:08Z: 周回 85 の pair で、HEAD caddb02(対象ファイルは周回 79 の a051690 と同じ)の zig-out 版の代行結果(この条件の項目はすべて期待どおり。項目と計測は記録 0085)を人間が確認した |
| C114 | 必須 | 一覧セル編集の IME の実機目視(検証: 人間) | met | human 2026-11-11T12:35:08Z: 周回 85 の pair で、HEAD caddb02(対象ファイルは周回 79 の a051690 と同じ)の zig-out 版の代行結果(この条件の項目はすべて期待どおり。項目と計測は記録 0085)を人間が確認した |
| C115 | 必須 | ショートカット一覧の実機目視(検証: 人間) | met | human 2026-11-11T12:35:08Z: 周回 85 の pair で、HEAD caddb02(対象ファイルは周回 79 の a051690 と同じ)の zig-out 版の代行結果(この条件の項目はすべて期待どおり。項目と計測は記録 0085)を人間が確認した |
| C116 | 必須 | 描画対象・停止/再開集合・解放・誕生時停止のテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 79: just swift-test exit 0 (failed 0 件) |
| C117 | 必須 | 描画停止・解放の実機観測(top / footprint、起動直後に落ちない、行 Delete 後のフォーカス、検証: 人間) | met | human 2026-11-11T12:35:08Z: 周回 85 の pair で、HEAD caddb02(対象ファイルは周回 79 の a051690 と同じ)の zig-out 版の代行結果 6 項目を人間が確認した。visible 1・hidden 8 の 1 分放置後の CPU は 0.3〜1.4%(30 秒平均 0.5%)で hidden 0(0.3〜1.1%、30 秒平均 1.0%)と同水準として合格。解放は th 80 → 124 → 79・IOSurface 領域 58 → 88 → 58・SurfaceView 18 → 28 → 18。7 回の起動(18 ペインの復元 5 回)で固まり・クラッシュ 0 回。行 Delete 後の打鍵は新しい focus に届き、hidden 中の出力は再表示で見え、hidden 8 の再起動後は CPU 0.6%・IOSurface 24 MB(hidden 0 と同じ) |
| C121 | 必須 | 停止集合に誕生した描画対象外の surface を含める(stop = (after.retained − after.drawn) ∩ (before.drawn ∪ born))(検証: C116) | met | cycle 79: just swift-test exit 0 (failed 0 件) |
| C122 | 必須 | 停止・再開の適用は RenderTargetTransition のみ(生成直後の一律 set_occlusion(false) が唯一の例外)、SurfaceView.isDrawing を持たない(検証: C116 + 読み合わせ) | met | cycle 79: just swift-test exit 0 (C116 passed。grep -rn xghostty_surface_set_occlusion macos/Sources は 2 箇所、grep -rn isDrawing macos/Sources は 0 件。周回 79 は描画停止の経路に触れていない) |
| C123 | 必須 | SurfaceView の `.ghosttySelectionDidChange` 購読は `object:` を渡さず `[weak self]` の filter で絞る(検証: 読み合わせ + C90) | met | cycle 79: just swift-test exit 0 (SurfaceView_AppKit.swift:295 の publisher(for: .ghosttySelectionDidChange) に object: が無く、296 行の [weak self] の filter で絞ることを読み合わせた) |
| C124 | 必須 | `XGhostty.Surface.deinit` はメインスレッドなら同期的に `xghostty_surface_free`(検証: 読み合わせ + C88〜C90 + C117) | met | cycle 79: just swift-test exit 0 (zig build・just test も周回 79 で exit 0。XGhostty.Surface.swift:34 の Thread.isMainThread で同期解放を読み合わせた。周回 79 は C124 の文面を保ったまま、復元で捨てる surface を作らないことで固まる件を断った。C117 は human 2026-11-11T12:35:08Z で確認) |
| C125 | 必須 | 一覧の行選択 Delete で閉じたとき新しい focus 先へキーボードフォーカスを移す(検証: C126 + 読み合わせ + C117) | met | cycle 79: just swift-test exit 0 (C126 passed。performCloseProjectListRow の .switched が moveKeyboardFocus(toProjectSurface:) を呼ぶ(BaseTerminalController.swift:1900)。C117 は human 2026-11-11T12:35:08Z で確認) |
| C126 | 必須 | 一覧セッション中の closeProject の focus 先・保持集合・セッション継続のテスト(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 79: just swift-test exit 0 (failed 0 件) |
| C127 | 必須 | 端末を設定ファイルに登録(表示名・ホスト・色)、hostname 一致を手元、登録なしは暗黙の手元、再読み込みで反映(検証: C136 + C137) | met | observed 82: --config-file の mini(手元、colour28)・loop(xg-loop、colour33)・nowhere の 3 登録が端末候補にこの順で出て、mini のペインは ssh を介さず緑、loop は ssh 経由で青のバー(C137 の項目 1・2)。C136 は cycle 79 で通過 |
| C128 | 必須 | プロジェクトの端末(既定は手元)、一覧の端末列で候補選択・Delete で手元・登録名のみ貼り付け、永続化、欠落は手元扱い、変更は以後の新しいペインだけに効き終了済みの再開は元の端末の同じセッションへ(検証: C136 + C137) | met | observed 82: 一覧の端末セルの Enter で mini・loop・nowhere が列挙され、loop に替えた後の split だけが ssh 経由になり元のペインは緑のまま。端末を nowhere に替えた後も、detach した loop のペインは Enter で同じセッション(session_created 不変)へ戻り、再起動後も端末と端末の色が復元された。C136 は cycle 79 で通過 |
| C129 | 必須 | 全ペインを端末上の tmux セッションへ attach するコマンドで起動、セッション名 `<ID>-<n>`、ペインごとの端末・セッション名を永続化(検証: C136 + C137) | met | observed 82: 新規プロジェクトで `tmux ls` に d0bef40b-…-1 が現れ、split で -2・-5・-6 と連番が進んだ。Quit(Terminate)→ 再起動の前後で 4 セッションの名前と session_created が一致し(diff exit 0)、attached 0 → 1 に戻って -2 に keep-c82・restart-c82 が残った。C136 は cycle 79 で通過 |
| C130 | 必須 | 開始ディレクトリ `~/workspace/<タイトル>` → `~/workspace` → ホーム、split は `#{pane_current_path}` を引き継ぐ(検証: C136 + C137) | met | observed 82: x-ghostty の -1 を外から kill して Enter で作り直すと session_path・pane_current_path とも ~/workspace/x-ghostty、~/workspace/hidden-cloud の無い hidden-cloud は ~/workspace。-1 で cd /tmp の後の loop への split の -2 も /private/tmp。C136 は cycle 79 で通過 |
| C131 | 必須 | attach 時にそのセッションだけへ status-style・status-left・prefix C-s を設定、リネームで status-left を更新(検証: C136 + C137) | met | observed 82: -1 の show-options は prefix C-s・status-left "[x-ghostty] "・status-style bg=colour28、loop の -2 は bg=colour33。一覧で renamed へ改名すると -1・-2・-6 の status-left が "[renamed] " になりバーの左端も変わった。後始末後の show-options -g・~/.tmux.conf の shasum・既存 19 セッションの show-options は開始前と diff exit 0。C136 は cycle 79 で通過 |
| C132 | 必須 | tmux / ssh の終了でペインは兄弟の有無によらず終了済み、Enter でプロジェクト内の終了済みペインそれぞれの attach を再実行(検証: C136 + C137・C142) | met | observed 83: 兄弟のある loop の 3 ペインの ssh を外から kill すると 3 つとも終了済みで出力(Connection to 127.0.0.1 closed.)が見えたまま残り、Return 1 回で 3 つとも同じセッションへ再 attach した(C142)。C137 は observed 82(detach・到達不能ホストの終了済みと Enter の再開)、C136 は cycle 79 で通過 |
| C133 | 必須 | 閉じたペインのセッションを undo 期限後に kill、undo で戻せば kill しない(検証: C136 + C137) | met | observed 82: split した -5 を Cmd+W(Close Terminal? に Return)で閉じると 2 秒後は残り 11 秒後に消えた。-6 を閉じて Cmd+Z で戻すと 14 秒後も attached で残った。renamed を close_project で閉じると 12 秒後に -1・-2・-6 が消えた。C136 は cycle 79 で通過 |
| C134 | 必須 | 手元でない端末への ssh に TERM=xterm-256color を渡す(検証: C136 + C137) | met | observed 82: ps に `env TERM=xterm-256color ssh -t xg-loop`、ssh 先の -2 で `tmux display -p 'client.#{client_termname}.end'` が client.xterm-256color.end、`tmux list-clients` も xterm-256color。C136 は cycle 79 で通過 |
| C135 | 必須 | 端末・セッション・コマンド・候補・kill 対象の判断ロジックはモデル層(検証: C136) | met | cycle 79: just swift-test exit 0 (failed 0 件) |
| C136 | 必須 | 端末登録と tmux セッションのテスト群(9 項目)が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 79: just swift-test exit 0 (failed 0 件。端末・tmux のテスト群は周回 79 で変えていない) |
| C137 | 必須 | 端末登録と tmux セッションの実機観測(Mac mini、ssh ループバック、screencapture と tmux の出力)(検証: 周回の実機観測) | met | observed 82: HEAD f3b68e6(対象ファイルは周回 79 の a051690 と同じ)の zig-out 版で 9 項目を観測(新規プロジェクトの tmux と緑のバー・C-s c、loop への split が ssh 経由の青いバーでカレントパス /private/tmp を継承、~/workspace/x-ghostty と ~/workspace の開始ディレクトリ、再起動で同じセッションへ再 attach し出力が残る、C-s d の終了済みと Enter で同じセッション、nowhere のエラーが見えたまま終了済みで Enter で再試行、Cmd+W の kill と undo、リネームでバーのタイトル更新、client_termname が xterm-256color、~/.tmux.conf と既存セッションのオプション不変) |
| C138 | 必須 | 2 台の実機での目視(Mac mini の tmux・再起動後の再 attach・切断後の再 attach)(検証: 人間) | met | human 2026-11-11T12:35:08Z: 周回 85 の pair で、「HEAD caddb02 の zig-out 版(対象ファイルは周回 79 の a051690 と同じ)を MacBook Air を含む 2 台で既に確認済みか」の問いに人間が「はい。」と答えた。エージェントの代行は Mac mini 1 台だけで、2 台の目視は人間が行った |
| C139 | 必須 | 種別と重み付きレイアウトの実機観測(5 列・候補・重みの幅と高さ・Core → Side の序数・種別変更で組み直し・選択肢は Wide / Tall の 2 つで縦長型の序数は列ごと・24 と 25 個目の hidden・Side に印なし)(検証: 周回の実機観測) | met | observed 81: HEAD 2f4378c の zig-out 版で 7 項目を観測(5 列・種別候補 Core → Side・Delete で Core、横長型で Side が同じ行の Core の半分の幅で行の高さは等しく、縦長型で Side が同じ列の Core の約半分の高さ、序数は Core → Side で Cmd+2・Cmd+5 が追従、種別変更で即座に組み直し、Cmd+Opt+L は Wide / Tall の 2 つで縦長型は列ごとに上→下、24 visible · 1 hidden で 25 個目の表示トグルは拒否、Side の zoom・一望・ラベル帯に印なし) |
| C140 | 必須 | 種別 Core / Side、既定 Core、一覧の種別列(候補 Core → Side・Delete で Core・Core / Side のみ貼り付け)、永続化、大きさ以外に差を付けない(検証: C107 + C139) | met | cycle 79: just swift-test exit 0 (C107 は周回 79 で通過。C139 は observed 81 で met) |
| C141 | 必須 | 同時 visible は最大 24、24 で表示トグルを拒否、序数は visible すべてに付く(C41)(検証: C107 + C139) | unmet | - (周回 86 の改訂で序数の範囲が変わった。周回 87 で C107 を含む just swift-test は exit 0。C139 の観測を周回 87 の変更後の版で取り直す) |
| C142 | 必須 | ペイン単位の終了済み状態の実機観測(ssh ループバックの 3 ペインを外から終了・Enter 1 回で全再 attach・終了済みのまま再起動・兄弟のシェル exit と Cmd+W・プライマリーの非昇格と Cmd+W の昇格・一部だけの再開で生きたセッションを作り直さない)(検証: 周回の実機観測) | met | observed 83: HEAD 09f61b3(対象ファイルは周回 79 の a051690 と同じ)の zig-out 版で 6 項目を観測(loop の 3 ペインの ssh を外から kill すると 3 つとも終了済みで残り配置と ★ は不変、15 秒後も 3 セッションが tmux ls に残る。全体ビューで Return 1 回で 3 つとも attached に戻り session_created 不変で keep-c83-N が見える。3 つとも終了済みで Quit → 再起動すると 3 ペインと ★ が復元され attached・session_created 不変。兄弟 -4 で exit すると終了済みで残り Cmd+W で閉じた。プライマリー -2 の ssh の kill では ★ は動かず、手元のプライマリー -1 を Cmd+W で閉じると ★ が隣の -2 へ昇格。-2 だけの再開で -3・-4 の session_created と pane_pid は diff exit 0) |
| C143 | 必須 | ペインが分割木から失われるのは明示的 close(Cmd+W・close_project・一覧の行 Delete)のみ、コマンド終了では失われない(検証: C95 + C142) | met | observed 83: ssh の kill(1 ペイン・3 ペインとも)と兄弟のシェルの exit でペインは閉じずに終了済みで残り、失われたのは Cmd+W で閉じたペインだけ(C142 の観測)。C95 は cycle 79 で通過 |
| C144 | 必須 | 優先度・締切・次トリガー・ソート・毎朝リセット・日付候補が存在しない(一覧 5 列でソートバーなし・ラベル帯に印と締切なし・一望はノートだけ・ショートカット一覧に項目なし・関連コードなし)(検証: C107 + 周回の実機観測 + grep が無出力) | met | observed 81: 一覧は 5 列でソートバーなし、ラベル帯は「序数. タイトル」だけ、一望はタイトルとノートだけ、ショートカット一覧(Cmd+/ を末尾までスクロール)に優先度・締切・次トリガー・ソートの項目なし。C107 は cycle 79 で通過し、grep -rE "ProjectPriority\|ProjectDeadline\|ProjectNextTrigger\|ProjectSortState" macos/Sources macos/Tests は周回 81 で無出力・exit 1 |
| C145 | 必須 | 削除した値を含む保存を読み込んでも失敗せず黙って無視し再保存で書かない、ノート・種別・端末・手動順・列順は復元、列順からは削除した列だけを除く(検証: C107) | met | cycle 79: just swift-test exit 0 (failed 0 件。ProjectLedgerTests.aSaveCarryingTheRemovedValuesLoadsAndDropsThem が passed) |
| C146 | 必須 | `Opt+Tab` / `Opt+Shift+Tab` で次・前へ、全体ビューは序数の順に visible を巡り折り返す、zoom 中は zoom 対象のペインを分割木の走査順に巡り折り返す、巡る先が無い・オーバーレイ表示中は何もしない(検証: C149 + C150) | unmet | - |
| C147 | 必須 | `Cmd+Opt+矢印` で方向の隣へ、全体ビューは隣の visible プロジェクト、zoom 中は隣のペイン、隣が無い・オーバーレイ中は何もしない、C21 は不変(検証: C149 + C150) | unmet | - |
| C148 | 必須 | focus 移動は `Opt+Tab` 系と `Cmd+Opt+矢印` だけ、`Cmd+1〜9`・`Cmd+[` / `Cmd+]`・`Cmd+Ctrl+Opt+Shift+矢印` の既定割り当て廃止、`goto_project` の序数形式を削除、`goto_split` は action を残す、ショートカット一覧に廃止キーを載せない(検証: C150 + 読み合わせ + C88〜C90) | unmet | - |
| C149 | 必須 | focus 移動(次・前・方向)と序数(10 番目以降を含む)のテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | unmet | - (項目 4「序数が visible すべてに配置順で付き hidden に付かない」は周回 87 の ProjectVisibleCapTests.everyVisibleProjectInPlacementOrderHasANumber・aHiddenRowFreesItsNumberForTheNextProject・onlyAHiddenRowGoesWithoutANumber と WorkspaceStateTests.restoringNumbersEveryCappedVisibleProject が passed。項目 1〜3 が無い) |
| C150 | 必須 | focus 移動のキーの統一と序数の実機観測(Opt+Tab の巡回と折り返し・zoom 中のペイン巡回・Cmd+Opt+矢印・廃止キーで移らない・10 番目以降の番号・一覧中は移らない・ショートカット一覧)(検証: 周回の実機観測) | unmet | - |
| C118 | 望ましい | マウスからノートを開く導線(検証: 人間) | unmet | - |
| C119 | 望ましい | ノート UI・プライマリー印の見た目の洗練(検証: 人間) | unmet | - |
| C120 | 望ましい | 全体ビューの非プライマリーペインのインジケータ(検証: 人間) | unmet | - |
