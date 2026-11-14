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

<!-- 周回 91 で対象ファイル(SPEC.md・README.md)を変えたので、C = 91。cycle 90 以前と observed 91 以前と
     2026-11-11 の human の確認はすべて失効した。3 ゲートは周回 91 に取り直した。
     周回 92 は対象ファイルを変えずに C150・C139・C137・C142 と C144 の画面を observed 92 で取り直した。
     「人間の確認は失効」と注記した met の行は、テストを出典にしつつ人間の確認も条件に含む。realized の前に、
     主体が人間の条件(C92 ほか)を ask で問い直す必要がある。 -->

| ID | 階層 | 条件 | 状態 | 証拠 |
|----|------|------|------|------|
| C1 | 必須 | プロジェクトごとに手書きの短いノートを保持できる(検証: C91) | met | cycle 91: just swift-test exit 0 (failed 0 件。HEAD 1890405 + 周回 91 の SPEC/README の変更のみ) |
| C2 | 必須 | ノート最大 100 行、保存時超過は確認し OK で先頭 100 行へ切詰め・Cancel で編集へ戻る(検証: C91 + C97) | met | cycle 91: just swift-test exit 0 (C91 passed、failed 0 件。C97 の人間の確認は失効しており問い直しが要る) |
| C3 | 必須 | ノートは永続化され再起動後に同じプロジェクトへ復元(検証: C91) | met | cycle 91: just swift-test exit 0 (failed 0 件) |
| C4 | 必須 | ノートはプロジェクトに属しペインに属さない(検証: C91) | met | cycle 91: just swift-test exit 0 (failed 0 件) |
| C5 | 必須 | `Cmd+E` でノート編集オーバーレイ、`Cmd+Enter` で保存して閉じる(検証: C91 + C92) | met | cycle 91: just swift-test exit 0 (C91 passed、failed 0 件。C92 の人間の確認は失効しており問い直しが要る) |
| C6 | 必須 | オーバーレイで Esc は確認なしに破棄して閉じる(検証: C91 + C92) | met | cycle 91: just swift-test exit 0 (C91 passed、failed 0 件。C92 の人間の確認は失効しており問い直しが要る) |
| C7 | 必須 | `Cmd+Enter` の fullscreen 既定割り当てを解除(検証: C92) | unmet | - (検証は C92 の人間の確認だけで、2026-11-11 の確認は周回 89・91 の対象変更より前のため失効。C92 を問い直した後に met にする) |
| C8 | 必須 | `Cmd+Opt+E` で一望モードをトグル、Esc でも抜ける(検証: C92) | unmet | - (C92 の人間の確認が失効。C92 を問い直した後に met にする) |
| C9 | 必須 | 一望モードは visible なプロジェクトのみ表示(検証: C91) | met | cycle 91: just swift-test exit 0 (failed 0 件) |
| C10 | 必須 | zoom 中に一望モードへ入ると zoom 解除(検証: C91) | met | cycle 91: just swift-test exit 0 (failed 0 件) |
| C11 | 必須 | 一望モードは閲覧専用で編集・focus 移動しない(検証: C91) | met | cycle 91: just swift-test exit 0 (failed 0 件) |
| C12 | 必須 | 一望モードで収まらないノートは切詰め、編集オーバーレイはスクロールで全文(検証: C92) | unmet | - (C92 の人間の確認が失効。C92 を問い直した後に met にする) |
| C13 | 必須 | ノート UI は端末領域を恒久占有しない(検証: C92) | unmet | - (C92 の人間の確認が失効。C92 を問い直した後に met にする) |
| C14 | 必須 | 既存機能と上流動作を退行させない(列挙した意図的変更を除く。優先度・締切・次トリガー・ソート等の削除と 5 列化(C144)、レイアウト型の向きの廃止と 2 種化・関連テストの削除と書き換え(C49〜C53)、focus 移動のキーの統一(`Opt+Tab` / `Cmd+Opt+矢印`、`Cmd+1〜9`・`Cmd+[` / `Cmd+]`・`Cmd+Ctrl+Opt+Shift+矢印` と `goto_project` の序数形式の廃止)・序数を visible すべてに付けること・関連テストの削除と書き換え(C146〜C149)を例外に含む)(検証: C88〜C90 exit 0 かつ既存テストが削除・無効化されず成功) | met | cycle 91: just swift-test exit 0 (zig build・just test も周回 91 で exit 0。9cb808d と HEAD の @Test 名を突き合わせ(.idd/tmp/c91/base_tests.txt・head_tests.txt)、消えた Swift のテスト 110 件はすべて例外に当たる: 優先度・締切・次トリガー・ソート・日付候補(C144)、向き・台座型(C49〜C53)、兄弟のあるペインの close と終了の判定(C29・C30・C143。残りは新しい名前で同じ項目を検査)、gotoProjectIndex* と overviewBlocksIndexFocusMoves(C146〜C149)、上限 9 と序数 1〜9(上限 9→24 と C149)。Zig の test 名は消えたものが無い。追加された無効化は無く、SkipZigTest は新設の Config.zig の macOS 専用テストの非 Darwin ガードだけ) |
| C15 | 必須 | ノートの判断ロジックはモデル層で XGhosttyTests から検証可能(検証: C91) | met | cycle 91: just swift-test exit 0 (failed 0 件) |
| C16 | 必須 | SPEC.md / README.md をノート層仕様に合わせ、README の Building 節に 3 検証コマンド(検証: 周回の読み合わせ) | met | cycle 91: grep -n "Building" -A12 README.md exit 0 (236〜238 行に zig build / just test / just swift-test の 3 行。周回 91 の変更はノート層の記述を変えていない) |
| C17 | 必須 | 各ペインはプライマリーフラグを持ち最初のペインがプライマリー(検証: C93) | met | cycle 91: just swift-test exit 0 (failed 0 件) |
| C18 | 必須 | プライマリーはプロジェクト内で常に 1 つ(検証: C93) | met | cycle 91: just swift-test exit 0 (failed 0 件) |
| C19 | 必須 | 全体ビューはプライマリーのみ描画、zoom 中は全ペイン(検証: C93 + C94) | met | cycle 91: just swift-test exit 0 (C93 passed、failed 0 件。C94 の人間の確認は失効しており問い直しが要る) |
| C20 | 必須 | 全体ビューの入力・focus はプライマリーへ、zoom 解除時に寄せる(検証: C93) | met | cycle 91: just swift-test exit 0 (failed 0 件) |
| C21 | 必須 | 全体ビューでペイン系操作は no-op(検証: C93) | met | cycle 91: just swift-test exit 0 (failed 0 件) |
| C22 | 必須 | zoom 中 `Cmd+P` で focused ペインをプライマリーへ(検証: C93 + C94) | met | cycle 91: just swift-test exit 0 (C93 passed、failed 0 件。C94 の人間の確認は失効しており問い直しが要る) |
| C23 | 必須 | プライマリーが `Cmd+W` で閉じたら最近傍 leaf を昇格、コマンド終了では昇格せず終了済みでプライマリーに留まる(検証: C93・C95 + C94 + C142) | met | observed 92: C142 の観測で、手元のプライマリーを Cmd+W で閉じると隣の loop ペインに ★ が移り(shot 045)、プライマリーの ssh を外から終了しても ★ は終了済みのペインに残り(shot 059)、それを Cmd+W で閉じると残りのペインが主になった(shot 060)。C93・C95 は cycle 91: just swift-test exit 0。C94 の人間の確認は失効しており問い直しが要る |
| C24 | 必須 | プライマリーフラグの永続化と復元時正規化(検証: C93) | met | cycle 91: just swift-test exit 0 (failed 0 件) |
| C25 | 必須 | プライマリー印は zoom 中かつ複数ペイン時のみ右上に表示(検証: C94) | unmet | - (C94 の人間の確認が失効。C94 を問い直した後に met にする) |
| C26 | 必須 | プライマリーの判断ロジックはモデル層(検証: C93) | met | cycle 91: just swift-test exit 0 (failed 0 件) |
| C27 | 必須 | SPEC.md / README.md をプライマリーペイン層仕様に合わせる(検証: 周回の読み合わせ) | met | cycle 91: grep -c "terminatedPanes" SPEC.md exit 0 (§22 のプライマリーペイン層と README の Primary panes は周回 91 で変えていない。§11.3 の新しい記述は「全体ビューでペイン間の focus 移動は no-op(§22)」と §22.5 に一致) |
| C28 | 必須 | プロジェクトを閉じる操作は常に確認ダイアログ(検証: C95 + C96) | met | cycle 91: just swift-test exit 0 (C95 passed、failed 0 件。C96 の人間の確認は失効しており問い直しが要る) |
| C29 | 必須 | ペインのプロセス(tmux クライアント / ssh)が exit したら兄弟の有無によらず閉じず終了済みで分割木に残す、最後でもプロジェクトは閉じない、状態は保存せず復元で全ペインが再 attach(検証: C95 + C96 + C142) | met | observed 92: C142 の観測で、loop の 3 ペインの ssh を外から終了すると 3 つとも閉じずに終了済みで残り、12 秒後もセッションが残り、全終了済みのまま終了・再起動すると 3 ペインとも同じセッション(session_created 不変)へ再 attach した。兄弟ペインの exit でも閉じなかった。C95 は cycle 91: just swift-test exit 0。C96 の人間の確認は失効しており問い直しが要る |
| C30 | 必須 | 終了済みペインで Enter を押すとプロジェクト内の終了済みペインすべてが同じペインで再開、配置とプライマリーは不変、生きているペインに触れない(検証: C95 + C96 + C142) | met | observed 92: C142 の観測で、全体ビューのプライマリーへの Enter 1 回で 3 ペインすべてが元のセッションへ戻り、残した出力 c142-out-2〜4 が見え、配置と ★ は不変だった。1 ペインだけの再開で生きた -2・-3 の session_created は不変だった。C95 は cycle 91 で通過。C96 の人間の確認は失効しており問い直しが要る |
| C31 | 必須 | プロジェクト喪失経路は確認を経た明示的 close のみ(検証: C95 + C96) | met | cycle 91: just swift-test exit 0 (C95 passed、failed 0 件。C96 の人間の確認は失効しており問い直しが要る) |
| C32 | 必須 | ノート編集オーバーレイで標準編集ショートカットと Undo/Redo が効く(検証: C97) | unmet | - (C97 の人間の確認が失効。C97 を問い直した後に met にする) |
| C33 | 必須 | 貼り付けで 100 行超過も C2 の確認を経る(検証: C91 + C97) | met | cycle 91: just swift-test exit 0 (C91 passed、failed 0 件。C97 の人間の確認は失効しており問い直しが要る) |
| C41 | 必須 | 序数は配置順(Core → Side、各種別内は表示順)の visible すべてに 1 から(9 で止めず最大 24)、ラベル帯と一覧の序数欄に表示、hidden には付けない、序数で飛ぶキーは持たない(検証: C107・C149 + C150) | met | observed 92: C150 の観測で、visible 12 のラベル帯と一覧に 1〜12、hidden にした qk の行は番号なし、visible 11 のラベル帯に 10・11 が見え、Cmd+3 では focus が移らなかった。C139 の観測で 24 visible に 1〜24 が付いた。C107・C149 は cycle 91: just swift-test exit 0 |
| C44 | 必須 | 終了済み状態の判断ロジックはモデル層(検証: C95) | met | cycle 91: just swift-test exit 0 (failed 0 件) |
| C45 | 必須 | SPEC.md / README.md を削除保護・ショートカット対応の仕様に合わせる(検証: 周回の読み合わせ) | met | cycle 91: grep -n "30.4 テスト" SPEC.md exit 0 (§30.4 の件数を ShortcutCatalogTests 9 件 / ShortcutListSessionTests 2 件に直し、@Test を struct ごとに数えて一致。§30.3・§30.4 に Opt+Tab 系と Cmd+Opt+矢印 が全体ビューと zoom に載ること、廃止したキーを載せないことを足した。§23 の削除保護と README の該当節は変えていない) |
| C46 | 必須 | `Cmd+Opt+H` で focused プロジェクトを即時 hidden(検証: C100 + C101) | met | cycle 91: just swift-test exit 0 (C100 passed、failed 0 件。C101 の人間の確認は失効しており問い直しが要る) |
| C47 | 必須 | visible は最低 1 つ残る(検証: C100) | met | cycle 91: just swift-test exit 0 (failed 0 件) |
| C48 | 必須 | hidden の復帰導線は一覧のみ、hidden シェルフ廃止(検証: C107 + C108) | met | cycle 91: just swift-test exit 0 (C107 passed、failed 0 件。C108 の人間の確認は失効しており問い直しが要る) |
| C49 | 必須 | レイアウト型は横長型・縦長型の 2 種(台座型と向きは廃止)、余りは後半行へ、行内幅は Core 1・Side 1/2 の重み、縦長型は転置、序数は横長型が行ごと・縦長型が列ごと(検証: C102 + C103・C139) | met | observed 92: C139 の観測で、選択肢は Wide / Tall の 2 つだけ、横長型 5 個は 2+3 で Side が同じ行の Core の半分の幅、縦長型は左列 2・右列 3 で Side が半分の高さ、序数は列ごとに上→下、24 個は 4+5+5+5+5。C102 は cycle 91: just swift-test exit 0。C103 の人間の確認は失効しており問い直しが要る |
| C50 | 必須 | visible 1〜24 で配置と序数の進み方が完全一致する型を畳み(実際の種別の組み合わせで比べる)、選択肢 1 つなら選ぶものが無い旨(検証: C102 + C103) | met | cycle 91: just swift-test exit 0 (C102 passed、failed 0 件。C103 の人間の確認は失効しており問い直しが要る) |
| C51 | 必須 | `Cmd+Opt+L` でレイアウト型の選択オーバーレイ、表示は「Wide」「Tall」(検証: C103) | unmet | - (C103 の人間の確認が失効。C103 を問い直した後に met にする) |
| C52 | 必須 | レイアウト型は永続化、既定は横長型、保存された向きは捨てて形を保ち、台座型は横長型へ、再保存に向きを書かない(検証: C102 + C103) | met | cycle 91: just swift-test exit 0 (C102 passed、failed 0 件。C103 の人間の確認は失効しており問い直しが要る) |
| C53 | 必須 | Core → Side の順(各種別内は表示順)に型に従いスロットへ割当(横長型は行ごと、縦長型は列ごと)、序数が追従(検証: C102) | met | cycle 91: just swift-test exit 0 (failed 0 件。ProjectLayoutTypeTests は passed) |
| C54 | 必須 | visible 数または visible の種別の変化時に記憶の型で自動適用(検証: C102 + C101・C103) | met | cycle 91: just swift-test exit 0 (C102 passed、failed 0 件。C101・C103 の人間の確認は失効しており問い直しが要る) |
| C55 | 必須 | プロジェクト単位のレイアウト resize/equalize 廃止、zoom 中ペインは存続(検証: C103) | unmet | - (C103 の人間の確認が失効。C103 を問い直した後に met にする) |
| C56 | 必須 | レイアウト型の判断ロジックはモデル層(検証: C102) | met | cycle 91: just swift-test exit 0 (failed 0 件) |
| C57 | 必須 | 「グループ」→「プロジェクト」全面改名(検証: C104) | met | cycle 91: test -d macos/Sources/Features/Projects exit 0 (test -e macos/Sources/Features/Groups は exit 1。C104 は cycle 91 で met) |
| C58 | 必須 | 改名は純粋なリネームで退行なし(検証: C104 + C88〜C90) | met | cycle 91: just swift-test exit 0 (zig build・just test も周回 91 で exit 0。C104 は cycle 91 で met) |
| C59 | 必須 | SPEC.md / README.md をレイアウト型・自動適用・hide・改名語彙に合わせる(検証: 周回の読み合わせ) | met | cycle 91: grep -n "向き\|行送り\|列送り" SPEC.md exit 0 (6 行で、§26.1 の廃止の記述と §26.4・§26.5 の旧保存の移行だけ。周回 91 は §26.3 の「序数(Cmd+1〜9)」を「序数(§7.3)」に直しただけで、レイアウト型・hide・改名の記述は変えていない) |
| C63 | 必須 | `Cmd+L` で一覧をトグル(Esc で閉じない・zoom を解除しない・表示・種別・タイトル・端末・ノートの 5 列・8 割)(検証: C107 + C108) | met | cycle 91: just swift-test exit 0 (C107 passed、failed 0 件。C108 の人間の確認は失効しており問い直しが要る) |
| C64 | 必須 | 一覧は単一の並びで常に手動順、手動順・列順を永続化、hidden も同色、序数は C41 の配置順(検証: C107 + C108) | met | cycle 91: just swift-test exit 0 (C107 passed、failed 0 件。C108 の人間の確認は失効しており問い直しが要る) |
| C65 | 必須 | Notion 流儀のセルカーソル・Enter 編集・候補列挙(端末・種別)・Space 循環の廃止(検証: C107 + C108) | met | cycle 91: just swift-test exit 0 (C107 passed、failed 0 件。C108 の人間の確認は失効しており問い直しが要る) |
| C66 | 必須 | ノート列編集は全行対象、Shift+Enter で改行、一覧内 `Cmd+Opt+E` は全行表示トグル(検証: C107 + C108) | met | cycle 91: just swift-test exit 0 (C107 passed、failed 0 件。C108 の人間の確認は失効しており問い直しが要る) |
| C67 | 必須 | `Cmd+矢印` は端移動、`Opt+矢印` で行・列並べ替え(検証: C107 + C108) | met | cycle 91: just swift-test exit 0 (C107 passed、failed 0 件。C108 の人間の確認は失効しており問い直しが要る) |
| C68 | 必須 | `Cmd+N` は一覧での新規プロジェクト作成、visible 24 未満なら visible・24 なら hidden、種別は Core(検証: C107 + C108) | met | cycle 91: just swift-test exit 0 (C107 passed、failed 0 件。C108 の人間の確認は失効しており問い直しが要る) |
| C69 | 必須 | 一覧の `Cmd+Enter` で focus(hidden 行は近傍 visible へ)(検証: C107 + C108) | met | cycle 91: just swift-test exit 0 (C107 passed、failed 0 件。C108 の人間の確認は失効しており問い直しが要る) |
| C70 | 必須 | 一覧の判断ロジック(端末・種別の候補・Delete・行選択・クリップボード等)はモデル層(検証: C107) | met | cycle 91: just swift-test exit 0 (failed 0 件) |
| C76 | 必須 | SPEC.md / README.md を端末登録・tmux セッション〜優先度等の削除(記述を残さない)・レイアウト型の向きの廃止と 2 種化(向きの記述を残さない)・focus 移動のキーの統一(廃止したキーと序数ジャンプの記述を残さない)・序数を visible すべてに付けることまでの仕様に合わせる(検証: 周回の読み合わせ) | met | cycle 91: grep -c "focusMoveTarget" SPEC.md exit 0 (周回 91 に SPEC §7.3(序数は visible すべて・hidden は「·」・序数で飛ぶキーなし)・§7.3 の上限時の挙動・§9.1(序数形式を一覧から消し、削除と SplitFocusDirection だけを取ることを記録)・§9.2・§10.3(Opt+Tab / Opt+Shift+Tab・Cmd+Opt+矢印・performable なし・廃止した既定の記録は 1 箇所)・§11.3 を focusMoveTarget の仕様へ書き直し・§14 の不変条件 20・§17 の設定例・§20・§21.3・§26.3・§27.1・§27 のテスト節・§30.3・§30.4 を直し、README の Projects・Project list・Layout types を Opt+Tab 系・Cmd+Opt+矢印・番号は visible すべてへ直した。grep で Cmd+1〜9・先頭 9 つ・1～9・maxProjectOrdinal・gotoProjectIndex・first nine は §9.1 と §10.3 の廃止の記録の外に無い。reviewer の読み取り審査でコードとの食い違いなし(指摘の §7.2 の hidden 行の「·」・§20 の序数の導出・§17 の廃止済み action の設定例も直した)。端末登録〜向きの記述は周回 79 の読み合わせから変えていない) |
| C78 | 必須 | 一覧テキスト列のセル編集が日本語 IME を受け付ける(検証: C114) | unmet | - (C114 の人間の確認が失効。C114 を問い直した後に met にする) |
| C79 | 必須 | セルカーソルの Delete で列ごとの値削除(タイトル空・端末は手元へ・種別は Core へ・ノートは確認・表示は何もしない)(検証: C107 + C108) | met | cycle 91: just swift-test exit 0 (C107 passed、failed 0 件。C108 の人間の確認は失効しており問い直しが要る) |
| C80 | 必須 | Esc で行選択、行選択の Delete で確認付き削除(検証: C107 + C108) | met | cycle 91: just swift-test exit 0 (C107 passed、failed 0 件。C108 の人間の確認は失効しており問い直しが要る) |
| C81 | 必須 | `Cmd+/` でショートカット一覧をトグル(検証: C115) | unmet | - (C115 の人間の確認が失効。C115 を問い直した後に met にする) |
| C82 | 必須 | `Cmd+K` の clear_screen 既定割り当て解除(検証: C113) | unmet | - (C113 の人間の確認が失効。C113 を問い直した後に met にする) |
| C83 | 必須 | 一覧セルのクリップボード操作(端末列は登録名のみ、種別列は Core / Side のみ)と候補列挙中の Tab 横移動(検証: C107 + C108) | met | cycle 91: just swift-test exit 0 (C107 passed、failed 0 件。C108 の人間の確認は失効しており問い直しが要る) |
| C84 | 必須 | 描画対象の定義(全体ビュー: visible のプライマリー / zoom: 対象の全ペイン)(検証: C116) | met | cycle 91: just swift-test exit 0 (failed 0 件) |
| C85 | 必須 | 描画対象外は生成時を含めレンダラとディスプレイリンクを停止し復帰時に再開(検証: C116 + C117) | met | cycle 91: just swift-test exit 0 (C116 passed、failed 0 件。C117 の人間の確認は失効しており問い直しが要る) |
| C86 | 必須 | 閉じた surface を経路によらず undo 期限後に SurfaceView〜IOSurface まで解放(検証: C116・C126 + C123〜C125 の読み合わせ + C117) | met | cycle 91: just swift-test exit 0 (C116・C126 passed、failed 0 件。C123〜C125 は周回 91 に読み合わせ済み。C117 の人間の確認は失効しており問い直しが要る) |
| C87 | 必須 | 描画対象の判定と停止・再開集合の導出はモデル層(検証: C116) | met | cycle 91: just swift-test exit 0 (failed 0 件) |
| C88 | 必須 | `zig build` が exit 0 | met | cycle 91: PATH=/opt/homebrew/opt/zig@0.15/bin:$PATH zig build exit 0 (HEAD 1890405 + 周回 91 の SPEC/README の変更。ビルド入力のコードは HEAD と同じ) |
| C89 | 必須 | `just test` が exit 0 | met | cycle 91: just test exit 0 |
| C90 | 必須 | `just swift-test` が exit 0 | met | cycle 91: just swift-test exit 0 (passed 759 行・failed 0 件・TEST SUCCEEDED) |
| C91 | 必須 | ノートのテスト群が macos/Tests/ に存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 91: just swift-test exit 0 (failed 0 件。ProjectNoteTests は変更なしで passed) |
| C92 | 必須 | ノートの実機目視(検証: 人間) | unmet | - (human 2026-11-11T12:35:08Z の確認は周回 89・91 の対象変更より前で失効。代行の機械検査の証拠を添えて ask で問い直す) |
| C93 | 必須 | プライマリーペインのテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 91: just swift-test exit 0 (failed 0 件。ProjectPrimaryPaneTests は変更なしで passed) |
| C94 | 必須 | プライマリーペインの実機目視(Cmd+W で閉じたときの昇格を含む)(検証: 人間) | unmet | - (human 2026-11-11T12:35:08Z の確認は失効。ask で問い直す) |
| C95 | 必須 | 削除保護のテスト群(兄弟ペインの exit で閉じない・複数の終了済みの再開・終了済みを含む複数ペインの復元を含む)が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 91: just swift-test exit 0 (failed 0 件。ProjectTerminatedTests は変更なしで passed) |
| C96 | 必須 | 削除保護の実機目視(検証: 人間) | unmet | - (human 2026-11-11T12:35:08Z の確認は失効。ask で問い直す) |
| C97 | 必須 | ノート編集オーバーレイの編集ショートカット・100 行超過確認の実機目視(検証: 人間) | unmet | - (human 2026-11-11T12:35:08Z の確認は失効。ask で問い直す) |
| C100 | 必須 | hide のテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 91: just swift-test exit 0 (failed 0 件) |
| C101 | 必須 | hide の実機目視(検証: 人間) | unmet | - (human 2026-11-11T12:35:08Z の確認は失効。ask で問い直す) |
| C102 | 必須 | レイアウト型のテスト群(1〜24 の横長型・縦長型、畳み込み(n=9 は畳まれない・n=1 は 1 つ)、横長型は行ごと・縦長型は列ごとの割当、永続化と既定・向きを捨てる移行・台座型の移行・再保存に向きなし、自動適用)が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 91: just swift-test exit 0 (failed 0 件。ProjectLayoutTypeTests は周回 73 から変えておらず passed。項目の対応は周回 73 の記録のとおり) |
| C103 | 必須 | レイアウト型の実機目視(「Wide」「Tall」の 2 つだけ、6 → 5 の縦長型の組み直し、n=8 の 2+3+3 ほか)(検証: 人間) | unmet | - (human 2026-11-11T12:35:08Z の確認は失効。ask で問い直す) |
| C104 | 必須 | 改名完了: Projects/ が在り Groups/ が無い、C88〜C90 exit 0、可視文言に Group が無いことの目視(検証: test -d / test -e + C88〜C90 + 人間) | met | cycle 91: test -d macos/Sources/Features/Projects exit 0 (test -e macos/Sources/Features/Groups は exit 1、C88〜C90 は周回 91 で exit 0。可視文言の目視は周回 90 の観測で Group の文言なし、以前の確認: grep -rnE "\"[^\"]*\bGroup\b" macos/Sources/Features/Projects macos/Sources/App は無出力) |
| C107 | 必須 | プロジェクト一覧のテスト群(既定列順 5 列、端末・種別の候補・Delete・貼り付け、visible 24 の拒否、削除した値を含む保存の読み込みを含む)が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 91: just swift-test exit 0 (failed 0 件。項目の対応は周回 73 の記録のとおり) |
| C108 | 必須 | プロジェクト一覧の実機目視(5 列を含む)(検証: 人間) | unmet | - (human 2026-11-11T12:35:08Z の確認は失効。ask で問い直す) |
| C113 | 必須 | キー変更の実機目視(検証: 人間) | unmet | - (human 2026-11-11T12:35:08Z の確認は失効。ask で問い直す) |
| C114 | 必須 | 一覧セル編集の IME の実機目視(検証: 人間) | unmet | - (human 2026-11-11T12:35:08Z の確認は失効。ask で問い直す) |
| C115 | 必須 | ショートカット一覧の実機目視(検証: 人間) | unmet | - (human 2026-11-11T12:35:08Z の確認は失効。ask で問い直す) |
| C116 | 必須 | 描画対象・停止/再開集合・解放・誕生時停止のテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 91: just swift-test exit 0 (failed 0 件) |
| C117 | 必須 | 描画停止・解放の実機観測(top / footprint、起動直後に落ちない、行 Delete 後のフォーカス、検証: 人間) | unmet | - (human 2026-11-11T12:35:08Z の確認は失効。ask で問い直す。前回の代行の計測値は記録 0085) |
| C121 | 必須 | 停止集合に誕生した描画対象外の surface を含める(stop = (after.retained − after.drawn) ∩ (before.drawn ∪ born))(検証: C116) | met | cycle 91: just swift-test exit 0 (failed 0 件) |
| C122 | 必須 | 停止・再開の適用は RenderTargetTransition のみ(生成直後の一律 set_occlusion(false) が唯一の例外)、SurfaceView.isDrawing を持たない(検証: C116 + 読み合わせ) | met | cycle 91: just swift-test exit 0 (C116 passed。周回 91 に grep -rn xghostty_surface_set_occlusion macos/Sources は 2 箇所、grep -rn isDrawing macos/Sources は 0 件) |
| C123 | 必須 | SurfaceView の `.ghosttySelectionDidChange` 購読は `object:` を渡さず `[weak self]` の filter で絞る(検証: 読み合わせ + C90) | met | cycle 91: just swift-test exit 0 (周回 91 に SurfaceView_AppKit.swift:295 の publisher(for: .ghosttySelectionDidChange) に object: が無く、296 行の [weak self] の filter で絞ることを読み合わせた) |
| C124 | 必須 | `XGhostty.Surface.deinit` はメインスレッドなら同期的に `xghostty_surface_free`(検証: 読み合わせ + C88〜C90 + C117) | met | cycle 91: just swift-test exit 0 (zig build・just test も周回 91 で exit 0。周回 91 に XGhostty.Surface.swift:34 の Thread.isMainThread で同期解放を読み合わせた。C117 の人間の確認は失効しており問い直しが要る) |
| C125 | 必須 | 一覧の行選択 Delete で閉じたとき新しい focus 先へキーボードフォーカスを移す(検証: C126 + 読み合わせ + C117) | met | cycle 91: just swift-test exit 0 (C126 passed。周回 91 に performCloseProjectListRow の .switched が BaseTerminalController.swift:1892 で moveKeyboardFocus(toProjectSurface:) を呼ぶことを読み合わせた。C117 の人間の確認は失効しており問い直しが要る) |
| C126 | 必須 | 一覧セッション中の closeProject の focus 先・保持集合・セッション継続のテスト(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 91: just swift-test exit 0 (failed 0 件) |
| C127 | 必須 | 端末を設定ファイルに登録(表示名・ホスト・色)、hostname 一致を手元、登録なしは暗黙の手元、再読み込みで反映(検証: C136 + C137) | met | observed 92: C137 の観測で、検証用設定の mini(手元、colour28)・loop(xg-loop、colour33)・nowhere の 3 登録が一覧の端末候補にこの順で出て、mini のペインは ssh を介さず緑のバー、loop のペインは ssh 経由で青のバーだった。C136 は cycle 91: just swift-test exit 0 |
| C128 | 必須 | プロジェクトの端末(既定は手元)、一覧の端末列で候補選択・Delete で手元・登録名のみ貼り付け、永続化、欠落は手元扱い、変更は以後の新しいペインだけに効き終了済みの再開は元の端末の同じセッションへ(検証: C136 + C137) | met | observed 92: C137 の観測で、新規プロジェクトの端末は mini、端末列で loop を選んだ後の split だけが loop になり元のペインは緑のまま、detach した loop ペインの Enter は同じセッション(session_created 不変)へ戻り、再起動後も端末と青のバーが復元された。C136 は cycle 91: just swift-test exit 0 |
| C129 | 必須 | 全ペインを端末上の tmux セッションへ attach するコマンドで起動、セッション名 `<ID>-<n>`、ペインごとの端末・セッション名を永続化(検証: C136 + C137) | met | observed 92: C137 の観測で、新規プロジェクトのペインが c23c5144-…-1 の tmux に入り、ps の attach コマンドは `tmux new-session -A -s <ID>-<n> -c "$d"`(loop は `env TERM=xterm-256color ssh -t xg-loop` で包む)、終了・再起動後に -1・-2・-5 が session_created 不変のまま attached 1 に戻った。C136 は cycle 91: just swift-test exit 0 |
| C130 | 必須 | 開始ディレクトリ `~/workspace/<タイトル>` → `~/workspace` → ホーム、split は `#{pane_current_path}` を引き継ぐ(検証: C136 + C137) | met | observed 92: C137 の観測で、x-ghostty の作り直したセッションは /Users/banri/workspace/x-ghostty、~/workspace/calm-field の無い calm-field は /Users/banri/workspace、`cd /tmp` 後の split は -1・-2 とも /private/tmp だった。C136 は cycle 91: just swift-test exit 0 |
| C131 | 必須 | attach 時にそのセッションだけへ status-style・status-left・prefix C-s を設定、リネームで status-left を更新(検証: C136 + C137) | met | observed 92: C137 の観測で、-1 のセッションオプションが prefix C-s・status-left "[x-ghostty] "・status-style bg=colour28、リネーム後は -1・-2・-5 の status-left が "[renamed] " でバー左端も [renamed]。show-options -g・~/.tmux.conf の shasum・開始前の 21 セッションのオプションは前後で diff exit 0。C136 は cycle 91: just swift-test exit 0 |
| C132 | 必須 | tmux / ssh の終了でペインは兄弟の有無によらず終了済み、Enter でプロジェクト内の終了済みペインそれぞれの attach を再実行(検証: C136 + C137・C142) | met | observed 92: C137 の観測で、C-s d の detach と外からの kill-session で終了済みになり Enter で戻り、到達不能な nowhere はエラーが見えたまま終了済みで Enter で再試行した(Last login 16:31:28 → 16:32:21)。C142 の観測で兄弟のある 3 ペインも終了済みで残り Enter 1 回で全再 attach。C136 は cycle 91: just swift-test exit 0 |
| C133 | 必須 | 閉じたペインのセッションを undo 期限後に kill、undo で戻せば kill しない(検証: C136 + C137) | met | observed 92: C137 の観測で、split した -4 を Cmd+W・Close で閉じると 2 秒後は残り 11 秒後に消え、-5 を閉じて Cmd+Z で戻すと 14 秒後も attached で残った。renamed の close_project の 13 秒後に -1・-2・-5 が消えた。C136 は cycle 91: just swift-test exit 0 |
| C134 | 必須 | 手元でない端末への ssh に TERM=xterm-256color を渡す(検証: C136 + C137) | met | observed 92: C137 の観測で、loop のペインの `tmux display -p 'client.#{client_termname}.end'` が client.xterm-256color.end、list-clients も xterm-256color。C136 は cycle 91: just swift-test exit 0 |
| C135 | 必須 | 端末・セッション・コマンド・候補・kill 対象の判断ロジックはモデル層(検証: C136) | met | cycle 91: just swift-test exit 0 (failed 0 件) |
| C136 | 必須 | 端末登録と tmux セッションのテスト群(9 項目)が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 91: just swift-test exit 0 (failed 0 件。端末・tmux のテスト群は周回 79 で変えていない) |
| C137 | 必須 | 端末登録と tmux セッションの実機観測(Mac mini、ssh ループバック、screencapture と tmux の出力)(検証: 周回の実機観測) | met | observed 92: HEAD f7b3aa8 の zig-out 版で 9 項目すべて期待どおり(新規ペインが <ID>-1 の tmux で緑のバーと [x-ghostty]・C-s c で 2 つ目のウィンドウ / loop の split が青のバーで同じ /private/tmp / x-ghostty と ~/workspace の開始ディレクトリ / 再起動後に同じセッションへ戻り keep-c92・restart-c92 が残る / detach と到達不能ホストの終了済みと Enter / close の kill と undo / リネームの status-left / client_termname xterm-256color / tmux.conf と他セッションのオプション不変)。画像と道具は .idd/tmp/c92/c137/ |
| C138 | 必須 | 2 台の実機での目視(Mac mini の tmux・再起動後の再 attach・切断後の再 attach)(検証: 人間) | unmet | - (human 2026-11-11T12:35:08Z の確認は失効。ask で問い直す) |
| C139 | 必須 | 種別と重み付きレイアウトの実機観測(5 列・候補・重みの幅と高さ・Core → Side の序数・種別変更で組み直し・選択肢は Wide / Tall の 2 つで縦長型の序数は列ごと・24 と 25 個目の hidden・Side に印なし)(検証: 周回の実機観測) | met | observed 92: HEAD f7b3aa8 の zig-out 版で 7 項目すべて期待どおり(一覧は表示・種別・タイトル・端末・ノートの 5 列、種別の候補は Core → Side、Delete で Core / qa を Side にすると序数 5 になり背後が 2+3 に組み直され Side は半分の幅 / Cmd+Opt+L は Wide・Tall だけ、Tall は列ごとの序数で Side は半分の高さ / 24 個 visible に 1〜24、25 個目は hidden で表示トグルは「no room to show」で拒否 / Side の zoom・一望・ラベル帯に印なし)。手順の Cmd+2・Cmd+5 は Opt+Tab に置き換えた。画像と道具は .idd/tmp/c92/c139/ |
| C140 | 必須 | 種別 Core / Side、既定 Core、一覧の種別列(候補 Core → Side・Delete で Core・Core / Side のみ貼り付け)、永続化、大きさ以外に差を付けない(検証: C107 + C139) | met | observed 92: C139 の観測で、新規行の種別は Core、候補は Core → Side、Delete で Core に戻り、Side は大きさ以外に印が無かった。C107 は cycle 91: just swift-test exit 0 |
| C141 | 必須 | 同時 visible は最大 24、24 で表示トグルを拒否、序数は visible すべてに付く(C41)(検証: C107 + C139) | met | observed 92: C139 の観測で、24 個 visible に序数 1〜24 が付き、25 個目の新規行は hidden で、その表示トグルは拒否された(24 visible · 1 hidden)。C107 は cycle 91: just swift-test exit 0 |
| C142 | 必須 | ペイン単位の終了済み状態の実機観測(ssh ループバックの 3 ペインを外から終了・Enter 1 回で全再 attach・終了済みのまま再起動・兄弟のシェル exit と Cmd+W・プライマリーの非昇格と Cmd+W の昇格・一部だけの再開で生きたセッションを作り直さない)(検証: 周回の実機観測) | met | observed 92: HEAD f7b3aa8 の zig-out 版で 6 項目すべて期待どおり(loop の 3 ペインの ssh を外から kill して 3 つとも終了済み・配置と ★ 不変・12 秒後もセッション残存 / 全体ビューの Enter 1 回で 3 つとも再 attach し c142-out-2〜4 が見える / 全終了済みのまま終了・再起動で 3 つとも attached 1・session_created 不変 / 兄弟ペインで exit して終了済み・Cmd+W で閉じた / プライマリーの ssh 終了で ★ は残り、Cmd+W で閉じると隣が主になる / 1 ペインだけの再開で -2・-3 の session_created 不変)。画像は .idd/tmp/c92/c137/ の 040〜060 |
| C143 | 必須 | ペインが分割木から失われるのは明示的 close(Cmd+W・close_project・一覧の行 Delete)のみ、コマンド終了では失われない(検証: C95 + C142) | met | observed 92: C142 の観測で、外からの ssh 終了・シェルの exit・プライマリーのコマンド終了のどれでもペインは分割木に残り、消えたのは Cmd+W と close_project のときだけだった。C95 は cycle 91: just swift-test exit 0 |
| C144 | 必須 | 優先度・締切・次トリガー・ソート・毎朝リセット・日付候補が存在しない(一覧 5 列でソートバーなし・ラベル帯に印と締切なし・一望はノートだけ・ショートカット一覧に項目なし・関連コードなし)(検証: C107 + 周回の実機観測 + grep が無出力) | met | observed 92: C150 の観測で、一覧は 5 列でソートバーが無く(shot 002)、ラベル帯は序数とタイトルだけで印と締切が無く(003)、一望はタイトルと「no note」だけ(080)、ショートカット一覧の先頭から末尾まで(070・071)優先度・締切・ソートの項目が無かった。周回 92 に grep -rE "ProjectPriority\|ProjectDeadline\|ProjectNextTrigger\|ProjectSortState" macos/Sources macos/Tests は無出力(exit 1)。C107 は cycle 91: just swift-test exit 0 |
| C145 | 必須 | 削除した値を含む保存を読み込んでも失敗せず黙って無視し再保存で書かない、ノート・種別・端末・手動順・列順は復元、列順からは削除した列だけを除く(検証: C107) | met | cycle 91: just swift-test exit 0 (failed 0 件。ProjectLedgerTests.aSaveCarryingTheRemovedValuesLoadsAndDropsThem が passed) |
| C146 | 必須 | `Opt+Tab` / `Opt+Shift+Tab` で次・前へ、全体ビューは序数の順に visible を巡り折り返す、zoom 中は zoom 対象のペインを分割木の走査順に巡り折り返す、巡る先が無い・オーバーレイ表示中は何もしない(検証: C149 + C150) | met | observed 92: C150 の観測で、全体ビューの Opt+Tab が 1→2→3、Opt+Shift+Tab が 3→2→1→12(折り返し)、Opt+Tab で 12→1 に戻り、zoom 中は zoom 対象を変えずに 3 ペインを巡って両端で折り返し、一覧の表示中は移らなかった。C149 は cycle 91: just swift-test exit 0 |
| C147 | 必須 | `Cmd+Opt+矢印` で方向の隣へ、全体ビューは隣の visible プロジェクト、zoom 中は隣のペイン、隣が無い・オーバーレイ中は何もしない、C21 は不変(検証: C149 + C150) | met | observed 92: C150 の観測で、全体ビューの Cmd+Opt+→↓←↑ が 1→2→6→5→1、上端の ↑ では 1 のまま、zoom 中は ← で隣のペイン、右端の → では動かず、一覧の表示中は移らなかった。C149 は cycle 91: just swift-test exit 0 |
| C148 | 必須 | focus 移動は `Opt+Tab` 系と `Cmd+Opt+矢印` だけ、`Cmd+1〜9`・`Cmd+[` / `Cmd+]`・`Cmd+Ctrl+Opt+Shift+矢印` の既定割り当て廃止、`goto_project` の序数形式を削除、`goto_split` は action を残す、ショートカット一覧に廃止キーを載せない(検証: C150 + 読み合わせ + C88〜C90) | met | observed 92: C150 の観測で、Cmd+3・Cmd+]・Cmd+[・Cmd+Ctrl+Opt+Shift+→↓ を押しても focus は 1 のままで、ショートカット一覧に ⌥⇥ · ⌥⇧⇥ と ⌘⌥矢印 があり Cmd+1〜9・Cmd+[ / Cmd+] は無かった。Config.zig の既定の読み合わせは周回 91(macOS 既定は ⌥⇥・⌥⇧⇥・⌘⌥矢印 の goto_project と ⌘⌃⇧矢印 の move_project だけ)、C88〜C90 は cycle 91 で exit 0 |
| C149 | 必須 | focus 移動(次・前・方向)と序数(10 番目以降を含む)のテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 91: just swift-test exit 0 (failed 0 件。ProjectFocusMoveTests 23 件は passed。項目 1・2・3 は ProjectFocusMoveTests(序数順の巡回と折り返し・Core → Side の順・hidden を飛ばす・10 番目以降・visible 1 で nil・5 種のオーバーレイで nil / zoom 中のペインの走査順の巡回と折り返し・zoom 対象不変・上流の goto_split:next と同順 / 横長型・縦長型の隣のプロジェクト・zoom 中の隣のペイン・隣が無ければ nil)、項目 4 は ProjectVisibleCapTests.everyVisibleProjectInPlacementOrderHasANumber・onlyAHiddenRowGoesWithoutANumber と WorkspaceStateTests.restoringNumbersEveryCappedVisibleProject) |
| C150 | 必須 | focus 移動のキーの統一と序数の実機観測(Opt+Tab の巡回と折り返し・zoom 中のペイン巡回・Cmd+Opt+矢印・廃止キーで移らない・10 番目以降の番号・一覧中は移らない・ショートカット一覧)(検証: 周回の実機観測) | met | observed 92: HEAD f7b3aa8 の zig-out 版で 7 項目すべて期待どおり(Opt+Tab 系の巡回と折り返し / zoom 中の 3 ペインの巡回と折り返し・zoom 対象不変 / Cmd+Opt+矢印 の隣と端 / Cmd+3・Cmd+] / Cmd+[・Cmd+Ctrl+Opt+Shift+矢印 で移らない / 10・11・12 の番号と hidden 行の番号なし / 一覧中は移らない / ショートカット一覧に Opt+Tab 系と Cmd+Opt+矢印 があり廃止キーなし)。画像と道具は .idd/tmp/c92/c150/ |
| C118 | 望ましい | マウスからノートを開く導線(検証: 人間) | unmet | - |
| C119 | 望ましい | ノート UI・プライマリー印の見た目の洗練(検証: 人間) | unmet | - |
| C120 | 望ましい | 全体ビューの非プライマリーペインのインジケータ(検証: 人間) | unmet | - |
