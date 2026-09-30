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

ideal_sha: 17076ce6f2df32055db93cc9e2dbf4d97a23ecd099b636a036e27e20ef96be5c

| ID | 階層 | 条件 | 状態 | 証拠 |
|----|------|------|------|------|
| C1 | 必須 | プロジェクトごとに手書きの短いノートを保持できる(検証: C91) | met | cycle 11: just swift-test exit 0 (検証は C91 のテスト成功のみ。C91 は met、failed 0 件) |
| C2 | 必須 | ノート最大 100 行、保存時超過は確認し OK で先頭 100 行へ切詰め・Cancel で編集へ戻る(検証: C91 + C97) | unmet | - |
| C3 | 必須 | ノートは永続化され再起動後に同じプロジェクトへ復元(検証: C91) | met | cycle 11: just swift-test exit 0 (検証は C91 のテスト成功のみ。C91 は met、failed 0 件) |
| C4 | 必須 | ノートはプロジェクトに属しペインに属さない(検証: C91) | met | cycle 11: just swift-test exit 0 (検証は C91 のテスト成功のみ。C91 は met、failed 0 件) |
| C5 | 必須 | `Cmd+E` でノート編集オーバーレイ、`Cmd+Enter` で保存して閉じる(検証: C91 + C92) | unmet | - |
| C6 | 必須 | オーバーレイで Esc は確認なしに破棄して閉じる(検証: C91 + C92) | unmet | - |
| C7 | 必須 | `Cmd+Enter` の fullscreen 既定割り当てを解除(検証: C92) | unmet | - |
| C8 | 必須 | `Cmd+Opt+E` で一望モードをトグル、Esc でも抜ける(検証: C92) | unmet | - |
| C9 | 必須 | 一望モードは visible なプロジェクトのみ表示(検証: C91) | met | cycle 11: just swift-test exit 0 (検証は C91 のテスト成功のみ。C91 は met、failed 0 件) |
| C10 | 必須 | zoom 中に一望モードへ入ると zoom 解除(検証: C91) | met | cycle 11: just swift-test exit 0 (検証は C91 のテスト成功のみ。C91 は met、failed 0 件) |
| C11 | 必須 | 一望モードは閲覧専用で編集・focus 移動しない(検証: C91) | met | cycle 11: just swift-test exit 0 (検証は C91 のテスト成功のみ。C91 は met、failed 0 件) |
| C12 | 必須 | 一望モードで収まらないノートは切詰め、編集オーバーレイはスクロールで全文(検証: C92) | unmet | - |
| C13 | 必須 | ノート UI は端末領域を恒久占有しない(検証: C92) | unmet | - |
| C14 | 必須 | 既存機能と上流動作を退行させない(列挙した意図的変更を除く)(検証: C88〜C90 exit 0 かつ既存テストが削除・無効化されず成功) | met | cycle 4: just swift-test exit 0 (zig build・just test も exit 0。git diff -M 9cb808d HEAD で削除されたテスト・.swift/.zig ファイルは無く、.disabled / XCTSkip / SkipZigTest の追加も無い。テスト宣言数は 3642 → 3650) |
| C15 | 必須 | ノートの判断ロジックはモデル層で XGhosttyTests から検証可能(検証: C91) | met | cycle 11: just swift-test exit 0 (検証は C91 のテスト成功のみ。C91 は met、failed 0 件) |
| C16 | 必須 | SPEC.md / README.md をノート層仕様に合わせ、README の Building 節に 3 検証コマンド(検証: 周回の読み合わせ) | met | cycle 12: README Building 節に zig build / just test / just swift-test の 3 行があることを grep で確認 exit 0 (README About の Notes 項と SPEC §21 を ProjectState / WorkspaceModel / ProjectNoteEditor / ProjectNoteOverview / NoteEditHistory / Config.zig の既定キーと読み合わせ。食い違い 3 点 — テスト件数 44→45、削除済み締切フィールドへの言及、「プロジェクト(=プロジェクト)」— を SPEC §21 で直した) |
| C17 | 必須 | 各ペインはプライマリーフラグを持ち最初のペインがプライマリー(検証: C93) | met | cycle 11: just swift-test exit 0 (検証は C93 のテスト成功のみ。C93 は met、failed 0 件) |
| C18 | 必須 | プライマリーはプロジェクト内で常に 1 つ(検証: C93) | met | cycle 11: just swift-test exit 0 (検証は C93 のテスト成功のみ。C93 は met、failed 0 件) |
| C19 | 必須 | 全体ビューはプライマリーのみ描画、zoom 中は全ペイン(検証: C93 + C94) | unmet | - |
| C20 | 必須 | 全体ビューの入力・focus はプライマリーへ、zoom 解除時に寄せる(検証: C93) | met | cycle 11: just swift-test exit 0 (検証は C93 のテスト成功のみ。C93 は met、failed 0 件) |
| C21 | 必須 | 全体ビューでペイン系操作は no-op(検証: C93) | met | cycle 11: just swift-test exit 0 (検証は C93 のテスト成功のみ。C93 は met、failed 0 件) |
| C22 | 必須 | zoom 中 `Cmd+P` で focused ペインをプライマリーへ(検証: C93 + C94) | unmet | - |
| C23 | 必須 | プライマリーが閉じたら最近傍 leaf を昇格(検証: C93 + C94) | unmet | - |
| C24 | 必須 | プライマリーフラグの永続化と復元時正規化(検証: C93) | met | cycle 11: just swift-test exit 0 (検証は C93 のテスト成功のみ。C93 は met、failed 0 件) |
| C25 | 必須 | プライマリー印は zoom 中かつ複数ペイン時のみ右上に表示(検証: C94) | unmet | - |
| C26 | 必須 | プライマリーの判断ロジックはモデル層(検証: C93) | met | cycle 11: just swift-test exit 0 (検証は C93 のテスト成功のみ。C93 は met、failed 0 件) |
| C27 | 必須 | SPEC.md / README.md をプライマリーペイン層仕様に合わせる(検証: 周回の読み合わせ) | met | cycle 13: grep -c "@Test" macos/Tests/Projects/ProjectPrimaryPaneTests.swift exit 0 (35 件で SPEC §22.8 と一致。README About の Primary panes 項と SPEC §22 を ProjectState / SplitTree.nearestLeaf / WorkspaceState / WorkspaceModel / BaseTerminalController / XGhostty.App / ProjectView / TerminalSplitTreeView / Config.zig の Cmd+P と読み合わせ。食い違い 3 点 — 冒頭のテスト節参照 §22.7→§22.8、最後のペイン close の旧記述(削除保護 §23 と矛盾)、snapFocusToPrimaryInOverallView の呼び出し元列挙の不足 — を SPEC §22 で直した) |
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
| C41 | 必須 | 各ソートキーの固定の向き・安定ソート・序数は visible 行の表示順(検証: C98・C107) | met | cycle 11: just swift-test exit 0 (検証は C98・C107 のテスト成功のみ。C98・C107 は met、failed 0 件) |
| C42 | 必須 | 一覧最上部のソートバーをキーボード・マウスで操作(検証: C107 + C108) | unmet | - |
| C43 | 必須 | ソート有効中の即時再ソートと Opt+↑↓ の確認、ソートアクション廃止(検証: C107 + C108) | unmet | - |
| C44 | 必須 | 優先度・締切・次トリガー・終了済みの判断ロジックはモデル層(検証: C95・C98・C111) | met | cycle 11: just swift-test exit 0 (検証は C95・C98・C111 のテスト成功のみ。C95・C98・C111 は met、failed 0 件) |
| C45 | 必須 | SPEC.md / README.md を削除保護・ショートカット・優先度・締切層に合わせる(検証: 周回の読み合わせ) | met | cycle 14: grep -c "@Test" (ProjectTerminatedTests / ProjectPriorityDeadlineTests / ProjectSortStateTests / ProjectNextTriggerTests) exit 0 (16 / 18 / 13 / 7 件で SPEC §23.5・§24.5・§24.6 と一致。SPEC §23・§24・§10 と README の Deletion protection / Priorities 項を WorkspaceModel / ProjectState / ProjectLabel / ProjectListOverlay / BaseTerminalController / Surface.zig / Config.zig の既定キーと読み合わせ。食い違い — §23.1 の closeFocusedProject の説明、§23.4・README の喪失経路に一覧の行選択 Delete が無い点 — を直し、ソース内コメントの §24.5 参照(ソート状態は §24.4)も直した) |
| C46 | 必須 | `Cmd+Opt+H` で focused プロジェクトを即時 hidden(検証: C100 + C101) | unmet | - |
| C47 | 必須 | visible は最低 1 つ残る(検証: C100) | met | cycle 11: just swift-test exit 0 (検証は C100 のテスト成功のみ。C100 は met、failed 0 件) |
| C48 | 必須 | hidden の復帰導線は一覧のみ、hidden シェルフ廃止(検証: C107 + C108) | unmet | - |
| C49 | 必須 | レイアウト型 = 形 3 種 × 向き 2 種、余りは後半行へ(検証: C102 + C103) | unmet | - |
| C50 | 必須 | 完全一致する型を畳み、選択肢 1 つなら選ぶものが無い旨(検証: C102 + C103) | unmet | - |
| C51 | 必須 | `Cmd+Opt+L` でレイアウト型の選択オーバーレイ(検証: C103) | unmet | - |
| C52 | 必須 | レイアウト型は永続化、既定は横長型・行送り(検証: C102 + C103) | unmet | - |
| C53 | 必須 | 表示順のまま向きに従いスロットへ割当、序数が追従(検証: C102) | met | cycle 11: just swift-test exit 0 (検証は C102 のテスト成功のみ。C102 は met、failed 0 件) |
| C54 | 必須 | visible 数変化時に記憶の型で自動適用(検証: C102 + C101・C103) | unmet | - |
| C55 | 必須 | プロジェクト単位のレイアウト resize/equalize 廃止、zoom 中ペインは存続(検証: C103) | unmet | - |
| C56 | 必須 | レイアウト型の判断ロジックはモデル層(検証: C102) | met | cycle 11: just swift-test exit 0 (検証は C102 のテスト成功のみ。C102 は met、failed 0 件) |
| C57 | 必須 | 「グループ」→「プロジェクト」全面改名(検証: C104) | unmet | - |
| C58 | 必須 | 改名は純粋なリネームで退行なし(検証: C104 + C88〜C90) | unmet | - |
| C59 | 必須 | SPEC.md / README.md をレイアウト型・自動適用・hide・改名語彙に合わせる(検証: 周回の読み合わせ) | unmet | - |
| C60 | 必須 | リモートペインの split は同ホスト・同パスへ ssh(検証: C105 + C106) | unmet | - |
| C61 | 必須 | リモート判定不能・接続失敗はローカルで開く(検証: C105 + C106) | unmet | - |
| C62 | 必須 | リモート判定はモデル層(検証: C105) | met | cycle 11: just swift-test exit 0 (検証は C105 のテスト成功のみ。C105 は met、failed 0 件) |
| C63 | 必須 | `Cmd+L` で一覧をトグル(Esc で閉じない・zoom を解除しない・6 列・8 割)(検証: C107 + C108) | unmet | - |
| C64 | 必須 | 一覧は単一の並び、手動順・列順・ソート状態を永続化、hidden も同色(検証: C107 + C108) | unmet | - |
| C65 | 必須 | Notion 流儀のセルカーソル・Enter 編集・候補列挙(検証: C107 + C108) | unmet | - |
| C66 | 必須 | ノート列編集は全行対象、Shift+Enter で改行、一覧内 `Cmd+Opt+E` は全行表示トグル(検証: C107 + C108) | unmet | - |
| C67 | 必須 | `Cmd+矢印` は端移動、`Opt+矢印` で行・列並べ替え(検証: C107 + C108) | unmet | - |
| C68 | 必須 | `Cmd+N` は一覧での新規プロジェクト作成(検証: C107 + C108) | unmet | - |
| C69 | 必須 | 一覧の `Cmd+Enter` で focus(hidden 行は近傍 visible へ)(検証: C107 + C108) | unmet | - |
| C70 | 必須 | 一覧の判断ロジックはモデル層(検証: C107) | met | cycle 11: just swift-test exit 0 (検証は C107 のテスト成功のみ。C107 は met、failed 0 件) |
| C71 | 必須 | 次トリガー 4 値(チームメンバーは外部へ移行)(検証: C107・C111 + C112) | unmet | - |
| C72 | 必須 | 毎日 6:00 境界で全プロジェクトの優先度を未設定へ(検証: C109 + C110) | unmet | - |
| C73 | 必須 | 最終リセット日付を永続化し作業日ごとに 1 回(検証: C109 + C110) | unmet | - |
| C74 | 必須 | 自動リセットの並びはソート状態に従う(検証: C109) | met | cycle 11: just swift-test exit 0 (検証は C109 のテスト成功のみ。C109 は met、failed 0 件) |
| C75 | 必須 | リセット判定はモデル層(検証: C109) | met | cycle 11: just swift-test exit 0 (検証は C109 のテスト成功のみ。C109 は met、failed 0 件) |
| C76 | 必須 | SPEC.md / README.md をリモート split〜描画停止までの仕様に合わせる(検証: 周回の読み合わせ) | unmet | - |
| C77 | 必須 | 締切セルの Enter で 10 択の日付候補(検証: C107 + C108) | unmet | - |
| C78 | 必須 | 一覧テキスト列のセル編集が日本語 IME を受け付ける(検証: C114) | unmet | - |
| C79 | 必須 | セルカーソルの Delete で列ごとの値削除(検証: C107 + C108) | unmet | - |
| C80 | 必須 | Esc で行選択、行選択の Delete で確認付き削除(検証: C107 + C108) | unmet | - |
| C81 | 必須 | `Cmd+/` でショートカット一覧をトグル(検証: C115) | unmet | - |
| C82 | 必須 | `Cmd+K` の clear_screen 既定割り当て解除(検証: C113) | unmet | - |
| C83 | 必須 | 一覧セルのクリップボード操作と候補列挙中の Tab 横移動(検証: C107 + C108) | unmet | - |
| C84 | 必須 | 描画対象の定義(全体ビュー: visible のプライマリー / zoom: 対象の全ペイン)(検証: C116) | met | cycle 2: just swift-test exit 0 (ProjectRenderTargetTests 17 件 passed) |
| C85 | 必須 | 描画対象外は生成時を含めレンダラとディスプレイリンクを停止し復帰時に再開(検証: C116 + C117) | unmet | - |
| C86 | 必須 | 閉じた surface とレンダラ・スレッドを解放(検証: C116 + C117) | unmet | - |
| C87 | 必須 | 描画対象の判定と停止・再開集合の導出はモデル層(検証: C116) | met | cycle 2: just swift-test exit 0 (ProjectRenderTargetTests 17 件 passed) |
| C88 | 必須 | `zig build` が exit 0 | met | cycle 4: PATH=/opt/homebrew/opt/zig@0.15/bin:$PATH zig build exit 0 |
| C89 | 必須 | `just test` が exit 0 | met | cycle 4: just test exit 0 |
| C90 | 必須 | `just swift-test` が exit 0 | met | cycle 4: just swift-test exit 0 |
| C91 | 必須 | ノートのテスト群が macos/Tests/ に存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 8: just swift-test exit 0 (ProjectNoteTests の 保存復元 = codableRoundTripRestoresNoteText、100 行以内 = normalizedNoteKeepsExactlyOneHundredLines / noteWithinLimitIsNotJudgedOver / endNoteEditingKeepsANoteOfExactlyOneHundredLinesVerbatim、超過と切詰め = noteOverLimitIsJudgedOverAndTruncationKeepsFirstOneHundred、保存して閉じる = endNoteEditingSavesDraftAndCloses、破棄 = cancelNoteEditingKeepsPreOpenTextAndCloses、一望の表示集合 = overviewDisplaySetIsExactlyTheVisibleProjects / …ExcludesHiddenProjects、zoom 解除 = enteringOverviewReleasesZoom、閲覧専用 = overviewBlocksNoteEditing / …DirectionalFocusMoves / …IndexFocusMoves / …FocusSwitch がすべて passed) |
| C92 | 必須 | ノートの実機目視(検証: 人間) | unmet | - |
| C93 | 必須 | プライマリーペインのテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 9: just swift-test exit 0 (ProjectPrimaryPaneTests の 初期ペイン = initialPaneOfNewProjectIsPrimary、後続分割と一意性 = laterSplitPanesAreNotPrimary / setPrimaryPaneMovesFlagAndDemotesFormerPrimary、保存復元と正規化 = saveRestoreRoundTripKeepsPrimaryOnSamePane / decodeNormalizesZeroPrimariesToFirstLeaf / …MultiplePrimariesToOne / …DanglingPrimaryToFirstLeaf、最近傍昇格 = primaryCloseProotesNearestLeaf / …InDeepTree、全体ビューの描画対象 = overallViewDisplaySetIsEachVisibleProjectsPrimaryOnly、ペイン操作 no-op = paneOperationsAreEnabledOnlyWhileTheFocusedProjectIsZoomed / …DisabledWhenTheZoomedProjectIsNotFocused(split・focus・zoom・resize・equalize の各 action が BaseTerminalController でこの判定に guard することを読み合わせ)、zoom 解除時の focus = zoomReleaseSnapsFocusToPrimary、set_primary = setPrimaryWhileZoomedMovesFlagToFocusedPane がすべて passed) |
| C94 | 必須 | プライマリーペインの実機目視(検証: 人間) | unmet | - |
| C95 | 必須 | 削除保護のテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 6: just swift-test exit 0 (ProjectTerminatedTests の closeProjectRequiresConfirmationRegardlessOfRunningProcesses / lastPaneExitIsJudgedTerminatedForEveryExitKind + markPaneTerminatedKeepsProjectWithNoteAndPane / siblingPaneNormalExitIsJudgedClosePane + removeExitedPaneClosesOnlyThatPane / terminatedProjectRoundTripKeepsNote が passed) |
| C96 | 必須 | 削除保護の実機目視(検証: 人間) | unmet | - |
| C97 | 必須 | ノート編集オーバーレイの編集ショートカット・100 行超過確認の実機目視(検証: 人間) | unmet | - |
| C98 | 必須 | 優先度・締切のテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 6: just swift-test exit 0 (ProjectPriorityDeadlineTests の priorityAndDeadlineRoundTripThroughSaveRestore / invalidDeadlineInputIsRejectedToUnset / prioritySortOrders… + deadlineSortOrders… + sortOrderingsCoverAllRowsAndMutateNothing(hidden を含む) / postSortOrdinalsCountVisibleRowsSkippingHidden / overdueIsStrictlyPastTheDeadlineDay が passed) |
| C99 | 必須 | 優先度・締切の実機目視(検証: 人間) | unmet | - |
| C100 | 必須 | hide のテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 5: just swift-test exit 0 (WorkspaceModelTests.hideFocusedProjectHidesAndMovesFocusToNeighbor / hideFocusedProjectRejectsLastVisibleProject、ProjectListTests.hidingTheLastVisibleProjectIsRefused が passed) |
| C101 | 必須 | hide の実機目視(検証: 人間) | unmet | - |
| C102 | 必須 | レイアウト型のテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 7: just swift-test exit 0 (スロット計算 = ProjectLayoutTypeTests の tierCounts… / wideSlots… / tallIsTheExactTransposeOfWide / wideOrientation… / pedestalStacks…、選択肢の畳み込み = choiceSetsCollapseExactMatchesPerCount + choiceSetsMatchTheSlotFrameCollapseForEveryCount(n=1〜9)、割当と序数 = rowMajor… / columnMajor… / pedestalAssigns… / ordinalsFollowTheListOrder…、永続化と既定 = ProjectLedgerTests の layoutTypeDefaultsToWideRowMajorWhenNothingIsSaved / chosenLayoutTypeRoundTrips、自動適用 = visibleCountChangesReapply… / countPreservingOperations… がすべて passed) |
| C103 | 必須 | レイアウト型の実機目視(検証: 人間) | unmet | - |
| C104 | 必須 | 改名完了: Projects/ が在り Groups/ が無い、C88〜C90 exit 0、可視文言に Group が無いことの目視(検証: test -d / test -e + C88〜C90 + 人間) | unmet | - |
| C105 | 必須 | リモート判定のテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 5: just swift-test exit 0 (ProjectRemoteSplitTests の localReportLaunchesLocally / remoteReportLaunchesSshToThatHostAndPath / reportWithoutHostInformationIsLocal が passed) |
| C106 | 必須 | リモート split の実機目視(検証: 人間) | unmet | - |
| C107 | 必須 | プロジェクト一覧のテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 10: just swift-test exit 0 (21 項目に対応する 52 テストがすべて passed。項目とテストの対応は .idd/cycles/0010.md の「変更」節。ノート全行削除の確認は ProjectList.deleteAction = confirmClearNote をモデルで固定し、ProjectListOverlay.deleteOnCursorCell が OK のときだけ削除を呼ぶことを読み合わせ) |
| C108 | 必須 | プロジェクト一覧の実機目視(検証: 人間) | unmet | - |
| C109 | 必須 | 優先度リセットのテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 5: just swift-test exit 0 (ProjectPriorityResetTests の boundaryCrossing… / resetClearsEvery… / resetRunsOnlyOnce… / resetDoesNotReorder… / resetResorts… が passed) |
| C110 | 必須 | 優先度リセットの実機目視(検証: 人間) | unmet | - |
| C111 | 必須 | 次トリガーのテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 5: just swift-test exit 0 (ProjectNextTriggerTests の nextTriggerDefaultsToUnset / nextTriggerSurvivesASaveAndRestoreForEveryValue / overviewContentIncludesTheNextTrigger が passed) |
| C112 | 必須 | 次トリガーの実機目視(検証: 人間) | unmet | - |
| C113 | 必須 | キー変更の実機目視(検証: 人間) | unmet | - |
| C114 | 必須 | 一覧セル編集の IME の実機目視(検証: 人間) | unmet | - |
| C115 | 必須 | ショートカット一覧の実機目視(検証: 人間) | unmet | - |
| C116 | 必須 | 描画対象・停止/再開集合・解放・誕生時停止のテスト群が存在し成功(検証: `just swift-test` exit 0 + 項目の存在) | met | cycle 2: just swift-test exit 0 (ProjectRenderTargetTests 17 件 passed。全 5 項目を macos/Tests/Projects/ProjectRenderTargetTests.swift で突き合わせ済み) |
| C117 | 必須 | 描画停止・解放の実機観測(top / footprint、検証: 人間) | unmet | - |
| C121 | 必須 | 停止集合に誕生した描画対象外の surface を含める(stop = (after.retained − after.drawn) ∩ (before.drawn ∪ born))(検証: C116) | met | cycle 2: just swift-test exit 0 (ProjectRenderTargetTests 17 件 passed) |
| C122 | 必須 | 停止・再開の適用は RenderTargetTransition のみ、SurfaceView.isDrawing を持たない、未生成 surface は未適用扱い(検証: C116 + 読み合わせ) | met | cycle 3: just swift-test exit 0 (ProjectRenderTargetTests 21 件 passed。grep -rn isDrawing macos/Sources は該当なし。set_occlusion の呼び出しは syncRenderTargetOcclusion 内の transition.stop/resume のループだけであることを読み合わせた) |
| C118 | 望ましい | マウスからノートを開く導線(検証: 人間) | unmet | - |
| C119 | 望ましい | ノート UI・プライマリー印の見た目の洗練(検証: 人間) | unmet | - |
| C120 | 望ましい | 全体ビューの非プライマリーペインのインジケータ(検証: 人間) | unmet | - |
