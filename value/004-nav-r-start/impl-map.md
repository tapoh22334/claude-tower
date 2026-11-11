# 要求充足マップ(O5) — 004-nav-r-start

engine: native(superpowers TDD)

| 要求 | 実装箇所 | 検証 |
|---|---|---|
| REQ-004-001 | lib/nav/nav-loop.sh の `r` の分岐 → lib/nav/nav-start.sh `start_under_cursor` → `_start_one_session`(scripts/session-restore.sh、`_mark_session_starting`)、`_settle_after_change` | e2e(test_acceptance_004.bats) |
| REQ-004-002 | lib/nav/nav-start.sh `start_under_cursor` → `_startable_in_project` | e2e |
| REQ-004-003 | lib/nav/nav-start.sh `start_under_cursor`(`Started N session(s)` のヒント) | e2e |
| REQ-004-004 | lib/nav/nav-start.sh `_state_is_startable`(`get_display_state` が `dormant`) | e2e |
| REQ-004-005 | lib/nav/nav-render.sh `show_help` | e2e, test_acceptance_003.bats |
| REQ-004-010 | lib/nav/nav-start.sh `_unstartable_reason` | e2e |
| REQ-004-011 | lib/nav/nav-start.sh `start_under_cursor`(`No dormant session in this project`) | e2e |
| REQ-004-012 | lib/nav/nav-start.sh `_start_one_session`(`NAV_START_ERR`)と失敗のヒント | e2e |
| REQ-004-013 | lib/nav/nav-start.sh `start_under_cursor`(画面の行と selected ファイルの照合) | e2e |
