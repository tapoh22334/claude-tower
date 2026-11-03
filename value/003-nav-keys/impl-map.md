# 要求充足マップ(O5) — 003-nav-keys

engine: native(superpowers TDD)

| 要求 | 実装箇所 | 検証 |
|---|---|---|
| REQ-003-001 | lib/nav/nav-loop.sh `main_loop` のキー分岐(`i` `r` `A` と旧 `f` を削除、`c` `f` を追加) | tests/test_nav_keys.bats, e2e |
| REQ-003-002 | lib/nav/nav-actions.sh `handle_project_key`(Enter と D 以外は 1 を返す) | test_nav_keys.bats, test_project_rows.bats, e2e |
| REQ-003-003 | lib/nav/nav-actions.sh `open_selected` → `focus_view` | e2e |
| REQ-003-004 | lib/nav/nav-actions.sh `open_selected` → `restore_selected`、nav-loop.sh の `_settle_after_change` | test_nav_keys.bats, e2e |
| REQ-003-005 | lib/nav/nav-actions.sh `handle_project_key ''`(既存の `session-add.sh --fork-dir`) | test_project_rows.bats, e2e |
| REQ-003-006 | lib/nav/nav-actions.sh `_add_default_dir` → `TOWER_ADD_DEFAULT_DIR` | test_nav_keys.bats, e2e |
| REQ-003-007 | lib/nav/nav-render.sh `show_help` とフッター | test_nav_keys.bats, test_display_snapshot.bats, e2e |
| REQ-003-010 | lib/common.sh `copy_session`、`start_claude_session` の mode `copy`、scripts/session-copy.sh | test_nav_keys.bats, e2e, 実際の claude で 1 回(judged.md) |
| REQ-003-011 | lib/common.sh `copy_session`(名前 `<name> copy` / `copy`) | e2e |
| REQ-003-012 | lib/nav/nav-actions.sh `copy_selected` → `set_nav_selected`, `_remember_session_row` | e2e |
| REQ-003-013 | lib/common.sh `copy_session`(元の metadata と transcript は読むだけ) | e2e, judged.md |
| REQ-003-020 | lib/nav/nav-jump.sh `_jump_assign_labels`, `_jump_cell`、nav-render.sh のラベル列と `_jump_fit` | test_nav_keys.bats, e2e |
| REQ-003-021 | lib/nav/nav-jump.sh `_jump_cell`(`NAV_JUMP_PREFIX` で絞る) | test_nav_keys.bats, e2e |
| REQ-003-022 | lib/nav/nav-jump.sh `jump_prompt` → `_jump_land` | test_nav_keys.bats, e2e |
| REQ-003-023 | lib/nav/nav-jump.sh `jump_prompt`(1 文字目の後の Enter) | test_nav_keys.bats, e2e |
| REQ-003-024 | lib/nav/nav-jump.sh `NAV_JUMP_IDS`(f を押した時点の id) | test_nav_keys.bats, e2e |
| REQ-003-030 | lib/nav/nav-actions.sh `copy_selected`(見出しの行と外部の行を断る) | e2e |
| REQ-003-031 | lib/nav/nav-actions.sh `copy_selected`、lib/common.sh `copy_session`(transcript の有無) | e2e |
| REQ-003-032 | lib/common.sh `copy_session`(起動に失敗したら metadata を保存しない)、`copy_selected` の "Copy failed" | e2e |
| REQ-003-033 | lib/nav/nav-actions.sh `open_selected`(`restore_selected` の失敗で `focus_view` しない) | e2e |
| REQ-003-034 | lib/nav/nav-jump.sh `jump_prompt`(Esc は `nav_read_escape`、当たらないキーは取り消し) | test_nav_keys.bats, e2e |
| REQ-003-035 | lib/nav/nav-jump.sh `_jump_land`(行が消えていれば動かさない) | test_nav_keys.bats, e2e |
| REQ-003-036 | lib/nav/nav-jump.sh `jump_prompt`(`_jump_assign_labels` が 1 を返せばモードに入らない) | test_nav_keys.bats, e2e |
| REQ-003-037 | lib/nav/nav-actions.sh `open_selected`(外部の行は再開しない) | e2e |
