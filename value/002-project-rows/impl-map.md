# 要求充足マップ(O5) — 002-project-rows

engine: native(superpowers TDD)

| 要求 | 実装箇所 | 検証 |
|---|---|---|
| REQ-002-001 | lib/common.sh 台帳(`list_projects` 他)、lib/nav/nav-build.sh `build_session_list`(台帳 ∪ セッションの dir で見出し行) | tests/test_project_rows.bats, e2e |
| REQ-002-002 | lib/common.sh `start_claude_session` → `register_project`、nav-optimistic.sh `_remember_session_row` | test_project_rows.bats, e2e |
| REQ-002-003 | `delete_session` / `_forget_session_row` は台帳に触れない | e2e「見出しが残る」 |
| REQ-002-004 | lib/common.sh `register_project` / `unregister_project`(tmp+mv、`projects.list`) | test_project_rows.bats |
| REQ-002-005 | nav-build.sh(台帳が無ければ現在の dir で初期化) | test_project_rows.bats, e2e |
| REQ-002-006 | nav-build.sh(見出しを `dir:` 行として配列へ)、nav-loop.sh `move_selection` は行を数えるだけ | test_project_rows.bats, e2e |
| REQ-002-007 | nav-loop.sh(`set_nav_selected` に行 id)、nav-render.sh(見出し行の反転) | test_project_rows.bats, e2e |
| REQ-002-008 | scripts/navigator-view.sh `show_project_card` + main_loop の `dir:` 分岐 | test_project_rows.bats, e2e「カード」 |
| REQ-002-009 | 既存の消費者は `has-session` 失敗 → 無選択相当(nav_redirect_view は detach) | test_project_rows.bats, e2e |
| REQ-002-010 | nav-cache.sh(形式不変、見出し行も ROW) | test_project_rows.bats, e2e |
| REQ-002-011 | nav-actions.sh `new_session_in_project` / `handle_project_key`、nav-loop.sh の分岐 | test_project_rows.bats, e2e |
| REQ-002-012 | nav-actions.sh `remove_project_row`、nav-optimistic.sh `_forget_project_row` | test_project_rows.bats, e2e |
| REQ-002-013 | nav-actions.sh `handle_project_key`(i/r/t/w/Tab → `_nav_hint`) | test_project_rows.bats, e2e |
| REQ-002-014 | scripts/project-rm.sh、scripts/tower.sh dispatch | test_project_rows.bats, e2e |
| REQ-002-015 | scripts/tower.sh `show_help` | test_project_rows.bats, e2e |
| REQ-002-020 | nav-actions.sh `remove_project_row`(`_project_member_count` > 0 → 断る) | test_project_rows.bats, e2e |
| REQ-002-021 | scripts/project-rm.sh(`project_session_count` > 0 → exit 1) | test_project_rows.bats, e2e |
| REQ-002-022 | scripts/project-rm.sh(未登録 → exit 1) | test_project_rows.bats, e2e |
| REQ-002-023 | nav-actions.sh `new_session_in_project`(`! -d` → ヒント、行は残す) | test_project_rows.bats, e2e |
| REQ-002-024 | lib/common.sh `list_projects`(空行・相対パスを無視) | test_project_rows.bats, e2e |
| REQ-002-025 | nav-loop.sh `move_selection`/`go_first` の既存 clamp、`handle_project_key` | e2e「見出しだけの一覧」 |
