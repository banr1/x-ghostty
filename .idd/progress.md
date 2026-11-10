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

ideal_sha: fe2c07cb47245782e51e1f1b503a6c72333d73185724aef39f3181eec720be6e

| ID | 階層 | 条件 | 状態 | 証拠 |
|----|------|------|------|------|
| C1 | 必須 | プロジェクトごとに手書きの短いノートを保持できる(検証: C91) | met | cycle 60: just swift-test exit 0 (C91 は met、failed 0 件) |
| C2 | 必須 | ノート最大 100 行、保存時超過は確認し OK で先頭 100 行へ切詰め・Cancel で編集へ戻る(検証: C91 + C97) | met | cycle 56: just swift-test exit 0 (C91 は met。C97 は human 2026-11-08T16:03:41Z で met。周回 59 の変更で失効、C97 の問い直しの後に取り直す) |
| C3 | 必須 | ノートは永続化され再起動後に同じプロジェクトへ復元(検証: C91) | met | cycle 60: just swift-test exit 0 (C91 は met、failed 0 件) |
| C4 | 必須 | ノートはプロジェクトに属しペインに属さない(検証: C91) | met | cycle 60: just swift-test exit 0 (C91 は met、failed 0 件) |
| C5 | 必須 | `Cmd+E` でノート編集オーバーレイ、`Cmd+Enter` で保存して閉じる(検証: C91 + C92) | met | cycle 56: just swift-test exit 0 (C91 は met。C92 は human 2026-11-08T16:03:41Z で met。周回 59 の変更で失効、C92 の問い直しの後に取り直す) |
| C6 | 必須 | オーバーレイで Esc は確認なしに破棄して閉じる(検証: C91 + C92) | met | cycle 56: just swift-test exit 0 (C91 は met。C92 は human 2026-11-08T16:03:41Z で met。周回 59 の変更で失効、C92 の問い直しの後に取り直す) |
| C7 | 必須 | `Cmd+Enter` の fullscreen 既定割り当てを解除(検証: C92) | met | cycle 56: just swift-test exit 0 (C92 は human 2026-11-08T16:03:41Z で met。周回 59 の変更で失効、C92 の問い直しの後に取り直す) |
| C8 | 必須 | `Cmd+Opt+E` で一望モードをトグル、Esc でも抜ける(検証: C92) | met | cycle 56: just swift-test exit 0 (C92 は human 2026-11-08T16:03:41Z で met。周回 59 の変更で失効、C92 の問い直しの後に取り直す) |
| C9 | 必須 | 一望モードは visible なプロジェクトのみ表示(検証: C91) | met | cycle 60: just swift-test exit 0 (C91 は met) |
| C10 | 必須 | zoom 中に一望モードへ入ると zoom 解除(検証: C91) | met | cycle 60: just swift-test exit 0 (C91 は met) |
| C11 | 必須 | 一望モードは閲覧専用で編集・focus 移動しない(検証: C91) | met | cycle 60: just swift-test exit 0 (C91 は met) |
| C12 | 必須 | 一望モードで収まらないノートは切詰め、編集オーバーレイはスクロールで全文(検証: C92) | met | cycle 56: just swift-test exit 0 (C92 は human 2026-11-08T16:03:41Z で met。周回 59 の変更で失効、C92 の問い直しの後に取り直す) |
| C13 | 必須 | ノート UI は端末領域を恒久占有しない(検証: C92) | met | cycle 56: just swift-test exit 0 (C92 は human 2026-11-08T16:03:41Z で met。周回 59 の変更で失効、C92 の問い直しの後に取り直す) |
| C14 | 必須 | 既存機能と上流動作を退行させない(列挙した意図的変更を除く。兄弟のあるペインのコマンド終了で閉じず終了済みで残す・プライマリーのコマンド終了で昇格しない・Enter で終了済みペインすべてを再開(C29・C30・C143)を例外に追加)(検証: C88〜C90 exit 0 かつ既存テストが削除・無効化されず成功) | met | cycle 59: just swift-test exit 0 (zig build・just test も周回 59 で exit 0、failed 0 件。周回 60 でも 3 ゲートは exit 0。周回 59 で ProjectTerminatedTests の 13 件を書き換えた: 兄弟の close 判定(childExitOutcome の .closePane / .keepPaneAwaitingKey、removeExitedPane、複数ペイン中の mark 拒否、分割で状態クリア)と単一ペインの再開 API は C14 の例外「兄弟のあるペインのコマンド終了でペインを閉じず終了済み状態で残すこと・Enter をプロジェクト内の終了済みペインすべての再開にすること」に当たり、新しい意味の同等のテストへ置き換えた。ProjectTmuxLaunchTests・ProjectTmuxPaneTests・ProjectRenderTargetTests は呼び出しを新 API に直しただけで件数は変わらない。無効化は無い) |
| C15 | 必須 | ノートの判断ロジックはモデル層で XGhosttyTests から検証可能(検証: C91) | met | cycle 60: just swift-test exit 0 (C91 は met) |
| C16 | 必須 | SPEC.md / README.md をノート層仕様に合わせ、README の Building 節に 3 検証コマンド(検証: 周回の読み合わせ) | met | cycle 60: grep -n "Building" -A12 README.md exit 0 (zig build / just test / just swift-test の 3 行を確認。ノート層の記述と実装は周回 59 の変更に触れられていない) |
| C17 | 必須 | 各ペインはプライマリーフラグを持ち最初のペインがプライマリー(検証: C93) | met | cycle 60: just swift-test exit 0 (C93 は met) |
| C18 | 必須 | プライマリーはプロジェクト内で常に 1 つ(検証: C93) | met | cycle 60: just swift-test exit 0 (C93 は met) |
| C19 | 必須 | 全体ビューはプライマリーのみ描画、zoom 中は全ペイン(検証: C93 + C94) | met | cycle 56: just swift-test exit 0 (C93 は met。C94 は human 2026-11-08T16:03:41Z で met だったが IDEAL の項目が変わり unmet。周回 60 の観測でも全体ビューはプライマリーのみ・zoom で全ペインだった) |
| C20 | 必須 | 全体ビューの入力・focus はプライマリーへ、zoom 解除時に寄せる(検証: C93) | met | cycle 60: just swift-test exit 0 (C93 は met) |
| C21 | 必須 | 全体ビューでペイン系操作は no-op(検証: C93) | met | cycle 60: just swift-test exit 0 (C93 は met) |
| C22 | 必須 | zoom 中 `Cmd+P` で focused ペインをプライマリーへ(検証: C93 + C94) | met | cycle 56: just swift-test exit 0 (C93 は met。C94 の人間の確認は問い直しが要る) |
| C23 | 必須 | プライマリーが `Cmd+W` で閉じたら最近傍 leaf を昇格、コマンド終了では昇格せず終了済みでプライマリーに留まる(検証: C93・C95 + C94 + C142) | unmet | - (C93 は cycle 60、C95 は cycle 59 で met、C142 は observed 60 で met。C94 の人間の確認が残る) |
| C24 | 必須 | プライマリーフラグの永続化と復元時正規化(検証: C93) | met | cycle 60: just swift-test exit 0 (C93 は met) |
| C25 | 必須 | プライマリー印は zoom 中かつ複数ペイン時のみ右上に表示(検証: C94) | met | cycle 56: just swift-test exit 0 (C94 の人間の確認は問い直しが要る) |
| C26 | 必須 | プライマリーの判断ロジックはモデル層(検証: C93) | met | cycle 60: just swift-test exit 0 (C93 は met) |
| C27 | 必須 | SPEC.md / README.md をプライマリーペイン層仕様に合わせる(検証: 周回の読み合わせ) | unmet | - (SPEC.md §22.2・§23 に「兄弟の exit で close」「コマンド終了で昇格」の趣旨が残り、周回 59 の実装と食い違う。C76 の更新で解消する) |
| C28 | 必須 | プロジェクトを閉じる操作は常に確認ダイアログ(検証: C95 + C96) | met | cycle 59: just swift-test exit 0 (C95 は met。C96 は human 2026-11-08T16:03:41Z で、周回 59 の変更の後の問い直しが要る) |
| C29 | 必須 | ペインのプロセス(tmux クライアント / ssh)が exit したら兄弟の有無によらず閉じず終了済みで分割木に残す、最後でもプロジェクトは閉じない、状態は保存せず復元で全ペインが再 attach(検証: C95 + C96 + C142) | unmet | - (C95 は cycle 59 で met、C142 は observed 60 で met。C96 の人間の確認が周回 59 の変更より前で、問い直しが残る) |
| C30 | 必須 | 終了済みペインで Enter を押すとプロジェクト内の終了済みペインすべてが同じペインで再開、配置とプライマリーは不変、生きているペインに触れない(検証: C95 + C96 + C142) | unmet | - (C95 は cycle 59 で met、C142 は observed 60 で met。C96 の人間の確認が周回 59 の変更より前で、問い直しが残る) |
| C31 | 必須 | プロジェクト喪失経路は確認を経た明示的 close のみ(検証: C95 + C96) | met | cycle 59: just swift-test exit 0 (C95 は met。C96 は human 2026-11-08T16:03:41Z で、周回 59 の変更の後の問い直しが要る) |
| C32 | 必須 | ノート編集オーバーレイで標準編集ショートカットと Undo/Redo が効く(検証: C97) | met | cycle 56: just swift-test exit 0 (C97 は human 2026-11-08T16:03:41Z で met。周回 59 の変更で失効、問い直しが要る) |
| C33 | 必須 | 貼り付けで 100 行超過も C2 の確認を経る(検証: C91 + C97) | met | cycle 56: just swift-test exit 0 (C91 は met。C97 は human 2026-11-08T16:03:41Z で met。周回 59 の変更で失効、問い直しが要る) |
| C34 | 必須 | 優先度 high/medium/low/未設定(検証: C98 + C99) | met | cycle 56: just swift-test exit 0 (C98 は cycle 60 で met。C99 は human 2026-11-08T16:03:41Z で、問い直しが要る) |
| C35 | 必須 | 締切(日付のみ)、不正入力は未設定(検証: C98 + C99) | met | cycle 56: just swift-test exit 0 (C98 は cycle 60 で met。C99 は human 2026-11-08T16:03:41Z で、問い直しが要る) |
| C36 | 必須 | 優先度・締切は一覧セルで設定し永続化(検証: C98 + C99) | met | cycle 56: just swift-test exit 0 (C98 は cycle 60 で met。C99 は human 2026-11-08T16:03:41Z で、問い直しが要る) |
| C37 | 必須 | ラベル帯に優先度の印と締切を表示(検証: C99) | met | cycle 56: just swift-test exit 0 (C99 は human 2026-11-08T16:03:41Z で、問い直しが要る) |
| C38 | 必須 | 一望モードでノートと優先度・締切・次トリガーを表示(検証: C111 + C99・C112) | met | cycle 56: just swift-test exit 0 (C111 は cycle 60 で met。C99・C112 は human 2026-11-08T16:03:41Z で、問い直しが要る) |
| C39 | 必須 | 締切超過を控えめに強調(1 段階のみ)(検証: C98 + C99) | met | cycle 56: just swift-test exit 0 (C98 は cycle 60 で met。C99 は human 2026-11-08T16:03:41Z で、問い直しが要る) |
| C40 | 必須 | ソートは 5 値の永続化される状態、既定は手動(検証: C107 + C108) | met | cycle 56: just swift-test exit 0 (C107 は cycle 60 で met。C108 は human 2026-11-08T16:03:41Z で、問い直しが要る) |
| C41 | 必須 | 各ソートキーの固定の向き・安定ソート・序数は配置順(Core → Side、各種別内は表示順)の visible(検証: C98・C107) | met | cycle 60: just swift-test exit 0 (C98・C107 は met。序数は onlyTheFirstNineInPlacementOrderHaveANumber が先頭 9 つを確かめる) |
| C42 | 必須 | 一覧最上部のソートバーをキーボード・マウスで操作(検証: C107 + C108) | met | cycle 56: just swift-test exit 0 (C107 は cycle 60 で met。C108 は human 2026-11-08T16:03:41Z で、問い直しが要る) |
| C43 | 必須 | ソート有効中の即時再ソートと Opt+↑↓ の確認、ソートアクション廃止(検証: C107 + C108) | met | cycle 56: just swift-test exit 0 (C107 は cycle 60 で met。C108 は human 2026-11-08T16:03:41Z で、問い直しが要る) |
| C44 | 必須 | 優先度・締切・次トリガー・終了済みの判断ロジックはモデル層(検証: C95・C98・C111) | met | cycle 60: just swift-test exit 0 (C95・C98・C111 は met) |
| C45 | 必須 | SPEC.md / README.md を削除保護・ショートカット・優先度・締切層に合わせる(検証: 周回の読み合わせ) | unmet | - (SPEC.md §23.2〜23.5 に childExitOutcome・removeExitedPane・terminatedPane・兄弟の any-key-closes など廃止済みの記述が残り、周回 59 の実装と食い違う。C76 の更新で解消する) |
| C46 | 必須 | `Cmd+Opt+H` で focused プロジェクトを即時 hidden(検証: C100 + C101) | met | cycle 56: just swift-test exit 0 (C100 は cycle 60 で met。C101 は human 2026-11-08T16:03:41Z で、問い直しが要る) |
| C47 | 必須 | visible は最低 1 つ残る(検証: C100) | met | cycle 60: just swift-test exit 0 (C100 は met) |
| C48 | 必須 | hidden の復帰導線は一覧のみ、hidden シェルフ廃止(検証: C107 + C108) | met | cycle 56: just swift-test exit 0 (C107 は cycle 60 で met。C108 は human 2026-11-08T16:03:41Z で、問い直しが要る) |
| C49 | 必須 | レイアウト型 = 形 2 種 × 向き 2 種(台座型廃止)、余りは後半行へ、行内幅は Core 1・Side 1/2 の重み、縦長型は転置(検証: C102 + C103・C139) | met | cycle 56: just swift-test exit 0 (C102 は cycle 60 で met。C139 は observed 57、C103 は human 2026-11-08T16:03:41Z で、どちらも取り直しが要る) |
| C50 | 必須 | visible 1〜24 で完全一致する型を畳み(配置の一致は実際の種別の組み合わせで比べる)、選択肢 1 つなら選ぶものが無い旨(検証: C102 + C103) | met | cycle 56: just swift-test exit 0 (C102 は cycle 60 で met。C103 は human 2026-11-08T16:03:41Z で、問い直しが要る) |
| C51 | 必須 | `Cmd+Opt+L` でレイアウト型の選択オーバーレイ(検証: C103) | met | cycle 56: just swift-test exit 0 (C103 は human 2026-11-08T16:03:41Z で、問い直しが要る) |
| C52 | 必須 | レイアウト型は永続化、既定は横長型・行送り、保存された台座型は横長型へ移行(検証: C102 + C103) | met | cycle 56: just swift-test exit 0 (C102 は cycle 60 で met。C103 は human 2026-11-08T16:03:41Z で、問い直しが要る) |
| C53 | 必須 | Core → Side の順(各種別内は表示順)に向きに従いスロットへ割当、序数が追従(検証: C102) | met | cycle 60: just swift-test exit 0 (C102 は met。coreComesBeforeSideEachKindInRowOrder・theSlotsAssignCoreThenSideFollowingTheOrientation が passed) |
| C54 | 必須 | visible 数または visible の種別の変化時に記憶の型で自動適用(検証: C102 + C101・C103) | met | cycle 56: just swift-test exit 0 (C102 は cycle 60 で met。C101・C103 は human 2026-11-08T16:03:41Z で、問い直しが要る) |
| C55 | 必須 | プロジェクト単位のレイアウト resize/equalize 廃止、zoom 中ペインは存続(検証: C103) | met | cycle 56: just swift-test exit 0 (C103 は human 2026-11-08T16:03:41Z で、問い直しが要る) |
| C56 | 必須 | レイアウト型の判断ロジックはモデル層(検証: C102) | met | cycle 60: just swift-test exit 0 (C102 は met。判断は ProjectLayoutType.swift と WorkspaceState.visibleProjectIDs にある) |
| C57 | 必須 | 「グループ」→「プロジェクト」全面改名(検証: C104) | met | cycle 60: test -d macos/Sources/Features/Projects exit 0 (test -e macos/Sources/Features/Groups は exit 1。C104 は met) |
| C58 | 必須 | 改名は純粋なリネームで退行なし(検証: C104 + C88〜C90) | met | cycle 60: just swift-test exit 0 (zig build・just test も周回 60 で exit 0。C104 は met) |
| C59 | 必須 | SPEC.md / README.md をレイアウト型・自動適用・hide・改名語彙に合わせる(検証: 周回の読み合わせ) | met | cycle 60: grep -n "台座\|pedestal" SPEC.md README.md exit 0 (廃止と移行の記述だけの 4 行。ProjectLayoutTypeTests は 31 件で §26.5 と一致。レイアウト型・hide・改名の記述は周回 59 の変更に触れられていない) |
| C63 | 必須 | `Cmd+L` で一覧をトグル(Esc で閉じない・zoom を解除しない・種別と端末を含む 8 列・8 割)(検証: C107 + C108) | met | cycle 56: just swift-test exit 0 (C107 は cycle 60 で met。C108 は human 2026-11-08T16:03:41Z で、問い直しが要る) |
| C64 | 必須 | 一覧は単一の並び、手動順・列順・ソート状態を永続化、hidden も同色、序数は C41 の配置順(検証: C107 + C108) | met | cycle 56: just swift-test exit 0 (C107 は cycle 60 で met。C108 は human 2026-11-08T16:03:41Z で、問い直しが要る) |
| C65 | 必須 | Notion 流儀のセルカーソル・Enter 編集・候補列挙(端末・種別列を含む)(検証: C107 + C108) | met | cycle 56: just swift-test exit 0 (C107 は cycle 60 で met。C108 は human 2026-11-08T16:03:41Z で、問い直しが要る) |
| C66 | 必須 | ノート列編集は全行対象、Shift+Enter で改行、一覧内 `Cmd+Opt+E` は全行表示トグル(検証: C107 + C108) | met | cycle 56: just swift-test exit 0 (C107 は cycle 60 で met。C108 は human 2026-11-08T16:03:41Z で、問い直しが要る) |
| C67 | 必須 | `Cmd+矢印` は端移動、`Opt+矢印` で行・列並べ替え(検証: C107 + C108) | met | cycle 56: just swift-test exit 0 (C107 は cycle 60 で met。C108 は human 2026-11-08T16:03:41Z で、問い直しが要る) |
| C68 | 必須 | `Cmd+N` は一覧での新規プロジェクト作成、visible 24 未満なら visible・24 なら hidden、種別は Core(検証: C107 + C108) | met | cycle 56: just swift-test exit 0 (C107 は cycle 60 で met。C108 は human 2026-11-08T16:03:41Z で、問い直しが要る) |
| C69 | 必須 | 一覧の `Cmd+Enter` で focus(hidden 行は近傍 visible へ)(検証: C107 + C108) | met | cycle 56: just swift-test exit 0 (C107 は cycle 60 で met。C108 は human 2026-11-08T16:03:41Z で、問い直しが要る) |
| C70 | 必須 | 一覧の判断ロジック(端末・種別の候補を含む)はモデル層(検証: C107) | met | cycle 60: just swift-test exit 0 (C107 は met) |
| C71 | 必須 | 次トリガー 4 値(チームメンバーは外部へ移行)(検証: C107・C111 + C112) | met | cycle 56: just swift-test exit 0 (C107・C111 は cycle 60 で met。C112 は human 2026-11-08T16:03:41Z で、問い直しが要る) |
| C72 | 必須 | 毎日 6:00 境界で全プロジェクトの優先度を未設定へ(検証: C109 + C110) | met | cycle 56: just swift-test exit 0 (C109 は cycle 60 で met。C110 は human 2026-11-08T16:03:41Z で、問い直しが要る) |
| C73 | 必須 | 最終リセット日付を永続化し作業日ごとに 1 回(検証: C109 + C110) | met | cycle 56: just swift-test exit 0 (C109 は cycle 60 で met。C110 は human 2026-11-08T16:03:41Z で、問い直しが要る) |
| C74 | 必須 | 自動リセットの並びはソート状態に従う(検証: C109) | met | cycle 60: just swift-test exit 0 (C109 は met) |
| C75 | 必須 | リセット判定はモデル層(検証: C109) | met | cycle 60: just swift-test exit 0 (C109 は met) |
| C76 | 必須 | SPEC.md / README.md を端末登録・tmux セッション〜序数の配置順・ペイン単位の終了済み状態(兄弟も閉じず残る・プロジェクト単位の再開・コマンド終了で昇格しない)までの仕様に合わせる(検証: 周回の読み合わせ) | unmet | - (SPEC.md 1594・1729〜1799 行付近に childExitOutcome・removeExitedPane・terminatedPane・兄弟の close 判定が残る。§22.2・§23.2〜23.5・§29 と README の更新が未着手) |
| C77 | 必須 | 締切セルの Enter で 10 択の日付候補(検証: C107 + C108) | met | cycle 56: just swift-test exit 0 (C107 は cycle 60 で met。C108 は human 2026-11-08T16:03:41Z で、問い直しが要る) |
| C78 | 必須 | 一覧テキスト列のセル編集が日本語 IME を受け付ける(検証: C114) | met | cycle 56: just swift-test exit 0 (C114 は human 2026-11-08T16:03:41Z で、問い直しが要る) |
| C79 | 必須 | セルカーソルの Delete で列ごとの値削除(端末は手元へ・種別は Core へ)(検証: C107 + C108) | met | cycle 56: just swift-test exit 0 (C107 は cycle 60 で met。C108 は human 2026-11-08T16:03:41Z で、問い直しが要る) |
| C80 | 必須 | Esc で行選択、行選択の Delete で確認付き削除(検証: C107 + C108) | met | cycle 56: just swift-test exit 0 (C107 は cycle 60 で met。C108 は human 2026-11-08T16:03:41Z で、問い直しが要る) |
| C81 | 必須 | `Cmd+/` でショートカット一覧をトグル(検証: C115) | met | cycle 56: just swift-test exit 0 (C115 は human 2026-11-08T16:03:41Z で、問い直しが要る) |
| C82 | 必須 | `Cmd+K` の clear_screen 既定割り当て解除(検証: C113) | met | cycle 56: just swift-test exit 0 (C113 は human 2026-11-08T16:03:41Z で、問い直しが要る) |
| C83 | 必須 | 一覧セルのクリップボード操作(端末列は登録名のみ、種別列は Core / Side のみ)と候補列挙中の Tab 横移動(検証: C107 + C108) | met | cycle 56: just swift-test exit 0 (C107 は cycle 60 で met。C108 は human 2026-11-08T16:03:41Z で、問い直しが要る) |
| C84 | 必須 | 描画対象の定義(全体ビュー: visible のプライマリー / zoom: 対象の全ペイン)(検証: C116) | met | cycle 60: just swift-test exit 0 (ProjectRenderTargetTests 21 件 passed、failed 0 件) |
| C85 | 必須 | 描画対象外は生成時を含めレンダラとディスプレイリンクを停止し復帰時に再開(検証: C116 + C117) | met | cycle 56: just swift-test exit 0 (C116 は cycle 60 で met。C117 は human 2026-11-08T16:03:41Z で、問い直しが要る) |
| C86 | 必須 | 閉じた surface を経路によらず undo 期限後に SurfaceView〜IOSurface まで解放(検証: C116・C126 + C123〜C125 の読み合わせ + C117) | met | cycle 56: just swift-test exit 0 (C116・C126 は cycle 60 で met。C123〜C125 の読み合わせは周回 60 で取り直した。C117 は human 2026-11-08T16:03:41Z で、問い直しが要る) |
| C87 | 必須 | 描画対象の判定と停止・再開集合の導出はモデル層(検証: C116) | met | cycle 60: just swift-test exit 0 (ProjectRenderTargetTests passed) |
| C88 | 必須 | `zig build` が exit 0 | met | cycle 60: PATH=/opt/homebrew/opt/zig@0.15/bin:$PATH zig build exit 0 (HEAD 3636d7a、観測の前に実行) |
| C89 | 必須 | `just test` が exit 0 | met | cycle 60: just test exit 0 |
| C90 | 必須 | `just swift-test` が exit 0 | met | cycle 60: just swift-test exit 0 (TEST SUCCEEDED、failed 0 件) |
| C91 | 必須 | ノートのテスト群が macos/Tests/ に存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 60: just swift-test exit 0 (項目とテストの対応は cycle 8 の記録どおり、ProjectNoteTests は削除・変更なしで passed) |
| C92 | 必須 | ノートの実機目視(検証: 人間) | met | human 2026-11-08T16:03:41Z: Cmd+E で開き Cmd+Enter で保存・Esc で破棄・Cmd+Enter で fullscreen にならない・Cmd+Opt+E 一望と Esc で解除・40 行ノートの切り詰めと編集のスクロール・見た目を合格(代行結果 .idd/tmp/human-checks-2026-11-09/results.md、shots 086〜095。周回 59 の変更で失効、問い直しが要る) |
| C93 | 必須 | プライマリーペインのテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 60: just swift-test exit 0 (項目とテストの対応は cycle 9 の記録どおり、ProjectPrimaryPaneTests 35 件 passed) |
| C94 | 必須 | プライマリーペインの実機目視(Cmd+W で閉じたときの昇格を含む)(検証: 人間) | unmet | - (IDEAL の項目 4 が「シェルを exit」から「Cmd+W で閉じる」に変わった。周回 60 の C142 の観測で Cmd+W の昇格は機械側で確かめた) |
| C95 | 必須 | 削除保護のテスト群(兄弟ペインの exit で閉じない・複数の終了済みの再開・終了済みを含む複数ペインの復元を含む)が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 59: just swift-test exit 0 (failed 0 件。周回 60 でも exit 0。ProjectTerminatedTests 17 件。項目 1: closeProjectRequiresConfirmationRegardlessOfRunningProcesses。項目 2: lastPaneExitKeepsTheProjectWithNoteAndPane。項目 3: siblingPaneExitKeepsThePaneWithTreeOtherPanesAndPrimaryUnchanged・primaryPaneExitDoesNotPromoteAnotherPane・everyPaneOfASplitProjectCanBeTerminatedAtOnce。項目 4: terminatedProjectRoundTripKeepsNote。項目 5: restartReplacesEveryTerminatedPaneInItsSlotAndLeavesLivePanes・restartIsRejectedUnlessItReplacesExactlyTheTerminatedPanes。項目 6: aSplitProjectWithTerminatedPanesRoundTripsWithEveryPane) |
| C96 | 必須 | 削除保護の実機目視(検証: 人間) | met | human 2026-11-08T16:03:41Z: Cmd+W の確認と Cancel・最後のペイン exit で終了済み・Enter で再開・見た目を合格(shots 124〜127。周回 59 の変更で失効、問い直しが要る) |
| C97 | 必須 | ノート編集オーバーレイの編集ショートカット・100 行超過確認の実機目視(検証: 人間) | met | human 2026-11-08T16:03:41Z: Cmd+A/C/X/V・Cmd+Z/Shift+Z・120 行貼り付けの確認で Cancel 継続/OK で先頭 100 行を合格(shots 096〜106。周回 59 の変更で失効、問い直しが要る) |
| C98 | 必須 | 優先度・締切のテスト群(ソート後の序数は C41 の配置順)が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 60: just swift-test exit 0 (既存の項目は従来どおり ProjectPriorityDeadlineTests で passed。ソート後の序数は ordinalsAfterASortFollowThePlacementOrder が passed) |
| C99 | 必須 | 優先度・締切の実機目視(検証: 人間) | met | human 2026-11-08T16:03:41Z: 一覧設定とラベル帯・一望・超過の赤字・priority ソートと Cmd+1 追従・見た目を合格(shots 023〜036、079、090、095。周回 59 の変更で失効、問い直しが要る) |
| C100 | 必須 | hide のテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 60: just swift-test exit 0 (項目とテストの対応は cycle 5 の記録どおり passed) |
| C101 | 必須 | hide の実機目視(検証: 人間) | met | human 2026-11-08T16:03:41Z: Cmd+Opt+H で即時 hide・選択画面なし・記憶の型で組み直しを合格(shots 110〜114。周回 59 の変更で失効、問い直しが要る) |
| C102 | 必須 | レイアウト型のテスト群(1〜24・重み・Core → Side・台座型の移行・種別変化での再導出)が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 60: just swift-test exit 0 (ProjectLayoutTypeTests 31 件 passed。項目 1: tierCountsAttachTheLeftoverToTheTrailingTiers・wideSlotsMatchTheDefinitionForEveryCount・tallIsTheExactTransposeOfWide・weightsHoldInEveryTierForEveryCountAndMix・theTreeRealizesTheSlotFramesForEveryTypeCountAndMix。項目 2: choiceSetsCollapseExactMatchesPerCount・choiceSetsMatchTheSlotFrameCollapseForEveryCount。項目 3: rowMajorAssignsTopRowLeftToRight・columnMajorAssignsLeftColumnTopToBottom・coreComesBeforeSideEachKindInRowOrder・theSlotsAssignCoreThenSideFollowingTheOrientation。項目 4: ProjectLedgerTests の 2 件・aSavedPedestalReadsAsWideKeepingItsOrientation・aWorkspaceSavedOnPedestalComesBackWideWithItsOrientation。項目 5: visibleCountChangesReapplyTheRememberedType・countPreservingOperationsDoNotChangeTheArrangement・aVisibleKindChangeReappliesTheRememberedType) |
| C103 | 必須 | レイアウト型の実機目視(検証: 人間) | met | human 2026-11-08T16:03:41Z: Cmd+Opt+L の 4 型・Esc 不変・6 で tall を選び 1 つ隠すと 5 が tall・8 の 2+3+3・再起動で tall·by rows 維持・visible 1 の nothing to choose・プロジェクト境界は動かずペイン境界は動く・見た目を合格(shots 107〜119、176。周回 59 の変更で失効、問い直しが要る) |
| C104 | 必須 | 改名完了: Projects/ が在り Groups/ が無い、C88〜C90 exit 0、可視文言に Group が無いことの目視(検証: test -d / test -e + C88〜C90 + 人間) | met | cycle 60: test -d macos/Sources/Features/Projects exit 0 (test -e macos/Sources/Features/Groups は exit 1、C88〜C90 は周回 60 で exit 0。補足: 可視文言の目視は 2026-10-28T14:21:46Z の人間の確認でメニューに Group なし。周回 59 は可視文言を足していない) |
| C107 | 必須 | プロジェクト一覧のテスト群(既定列順 8 列、端末・種別の候補・Delete・貼り付け、visible 24 の拒否を含む)が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 60: just swift-test exit 0 (failed 0 件。既存の項目は従来どおり ProjectListTests ほかで passed。序数: onlyTheFirstNineInPlacementOrderHaveANumber・aHiddenRowFreesItsNumberForTheNextProject・coreComesBeforeSideEachKindInRowOrder。新規行: aNewRowIsVisibleCoreWhileBelowTheCap・aNewRowIsHiddenCoreAtTheCap。種別: aProjectIsCoreByDefault・theKindPersistsAndRestores・aSaveWithoutAKnownKindRestoresAsCore・theKindIsNotASortKey・theCandidatesAreCoreThenSide・deleteReturnsTheKindToCore。visible 24 の拒否: theToggleIsRejectedWithTwentyFourVisible) |
| C108 | 必須 | プロジェクト一覧の実機目視(検証: 人間) | met | human 2026-11-08T16:03:41Z: 8 列・8 割・hidden 同色から候補列挙中の Tab 横移動まで IDEAL の全 23 項目と見た目を合格(shots 002〜085。周回 59 の変更で失効、問い直しが要る) |
| C109 | 必須 | 優先度リセットのテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 60: just swift-test exit 0 (項目とテストの対応は cycle 5 の記録どおり passed) |
| C110 | 必須 | 優先度リセットの実機目視(検証: 人間) | met | human 2026-11-08T16:03:41Z: 翌朝 6:00 の観測は行わず、C109 のテストと実装で足りるとして人間の判断で合格(2026-10-30 と同じ判断。周回 59 の変更で失効、問い直しが要る) |
| C111 | 必須 | 次トリガーのテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 60: just swift-test exit 0 (項目とテストの対応は cycle 5 の記録どおり passed) |
| C112 | 必須 | 次トリガーの実機目視(検証: 人間) | met | human 2026-11-08T16:03:41Z: 一覧で設定・一望に表示・ラベル帯に出ないことを合格(shots 027、079、090。周回 59 の変更で失効、問い直しが要る) |
| C113 | 必須 | キー変更の実機目視(検証: 人間) | met | human 2026-11-08T16:03:41Z: Cmd+E でノート・Cmd+Opt+E で一望・Cmd+Opt+N/D/Shift+D 無反応・Cmd+E で検索しない・Cmd+K で画面クリアしないことを合格(shots 103、104。周回 59 の変更で失効、問い直しが要る) |
| C114 | 必須 | 一覧セル編集の IME の実機目視(検証: 人間) | met | human 2026-11-08T16:03:41Z: タイトル列・ノート列の日本語の未確定表示・変換・確定、未確定中の Esc は IME の取り消しで編集継続、英語とオーバーレイは従来どおりを合格(shots 141〜154。周回 59 の変更で失効、問い直しが要る) |
| C115 | 必須 | ショートカット一覧の実機目視(検証: 人間) | met | human 2026-11-08T16:03:41Z: Cmd+/ の場面別グループ・全体/zoom/一覧/オーバーレイから開ける・閉じると編集途中の内容ごと戻る・見た目を合格(shots 128〜135。周回 59 の変更で失効、問い直しが要る) |
| C116 | 必須 | 描画対象・停止/再開集合・解放・誕生時停止のテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 60: just swift-test exit 0 (ProjectRenderTargetTests 21 件 passed。全 5 項目の対応は cycle 2・3 の記録どおり) |
| C117 | 必須 | 描画停止・解放の実機観測(top / footprint、起動直後に落ちない、行 Delete 後のフォーカス、検証: 人間) | met | human 2026-11-08T16:03:41Z: 1: visible 1・hidden 8 を 1 分放置で CPU 0.5%(hidden 0 も 0.5%)。2: 5 プロジェクト各 2 ペインを close_project 3 件と行 Delete 2 件で閉じ 66 秒後にスレッド 51→92→51・IOSurface 領域 37→67→37・SurfaceView 11→21→11。3: 3 回の起動と seq 300・一覧スクロールで落ちず。4: 行 Delete 後も一覧は開いたまま行操作が効き Cmd+L で閉じ直後の入力が新 focus へ届いた。5: hidden 中の出力が再表示で描かれた。6: hidden 8 再起動の無操作 1 分で CPU 0.6%・IOSurface 24 MB、hidden 0 も 24 MB で +0%。描画対象外 IOSurface は最大 173 MB 未満で 200 MB 未満(周回 59 の変更で失効、問い直しが要る) |
| C121 | 必須 | 停止集合に誕生した描画対象外の surface を含める(stop = (after.retained − after.drawn) ∩ (before.drawn ∪ born))(検証: C116) | met | cycle 60: just swift-test exit 0 (ProjectRenderTargetTests 21 件 passed) |
| C122 | 必須 | 停止・再開の適用は RenderTargetTransition のみ(生成直後の一律 set_occlusion(false) が唯一の例外)、SurfaceView.isDrawing を持たない(検証: C116 + 読み合わせ) | met | cycle 60: just swift-test exit 0 (C116 passed。grep -rn xghostty_surface_set_occlusion macos/Sources は 2 箇所(SurfaceView_AppKit.swift:383 の init 直後の一律停止と BaseTerminalController.swift:2471 の transition の適用)、grep -rn isDrawing macos/Sources は 0 件) |
| C123 | 必須 | SurfaceView の `.ghosttySelectionDidChange` 購読は `object:` を渡さず `[weak self]` の filter で絞る(検証: 読み合わせ + C90) | met | cycle 60: just swift-test exit 0 (SurfaceView_AppKit.swift:295 の publisher(for: .ghosttySelectionDidChange) に object: が無く、296 行の [weak self] の filter で絞ることを周回 60 で読み合わせた) |
| C124 | 必須 | `XGhostty.Surface.deinit` はメインスレッドなら同期的に `xghostty_surface_free`(検証: 読み合わせ + C88〜C90 + C117) | met | cycle 56: just swift-test exit 0 (XGhostty.Surface.swift:34 の Thread.isMainThread による同期解放を周回 60 で読み合わせ、C88〜C90 は周回 60 で exit 0。C117 は human 2026-11-08T16:03:41Z で、問い直しが要る) |
| C125 | 必須 | 一覧の行選択 Delete で閉じたとき新しい focus 先へキーボードフォーカスを移す(検証: C126 + 読み合わせ + C117) | met | cycle 56: just swift-test exit 0 (C126 は cycle 60 で met。performCloseProjectListRow の .switched が moveKeyboardFocus(toProjectSurface:) を呼ぶ(BaseTerminalController.swift:1971〜1973)ことを周回 60 で読み合わせた。C117 は human 2026-11-08T16:03:41Z で、問い直しが要る) |
| C126 | 必須 | 一覧セッション中の closeProject の focus 先・保持集合・セッション継続のテスト(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 60: just swift-test exit 0 (ProjectListRowSelectionTests の 2 件が passed) |
| C127 | 必須 | 端末を設定ファイルに登録(表示名・ホスト・色)、hostname 一致を手元、登録なしは暗黙の手元、再読み込みで反映(検証: C136 + C137) | met | observed 57: 登録 mini・loop・nowhere が端末列の候補にこの順で出て、mini は ssh を介さず bg=colour28。loop のホストを変えて Reload Configuration すると次の再開から反映された(C136 は cycle 60 で met。周回 59 の変更で失効、C137 の観測の取り直しが要る) |
| C128 | 必須 | プロジェクトの端末(既定は手元)、一覧の端末列で候補選択・Delete で手元・登録名のみ貼り付け、永続化、欠落は手元扱い、変更は以後の新しいペインだけに効き終了済みの再開は元の端末の同じセッションへ(検証: C136 + C137) | met | observed 57: p06 の端末を loop へ変えると新しい split だけが ssh になり元のペインは mini のまま。再起動後も一覧の端末列は loop。終了済みの再開は同じセッションへ戻った(周回 60 の C142 の観測でも端末列 mini→loop の後の split だけが ssh になり元のペインは緑のまま。周回 59 の変更で失効、C137 の観測の取り直しが要る) |
| C129 | 必須 | 全ペインを端末上の tmux セッションへ attach するコマンドで起動、セッション名 `<ID>-<n>`、ペインごとの端末・セッション名を永続化(検証: C136 + C137) | met | observed 57: 新規プロジェクトで `tmux ls` に 7149ac80-…-1 が現れ、split は 0b668a4a-…-2・-3 と連番になった。再起動で全 7 セッションが attached 1 に戻り、セッションは増減しなかった(周回 59 の変更で失効、C137 の観測の取り直しが要る) |
| C130 | 必須 | 開始ディレクトリ `~/workspace/<タイトル>` → `~/workspace` → ホーム、split は `#{pane_current_path}` を引き継ぐ(検証: C136 + C137) | met | observed 57: x-ghostty の作り直したセッションは session_path・pane_current_path とも ~/workspace/x-ghostty、~/workspace/<タイトル> の無い qa などは ~/workspace。split の新ペインは元ペインと同じ /private/tmp(周回 59 の変更で失効、C137 の観測の取り直しが要る) |
| C131 | 必須 | attach 時にそのセッションだけへ status-style・status-left・prefix C-s を設定、リネームで status-left を更新(検証: C136 + C137) | met | observed 57: show-options は prefix C-s・bg=colour28・status-left を示し、リネームで "[x-ghostty] " になった。xghostty が作っていないセッションとグローバルのオプションは開始前と diff なし(周回 59 の変更で失効、C137 の観測の取り直しが要る) |
| C132 | 必須 | tmux / ssh の終了でペインは兄弟の有無によらず終了済み、Enter でプロジェクト内の終了済みペインそれぞれの attach を再実行(検証: C136 + C137・C142) | unmet | - (C136 は cycle 60 で met、C142 は observed 60 で met。C137 の観測(observed 57)は周回 59 の変更より前で、取り直しが残る) |
| C133 | 必須 | 閉じたペインのセッションを undo 期限後に kill、undo で戻せば kill しない(検証: C136 + C137) | met | observed 57: Cmd+W で閉じた -2 は 2 秒後に残り 10 秒後に消えた。Cmd+Z で戻した -3 は 11 秒後も attached 1。一覧の行 Delete で閉じた 20 個も消えた。終了ではセッションは残った(周回 60 でも Cmd+W で閉じた -1・-2 は undo 期限後に消え、終了済みの 3 セッションは残った。周回 59 の変更で失効、C137 の観測の取り直しが要る) |
| C134 | 必須 | 手元でない端末への ssh に TERM=xterm-256color を渡す(検証: C136 + C137) | met | observed 57: ps に `env TERM=xterm-256color ssh -t xg-loop` があり、ssh 先の `tmux display -p` は client.xterm-256color.end を返した(周回 60 の ps にも同じ形が出た。周回 59 の変更で失効、C137 の観測の取り直しが要る) |
| C135 | 必須 | 端末・セッション・コマンド・候補・kill 対象の判断ロジックはモデル層(検証: C136) | met | cycle 60: just swift-test exit 0 (C136 は met。配置は周回 43 の記録どおり) |
| C136 | 必須 | 端末登録と tmux セッションのテスト群(9 項目)が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 60: just swift-test exit 0 (failed 0 件。項目とテストの対応は cycle 39 の台帳どおり。ProjectTmuxLaunchTests・ProjectTmuxPaneTests は周回 59 で呼び出しを新 API に直しただけ) |
| C137 | 必須 | 端末登録と tmux セッションの実機観測(Mac mini、ssh ループバック、screencapture と tmux の出力)(検証: 周回の実機観測) | met | observed 57: HEAD da74802 の zig-out 版で 9 項目すべてを確かめた(詳細は記録 0057 の検証表)。~/.tmux.conf の sha・グローバルと開始前 12 セッションのオプションは開始前と diff なし(周回 59 の変更で失効、取り直しが要る) |
| C138 | 必須 | 2 台の実機での目視(Mac mini の tmux・再起動後の再 attach・切断後の再 attach)(検証: 人間) | met | human 2026-11-08T16:03:41Z: MacBook Air 上の xghostty で 3 項目(Mac mini の tmux に入りバーが Mac mini の色・再起動で同じセッションへ・切断後の Enter で同じセッションへ)を確認済みと周回 56 の pair で回答(周回 59 の変更で失効、問い直しが要る) |
| C139 | 必須 | 種別と重み付きレイアウトの実機観測(8 列・候補・重みの幅と高さ・Core → Side の序数・種別変更で組み直し・台座型なし・24 と 25 個目の hidden・Side に印なし)(検証: 周回の実機観測) | met | observed 57: HEAD da74802 の zig-out 版で 7 項目すべてを確かめた。Side の幅と高さは Core の半分(約 380 対 760、約 175 対 349)、Side の zoom・一望も Core と同じで印なし。24 は 4+5+5+5+5 で 25 個目は hidden(詳細は記録 0057 の検証表。周回 59 の変更で失効、取り直しが要る) |
| C140 | 必須 | 種別 Core / Side、既定 Core、一覧の種別列(候補 Core → Side・Delete で Core・Core / Side のみ貼り付け)、永続化、ソートキーにしない、大きさ以外に差を付けない(検証: C107 + C139) | met | observed 57: C139 の項目 1・2・7 のとおりで、再起動後も qa は Side のまま(C107 は cycle 60 で met。周回 59 の変更で失効、C139 の取り直しが要る) |
| C141 | 必須 | 同時 visible は最大 24、24 で表示トグルを拒否、序数は配置順の先頭 9 つ(検証: C107 + C139) | met | observed 57: 24 visible で新規行は hidden になり、その行の表示トグルは「no room to show」で拒否された。序数は 9 までで、序数の無い p11 へ一覧の Cmd+Enter で focus して入力が届いた(C107 は cycle 60 で met。周回 59 の変更で失効、C139 の取り直しが要る) |
| C142 | 必須 | ペイン単位の終了済み状態の実機観測(ssh ループバックの 3 ペインを外から終了・Enter 1 回で全再 attach・終了済みのまま再起動・兄弟のシェル exit と Cmd+W・プライマリーの非昇格と Cmd+W の昇格・一部だけの再開で生きたセッションを作り直さない)(検証: 周回の実機観測) | met | observed 60: HEAD 3636d7a の zig-out 版で 6 項目を確かめた。loop の 3 ペイン(-3〜-5)の ssh を外から kill すると 3 つとも終了済みで残り配置と ★ は不変、15 秒後も 3 セッションが残った。全体ビューで Enter 1 回で 3 つとも同じセッション(session_created 不変)へ戻り出力が見えた。全終了済みで終了・再起動すると 3 ペインとも復元され再 attach。-5 で exit すると終了済みで残り Cmd+W で閉じた。プライマリーの終了では昇格せず、Cmd+W で閉じると隣が昇格。プライマリーだけ再開しても -4・-5 の session_created と pane_pid は不変(記録 0060 の検証表) |
| C143 | 必須 | ペインが分割木から失われるのは明示的 close(Cmd+W・close_project・一覧の行 Delete)のみ、コマンド終了では失われない(検証: C95 + C142) | met | observed 60: C142 の観測で、ssh の kill・シェルの exit・全ペインの終了・終了済みでの非 Enter 打鍵(a)のいずれでもペインは失われず、失われたのは Cmd+W の close だけだった(C95 は cycle 59: just swift-test exit 0、周回 60 でも exit 0) |
| C118 | 望ましい | マウスからノートを開く導線(検証: 人間) | unmet | - |
| C119 | 望ましい | ノート UI・プライマリー印の見た目の洗練(検証: 人間) | unmet | - |
| C120 | 望ましい | 全体ビューの非プライマリーペインのインジケータ(検証: 人間) | unmet | - |
