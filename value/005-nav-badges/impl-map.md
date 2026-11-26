# 要求充足マップ(O5) — 005-nav-badges

engine: native(superpowers TDD)

| 要求 | 実装箇所 | 検証 |
|---|---|---|
| REQ-005-001 | lib/claude-sessions.sh `_pane_scan`(`PANE_SHELLS`)→ `pane_shows_working`、`is_session_busy`。待ち行列は `get_wait_state` がシェルだけの busy を入力待ちとして扱う | test_acceptance_005.bats, test_claude_sessions.bats, test_wait_state.bats |
| REQ-005-002 | lib/nav/nav-build.sh `_session_badges`(`⚙N`) | test_acceptance_005.bats |
| REQ-005-003 | lib/nav/nav-build.sh `_session_badges`(`✦N` を先に置く) | test_acceptance_005.bats, test_newmsg_state.bats |
| REQ-005-004 | lib/nav/nav-render.sh `_compose_row`、`_badge_cells`、lib/nav/nav-build.sh `build_session_list` の 2 段の組み立て(`NAV_BADGE_W`) | test_acceptance_005.bats, test_list_columns.bats |
| REQ-005-005 | lib/nav/nav-render.sh `_compose_row`(`NAV_BADGE_W` が 0 のときはバッジ欄なし) | test_acceptance_005.bats |
| REQ-005-006 | lib/nav/nav-render.sh(`NAV_RIGHT_COL` を削除)、lib/nav/nav-build.sh `_session_label` の幅、lib/nav/nav-jump.sh `_jump_fit` | test_acceptance_005.bats, test_nav_keys.bats |
| REQ-005-007 | lib/nav/nav-render.sh `show_help`(`Badges:` の行)、README.md | test_acceptance_005.bats |
| REQ-005-010 | lib/claude-sessions.sh `_pane_scan`(シェル数の行のあとにエージェント一覧以外の行があれば数えない) | test_acceptance_005.bats |
| REQ-005-011 | lib/nav/nav-cache.sh(`BADGE_W` をキャッシュに保存)、lib/nav/nav-optimistic.sh の行は `NAV_BADGE_W` で組み立てる | test_acceptance_005.bats |
