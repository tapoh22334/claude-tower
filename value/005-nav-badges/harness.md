# シェルとエージェントのバッジ — 品質ハーネス

feature-id: 005-nav-badges

> 小機能のため簡略化した(vf-pipeline「小さく回す場合」)。

## 検知したい欠陥クラス

| ID | 名称 | 症状 | 実績 | 検知する工程 |
|---|---|---|---|---|
| DEF-001 | 止まったセッションの誤った busy | 終了した Claude の残った画面でスピナーが回る | #88、#123 | 受入(REQ-005-010)+ tower-reviewer |
| DEF-002 | 楽観的な行の桁ずれ | 起動中・削除中の行だけタイトルがずれる | 003・004 の楽観的な編集 | 受入(REQ-005-011)+ tower-reviewer |
| DEF-003 | ヘルプのはみ出し | 80×24 で見出しが画面外に押し出される | #131 の初回 CI | 受入(REQ-005-007)+ 統合テスト |
| DEF-004 | 再構築あたりの fork の増加 | 一覧の更新に時間がかかる | #97 | tower-reviewer |

## ゲート配置

| ゲート | 判定方法 | 採否 |
|---|---|---|
| GATE-req-lint | `lint-requirements.py` | 採用 |
| GATE-flow-coverage | 要求とフローの双方向の対応 | 採用 |
| GATE-review | tower-reviewer | 採用 |
| GATE-acceptance | 中核フローの全通過 | 採用 |
| GATE-trace | 未対応の要求がゼロ | 採用 |
