# Navigator のキーを整理し、copy とラベルジャンプを足す — 品質ハーネス

feature-id: 003-nav-keys

> 001・002 の harness.md の欠陥クラスを継承し、この機能に効くものに絞る。
> 規模は小機能であるため、簡略化した harness とする(vf-pipeline の「小機能」の行)。

## 検知したい欠陥クラス

| ID | 名称 | 症状 | 実績 | 検知する工程 | 費用 |
|---|---|---|---|---|---|
| DEF-T2 | 継承された `set -e` によるループ死 | ジャンプのモードや新しいキーの処理で、素の `return 1` や失敗した `[[ ]] &&` が一覧のループを殺す | #60/#62/#65 | 単体(全キーを押してもループが生きている)+ tower-reviewer | 低 |
| DEF-T5 | 共有状態と画面の不一致 | ジャンプや複製の後、`selected` とハイライト・表示ペインが食い違う | #35/#39/#40/#65 | 単体(着地後の `get_nav_selected`)+ 受入 | 低 |
| DEF-T9 | 楽観編集と再構築の不変条件の食い違い | 複製の行が `◐` で現れた後、再構築で消える・別グループに付く | #46 | 単体(`_remember_session_row` を通す)+ tower-reviewer | 低 |
| DEF-T12(新) | 一時的なモードの後の端末状態 | ラベルを消し忘れる、カーソルや echo が戻らない | CLAUDE.md が名指しする再発クラス(`/` 検索の導入時に同じ形を確認) | 単体(取り消し後の再描画)+ tower-reviewer | 低 |
| DEF-T13(新) | 外部コマンドの引数の取り違え | `--session-id` と `--resume` の組で `--fork-session` を落とし、claude が起動を拒む | CLI の仕様を調べた時点で確認(binary の文言) | 単体(起動コマンドの文字列)+ 手で 1 回 | 低 |

## ゲート配置

| ゲート | 位置 | 判定方法 | 防ぐ欠陥クラス | 守る要素のタグ | 費用 | 採否 |
|---|---|---|---|---|---|---|
| GATE-value-falsifiable | orient 出口 | 外れ判定の有無 | — | 全体 | 低 | 採用 |
| GATE-articulation | articulate 出口 | `lint-articulation.py` | — | 全体 | 低・自動 | 採用 |
| GATE-req-lint | requirements 出口 | `lint-requirements.py` | 曖昧な要求 | 全体 | 低・自動 | 採用 |
| GATE-flow-coverage | acceptance 準備 | `check-coverage.py` | 検証手段の無い要求 | 全体 | 低・自動 | 採用 |
| GATE-unit | construct 中 | `make test` 全件 + `make lint` | DEF-T2/T5/T9/T12/T13 | core〜generic | 低・自動 | 採用 |
| GATE-review | construct 出口 | tower-reviewer | DEF-T2/T5/T9/T12 | core | 中 | 採用 |
| GATE-acceptance | acceptance 出口 | 中核 2 フロー(UF-003-002, UF-003-003)の全通過 | DEF-T5/T12 | core | 中 | 採用 |
| GATE-trace | trace 出口 | `generate-trace.py` 穴ゼロ | — | 全体 | 低・自動 | 採用 |
| GATE-ci | PR | GitHub Actions の結論がすべて success | 環境差 | 全体 | 低・自動 | 採用 |

## レビューエージェントの選定

| エージェント | 採否 | 理由 |
|---|---|---|
| tower-reviewer | 採用 | DEF-T2/T5/T9/T12 はこのアプリの再発クラスで、CLAUDE.md が名指しする |
| ja-style-reviewer | 採用 | value/ の日本語文書と README を書き換えるため(CLAUDE.md の方針) |
| code-practice-reviewer | 選外 | tower-reviewer と shellcheck で足りる。一般的な指摘はこの規模では実績が無い |
| test-pyramid-reviewer | 選外 | テストは既存の bats の型に乗せるだけで、層の配分は変えない |
| product-design-reviewer | 選外 | 画面の見た目はラベルの列を足すだけ。読みやすさは使ってから判断する(orient.md) |
| architecture-reviewer | 選外 | 新しいコンポーネントを作らない。nav/ の 1 ファイル 1 責務の型に乗せる |

## 構築層への要求(契約の I4)

### テスト戦略
- 単体: キーの割り当て(17 個、`i` `r` `A` が何もしない、Enter と D 以外が行の種類で変わらない)、Enter の 3 状態(動いている・休眠中・外部)と再開の失敗、`a` の既定ディレクトリ、複製の起動コマンド・名前・断る 3 条件・起動失敗、ラベルの割り当て(2 段、26 で打ち切り、復旧できないグループに付けない)、絞り込み・着地・Enter・Esc・当たらないキー・消えた行・見出しが 0 件
- 受入(`tests/e2e/test_acceptance_003.bats`): 中核 2 フローは必須、重要 3 フローは推奨
- 既存テストの更新: 削るキー(`i` `r` `A` 旧 `f`)を参照するテストは、前提の更新か回帰かを 1 本ずつ判定して記録する

### 禁止する手法・ライブラリ
- ジャンプのモードの中での `render_list` 以外の画面書き込み(ラベルは描画関数の引数で渡す)
- 複製で元のセッションの transcript を書き換える手段(`--fork-session` を外す、ファイルを複製する)
- 削ったキーの別名(非スコープ)

### 守るべき既存規約
- 001・002 と同じ(shellcheck、4 スペース、`_` 接頭辞、500 行以下、`handle_error`、`set -e` を受け継ぐ前提)
- nav/ の 1 ファイル 1 責務。ジャンプのモードは新しいファイル(`nav-jump.sh`)に置き、`navigator-list.sh` は読み込むだけにする

### 非機能要求
- 性能: `f` を押してからラベルが出るまでの再描画は 1 回
- セキュリティ: 権限の境界は変わらない

### 「動けばよい」を許す範囲
- なし

## 費用対効果の点検

- [x] DEF-T13 は単体で起動コマンドの文字列を検査し、受入では手で 1 回だけ確かめる
- [x] DEF-T5 は単体と受入の 2 層(層が違う)
- [x] 実績ゼロの欠陥クラスは無い(T12 は CLAUDE.md の名指し、T13 は CLI の文言で確認)

上流に移した判断:
| 欠陥クラス | 元の検知工程 | 移した先 | 理由 |
|---|---|---|---|
| DEF-T13 | 受入 | 単体 | 起動するコマンドの文字列を見るだけで再現できる |
