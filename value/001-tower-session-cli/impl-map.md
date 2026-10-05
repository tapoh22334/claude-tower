# 要求充足マップ(O5) — 001-tower-session-cli

engine: native(superpowers TDD。spec-kit は使っていない: vf-construct の `scripts/`
が空でアダプタが無く、規模も 3 スクリプト + lib 1 本なので手で O1〜O6 を揃えた)

| 要求 | 実装箇所 | 検証 |
|---|---|---|
| REQ-001-001 | tmux-plugin/scripts/session-rename.sh, lib/common.sh `set_session_name` | tests/test_tower_rename.bats, tests/test_session_cli_lib.bats, e2e |
| REQ-001-002 | lib/common.sh `current_tower_session`, session-rename.sh | test_session_cli_lib.bats, test_tower_rename.bats, e2e |
| REQ-001-003 | lib/common.sh `set_session_name`(tmp + mv、単一キー) | test_session_cli_lib.bats, test_tower_rename.bats |
| REQ-001-004 | session-rename.sh `--clear` → `set_session_name "" ` | test_tower_rename.bats, e2e |
| REQ-001-005 | 既存 lib/nav/nav-build.sh `_session_label`(META_SESSION_NAME を読む) | e2e(`_session_label` が新名を返す) |
| REQ-001-006 | lib/session-open.sh `open_session_in_dir`, scripts/session-open.sh | test_tower_open.bats, e2e |
| REQ-001-007 | lib/session-open.sh `prompt_to_file`, lib/common.sh `start_claude_session` 第 4 引数 | test_session_cli_lib.bats, test_tower_open.bats, e2e |
| REQ-001-008 | lib/session-open.sh(`set_nav_selected`) | test_tower_open.bats, e2e |
| REQ-001-009 | lib/session-open.sh(`nav_redirect_view` when Navigator runs) | e2e「view が新セッションに切り替わる」 |
| REQ-001-010 | lib/session-open.sh(元セッションに触れる呼び出しが無い) | test_tower_open.bats「leaves the calling session alone」, e2e |
| REQ-001-011 | scripts/project-new.sh | tests/test_project_new.bats, e2e |
| REQ-001-012 | scripts/project-new.sh(`--prompt` / `--prompt-file` → `prompt_to_file`) | test_project_new.bats, e2e |
| REQ-001-013 | 3 スクリプトとも id のみ stdout、文言は `>&2` | test_tower_*.bats(`--separate-stderr`)、e2e |
| REQ-001-014 | 3 スクリプトに `read` / 確認プロンプトが無い | test_tower_*.bats「stdin closed」, e2e |
| REQ-001-015 | scripts/tower.sh `show_help` | e2e「help に 3 コマンド」 |
| REQ-001-016 | skills/tower/SKILL.md | e2e「スキルから非対話で呼べる文面と契約」 |
| REQ-001-020 | session-rename.sh(`current_tower_session` 失敗 → exit 2) | test_tower_rename.bats, e2e |
| REQ-001-021 | session-rename.sh(空名・`--clear` 併用 → exit 2) | test_tower_rename.bats, e2e |
| REQ-001-022 | session-rename.sh(`has_metadata` → exit 1) | test_tower_rename.bats, e2e |
| REQ-001-023 | scripts/session-open.sh(ディレクトリ検査を先に → exit 1) | test_tower_open.bats, e2e |
| REQ-001-024 | lib/session-open.sh `prompt_to_file`(読めない → exit 1) | test_tower_open.bats, e2e |
| REQ-001-025 | scripts/project-new.sh(`-e` 検査 → exit 1) | test_project_new.bats, e2e |
| REQ-001-026 | scripts/project-new.sh(名前検証 → exit 2) | test_project_new.bats, e2e |
| REQ-001-027 | scripts/project-new.sh(`git init` 失敗 → exit 1、ディレクトリ残置) | test_project_new.bats, e2e |
| REQ-001-028 | lib/session-open.sh(`nav_tmux has-session` ガード) | test_tower_open.bats, e2e |
