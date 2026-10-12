# 作業記録(O3) — 002-project-rows

| タスク | 要求 | 成果 |
|---|---|---|
| 台帳(`register_project` ほか)、`session_project_dir`、`project_session_count`、`start_claude_session` で登録 | REQ-002-001〜005, 024 | lib/common.sh、tests/test_project_rows.bats |
| 見出し行(nav-build / nav-render / nav-optimistic) | REQ-002-006, 007, 010 | 既存 13 テストの前提更新 + 新規 |
| view のカード(navigator-view.sh) | REQ-002-008 | 単体 + e2e |
| 見出しでのキー(nav-actions / nav-loop) | REQ-002-011〜013, 020, 023, 025 | 単体 + e2e |
| `tower project rm`(project-rm.sh)+ help | REQ-002-014, 015, 021, 022 | 単体 + e2e |
| 他の読者の `dir:` 耐性 | REQ-002-009 | 単体 + e2e |
| 受入 11 シナリオ | 全要求 | tests/e2e/test_acceptance_002.bats |
| レビュー反映(カード再描画、前方一致、rm 後の resync、D の件数、flock) | — | 2 コミット目 |

Issue: #74(Story)、#75〜#77(Task)。PR #78。
