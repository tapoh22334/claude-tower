# Navigator でプロジェクトを行として扱う — 品質ハーネス

feature-id: 002-project-rows

> 001 の harness.md の欠陥クラス DEF-T1〜T7 を継承し、この機能で特に効くものに絞る。

## 検知したい欠陥クラス

| ID | 名称 | 症状 | 実績 | 検知する工程 | 費用 |
|---|---|---|---|---|---|
| DEF-T5 | 共有状態と画面の不一致 | `selected` が指すものとハイライト・view が食い違う | #35/#39/#40/#65(未一覧 id) | 単体(index と selected の往復)+ 受入(実 tmux で view) + tower-reviewer | 中 |
| DEF-T2 | 継承された `set -e` によるループ死 | 見出し行で `[[ ]] &&` や素の `return` がループを殺す | #60/#62/#65 | 「見出し行で全キーを押しても生きている」単体 + tower-reviewer | 低 |
| DEF-T3 | 非原子的な状態書き換え | 台帳の途中状態を再構築が読む | `save_metadata` の既知の性質 | 単体(tmp+mv、壊れた行の無視) | 低 |
| DEF-T4 | テストが本物の状態に触る | 利用者の台帳 `projects.list` を書き換える | #41 | test_helper の `CLAUDE_TOWER_METADATA_DIR` 隔離に乗る | 低 |
| DEF-T9(新) | 楽観編集と再構築の不変条件の食い違い | 見出しが行になった後、`_remember_session_row` / `_forget_session_row` が旧前提(見出しは先頭行に乗る)で動き、見出しが消える・二重になる・別グループに付く | #46 / 探索で `_forget_session_row` が最後の行の見出しを隣グループへ渡す欠陥を確認 | 単体(挿入・削除の全パターン)+ 受入 | 低 |
| DEF-T10(新) | 行種別を知らない消費者 | Tile/Tail/Queue/CLI が `dir:` を session id として扱い落ちる | 探索で「現状は安全に劣化」を確認(回帰防止) | 単体(各 view に `dir:` を食わせる) | 低 |

## ゲート配置

| ゲート | 位置 | 判定方法 | 防ぐ欠陥クラス | 費用 | 採否 |
|---|---|---|---|---|---|
| GATE-value-falsifiable | orient 出口 | 外れ判定の有無 | — | 低 | 採用 |
| GATE-articulation | articulate 出口 | `lint-articulation.py` | — | 低・自動 | 採用 |
| GATE-req-lint | requirements 出口 | `lint-requirements.py` | 曖昧要求 | 低・自動 | 採用 |
| GATE-flow-coverage | acceptance 準備 | `check-coverage.py` | 検証手段の無い要求 | 低・自動 | 採用 |
| GATE-unit | construct 中 | `make test` 全件(既存 745 + 新規)+ `make lint` | DEF-T2/T3/T9/T10 | 低・自動 | 採用 |
| GATE-review | construct 出口 | tower-reviewer | DEF-T5/T2/T9 | 中 | 採用 |
| GATE-acceptance | acceptance 出口 | 中核 3 フロー全通過(実 tmux、per-run socket) | DEF-T5/T9 | 中 | 採用 |
| GATE-trace | trace 出口 | `generate-trace.py` 穴ゼロ | — | 低・自動 | 採用 |
| GATE-contract(手動) | construct 出口 | O1〜O6 の存在 | — | 低 | 採用 |

## レビューエージェントの選定

| エージェント | 採否 | 理由 |
|---|---|---|
| tower-reviewer | 採用 | DEF-T5/T9 はこの機能の中心。CLAUDE.md が名指し |
| その他 | 選外 | 001 と同じ理由(重複・実績なし)。見出し行の見た目は利用後に判断する |

## 構築層への要求(契約の I4)

### テスト戦略
- 単体: 台帳関数(登録・重複・削除・壊れた行・tmp+mv)、`build_session_list` の見出し行(0 件 / N 件 / 台帳のみ / 初期化)、`_remember_session_row` / `_forget_session_row` の全パターン(空グループへ挿入、最後の行の削除、見出しだけの一覧)、キー処理(見出しで n/Enter/f/D/i/r/t/w)、view のカード描画関数、`tower project rm`
- 結合(実 tmux): 見出し選択時に view pane が nested client を外してカードを描く
- 受入(`tests/e2e/test_acceptance_002.bats`): 5 フロー
- 既存テストの更新: 見出しが行になることで `SESSION_HEADERS` の前提が変わる(test_optimistic_list / test_navigator_cache / test_coverage_gaps_9・12)。**壊れたテストは「前提の更新」か「回帰」かを 1 本ずつ判定して記録する**

### 禁止する手法・ライブラリ
- `SESSION_HEADERS` に依存する新コード(配列は互換のため残すが常に空)
- `selected` の内容を `tower_` 前提で `has-session` に渡す新コード(先に種別を見る)
- 台帳の全体上書き(`>` 直書き)

### 守るべき既存規約
- 001 と同じ(shellcheck、4 スペース、`_` 接頭辞、500 行、`handle_error`、`set -e` を受け継ぐ前提)
- `nav-render.sh` の行幅計算(`_content_width`、全角幅)を見出し行にも適用

### 非機能要求
- 性能: 再構築 1 回あたりの台帳読み込みは 1 回、キー 1 打の遅延を増やさない
- セキュリティ: 台帳のパスは絶対パスのみ受け付ける(REQ-002-024)

### 「動けばよい」を許す範囲
- なし

## 費用対効果の点検

- [x] DEF-T9/T10 は単体で捕まえ、受入は中核フローの証跡に使う
- [x] DEF-T5 は単体と受入の 2 層(層が違う)
- [x] 実績ゼロの欠陥クラスは無い(T9 は探索で欠陥の芽を確認、T10 は回帰防止)

上流に移した判断:
| 欠陥クラス | 元の検知工程 | 移した先 | 理由 |
|---|---|---|---|
| DEF-T10 | 受入 | 単体 | 各 view に `dir:` を食わせるだけで再現できる |
