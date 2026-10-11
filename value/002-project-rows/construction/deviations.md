# 逸脱報告(O6) — 002-project-rows

| # | 内容 | 種別 | 理由 |
|---|---|---|---|
| 1 | 見出しを「先頭行に乗る文字列」から「行(id `dir:<path>`)」に変えた。`SESSION_HEADERS` は常に "" | 内部設計 | 見出しを選べるようにする最小の形。キャッシュ形式は不変。既存テスト 13 本の前提を更新(回帰ではない。`tests/test_optimistic_list.bats` 等) |
| 2 | 不明ディレクトリのセッションが raw の先頭にあると一覧から消える既存欠陥を修正(`"${a[@]:-}"` の空配列展開) | 既存欠陥の修正 | 新テスト「unknown-dir group keeps its header row」が検出 |
| 3 | `project_registered` の `list_projects \| grep -q` を変数経由に | 欠陥修正 | pipefail + grep -q の SIGPIPE 競合で bats が不定に失敗した |
| 4 | カードの git ブランチは `symbolic-ref --short HEAD` を優先 | 実装詳細 | 初回コミット前の repo でも出す |
| 5 | 見出し選択中、view はカードを 2 秒周期で描き直す | 実装詳細 | セッション数が変わっても追従するため。再描画は軽い |
| 6 | Tile/Tail/Queue は `dir:` 選択を無選択として扱い、戻ると先頭のセッションが選ばれる | 要求どおり(REQ-002-009) | 設計の範囲内。見出し選択の維持は非スコープ |

非スコープ違反の点検: 並べ替え・折りたたみ・一括操作・外部連携は無し。件数表示(E-012)はカードにのみ出し、一覧の見出しには出していない。

## レビュー(tower-reviewer)後の追補

| # | 内容 | 種別 | 理由 |
|---|---|---|---|
| 7 | view のカードは 2 秒タイマーで再描画し、`clear` ではなくホーム移動 + 行末消去で描く | 欠陥修正(CONFIRMED) | `SECONDS % 2` 判定は偶数秒の間 10 回/秒 clear + 全再描画になっていた |
| 8 | `nav_redirect_view` は `dir:` を見た時点で detach 側へ | 欠陥修正(CONFIRMED) | tmux のターゲットは前方一致で、`dir:` が `dir*` という名のセッションに当たり得た |
| 9 | `tower project rm` はカーソル下のプロジェクトなら `selected` を空にし、list ループの再同期は未一覧の `dir:` を「消えた行」として扱いカーソル行を書き戻す | 欠陥修正(CONFIRMED) | 外部削除後に強制再構築が毎 tick 走り続け、D の対象と画面が食い違っていた |
| 10 | 見出しでの D は画面上の行数と台帳の件数の大きい方で判定 | 欠陥修正(CONFIRMED) | dead/lost だけが残るプロジェクトで Navigator と CLI の判定が食い違った |
| 11 | 台帳の RMW を `flock`(あれば)で排他し、tmp 名を `mktemp` に | 堅牢化(PLAUSIBLE) | 同時の `tower open` で片方の登録が消え得た |
