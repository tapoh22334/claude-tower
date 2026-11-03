# 作業記録(O3) — 003-nav-keys

| タスク | 要求 | 成果 |
|---|---|---|
| キーの整理(`i` `r` `A` と旧 `f` を削除、Enter で再開、見出しの行は Enter と D だけ) | REQ-003-001〜005, 033, 037 | nav-loop.sh、nav-actions.sh `open_selected` `handle_project_key`、tests/test_nav_keys.bats |
| `a` の場所の初期値 | REQ-003-006 | nav-actions.sh `_add_default_dir` |
| ヘルプとフッター | REQ-003-007 | nav-render.sh |
| copy(`c`) | REQ-003-010〜013, 030〜032 | lib/common.sh `copy_session`、scripts/session-copy.sh、nav-actions.sh `copy_selected` |
| ラベルジャンプ(`f`) | REQ-003-020〜024, 034〜036 | lib/nav/nav-jump.sh、nav-render.sh のラベル列 |
| 既存テストの前提の更新と README | — | deviations.md #3 |
| 受入(12 シナリオ)と実 claude での確認 | 全件 | tests/e2e/test_acceptance_003.bats、acceptance/results/ |
| レビュー指摘の修正(折り返し、Enter の再開の照合) | REQ-003-020, 004 | `_jump_fit`、`open_selected` の引数 |
