# r による休眠セッションの起動 — 品質ハーネス

feature-id: 004-nav-r-start

> 小機能のため簡略化した(vf-pipeline「小さく回す場合」)。欠陥クラスは、このリポジトリで繰り返し起きたものだけを選んだ。

## 検知したい欠陥クラス

| ID | 名称 | 症状 | 実績 | 検知する工程 | 費用 |
|---|---|---|---|---|---|
| DEF-001 | 画面と共有状態の不一致 | 画面と違う行のセッションが起動する | 003 の逸脱 7、メモリ tower-nav-shared-state-files | tower-reviewer + 受入(REQ-004-013) | 低 |
| DEF-002 | 楽観的な編集が再読み込みで戻る | ◐ にした行が次の tick で ○ に戻る | メモリ optimistic edit(tower-reviewer の観点 4) | tower-reviewer | 低 |
| DEF-003 | `$(...)` による配列の書き換えの消失 | ◐ にした行が描かれない | メモリ bash-subshell-discards-array-mutation | tower-reviewer + 受入 | 低 |
| DEF-004 | 端末の状態の取り残し | 起動後にカーソルや入力の反響が戻らない | tower-reviewer の観点 5 | tower-reviewer | 低 |

## ゲート配置

| ゲート | 位置 | 判定方法 | 防ぐ欠陥クラス | 費用 | 採否 |
|---|---|---|---|---|---|
| GATE-req-lint | requirements 出口 | `lint-requirements.py` | 要求の曖昧さ | 低・自動 | 採用 |
| GATE-flow-coverage | userflows 出口 | 要求とフローの双方向の対応 | 要求の対応漏れ | 低・自動 | 採用 |
| GATE-review | construct 出口 | tower-reviewer | DEF-001〜004 | 中 | 採用 |
| GATE-acceptance | acceptance 出口 | 中核フローの全通過 | 価値の未達 | 中 | 採用 |
| GATE-trace | trace 出口 | 未対応の要求がゼロ | 要求の未検証 | 低 | 採用 |

## レビューエージェントの選定

| エージェント | 採否 | 理由 |
|---|---|---|
| tower-reviewer | 採用 | CLAUDE.md が PR 前に指定している。DEF-001〜004 はこのエージェントの観点である |
| code-practice-reviewer | 不採用 | ShellCheck と既存の規約で足りる。tower-reviewer と重複する |
| test-pyramid-reviewer | 不採用 | 追加するのは受入テストとヘルプのテストだけで、比率の判断がない |
| product-design-reviewer | 不採用 | キーを 1 つ戻すだけで、画面の構成は変えない |

## 構築層への要求(契約の I4)

### テスト戦略
- 結合: 受入シナリオを `tests/e2e/test_acceptance_004.bats` に置く。実 tmux のテスト専用 socket を使い、claude の代わりに引数を記録するスタブを使う(003 と同じ形)
- 単体: 追加しない。起動の可否の判定は `get_display_state` の既存テストが受け持つ

### 禁止する手法・ライブラリ
- 外部コマンドの追加(fzf などの新しい依存)

### 守るべき既存規約
- ファイルは 500 行未満。`nav-actions.sh` は上限に達しているので、r の処理は `lib/nav/` に新しいファイルとして置く
- 起動は `session-restore.sh` を通す。Enter による再開と同じ経路を使う

### 非機能要求
- ヘルプは 24 行未満に収める(既存の制約)
- フッターは 80 桁に収める(003 の REQ-003-007)
