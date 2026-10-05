# トレーサビリティ報告 — 001-tower-session-cli

> この文書は `generate-trace.py` の生成物。**手で編集しない。**
> 直したくなったら元の ID かスクリプトを直す。

- 要求 26 件 / ユーザフロー 6 件 / シナリオ 12 件
- 実行結果: 20261005-145917
- 穴: **0 件**

## 追跡表

| 要求 | 型 | 由来 | UF | シナリオ | 実装 | 結果 |
|---|---|---|---|---|---|---|
| REQ-001-001 | Event-driven | VH-001 / UF-001-001 / E-001 | UF-001-001 | 1 | tmux-plugin/scripts/session-rename.sh,… | 通過 |
| REQ-001-002 | State-driven | VH-001 / UF-001-001 / E-002 | UF-001-001 | 1 | lib/common.sh `current_tower_session`,… | 通過 |
| REQ-001-003 | Ubiquitous | VH-001 / E-003(再構築が途中状態を読まない) | UF-001-001 | 1 | lib/common.sh `set_session_name`(tmp +… | 通過 |
| REQ-001-004 | Event-driven | E-004 / UF-001-002 | UF-001-002 | 1 | session-rename.sh `--clear` → `set_ses… | 通過 |
| REQ-001-005 | State-driven | VH-001 / E-003 / UF-001-001 | UF-001-001 | 1 | 既存 lib/nav/nav-build.sh `_session_labe… | 通過 |
| REQ-001-006 | Event-driven | VH-002 / UF-001-003 / E-005 | UF-001-003 | 1 | lib/session-open.sh `open_session_in_d… | 通過 |
| REQ-001-007 | Event-driven | VH-002 / UF-001-003 / E-006 | UF-001-003 | 1 | lib/session-open.sh `prompt_to_file`, … | 通過 |
| REQ-001-008 | Event-driven | VH-002 / UF-001-003 / E-005 | UF-001-003 | 1 | lib/session-open.sh(`set_nav_selected`… | 通過 |
| REQ-001-009 | State-driven | E-007 / UF-001-003 | UF-001-003 | 1 | lib/session-open.sh(`nav_redirect_view… | 通過 |
| REQ-001-010 | Ubiquitous | orient.md 非スコープ / UF-001-003 | UF-001-003 | 1 | lib/session-open.sh(元セッションに触れる呼び出しが無い)… | 通過 |
| REQ-001-011 | Event-driven | VH-003 / UF-001-004 / E-008 | UF-001-004 | 1 | scripts/project-new.sh tests/test_proj… | 通過 |
| REQ-001-012 | Event-driven | VH-003 / UF-001-004 | UF-001-004 | 1 | scripts/project-new.sh(`--prompt` / `-… | 通過 |
| REQ-001-013 | Event-driven | E-010 / UF-001-005 | UF-001-001,UF-001-002,UF-001-003,UF-001-004,UF-001-005 | 4 | 3 スクリプトとも id のみ stdout、文言は `>&2` test_… | 通過 |
| REQ-001-014 | Ubiquitous | E-014 / UF-001-005 | UF-001-005 | 1 | 3 スクリプトに `read` / 確認プロンプトが無い test_towe… | 通過 |
| REQ-001-015 | Ubiquitous | E-013 | UF-001-006 | 1 | scripts/tower.sh `show_help` e2e「help … | 通過 |
| REQ-001-016 | Ubiquitous | VH-002 / E-012 / UF-001-005 | UF-001-005 | 1 | skills/tower/SKILL.md e2e「スキルから非対話で呼べる… | 通過 |
| REQ-001-020 | Unwanted | E-002 / E-011 / UF-001-006 | UF-001-006 | 1 | session-rename.sh(`current_tower_sessi… | 通過 |
| REQ-001-021 | Unwanted | E-011 | UF-001-006 | 1 | session-rename.sh(空名・`--clear` 併用 → ex… | 通過 |
| REQ-001-022 | Unwanted | E-011 | UF-001-006 | 1 | session-rename.sh(`has_metadata` → exi… | 通過 |
| REQ-001-023 | Unwanted | E-011 / UF-001-006 | UF-001-006 | 1 | scripts/session-open.sh(ディレクトリ検査を先に → … | 通過 |
| REQ-001-024 | Unwanted | E-011 | UF-001-006 | 1 | lib/session-open.sh `prompt_to_file`(読… | 通過 |
| REQ-001-025 | Unwanted | E-011 / UF-001-006 | UF-001-006 | 1 | scripts/project-new.sh(`-e` 検査 → exit … | 通過 |
| REQ-001-026 | Unwanted | E-011 | UF-001-006 | 1 | scripts/project-new.sh(名前検証 → exit 2) … | 通過 |
| REQ-001-027 | Unwanted | E-011 | UF-001-006 | 1 | scripts/project-new.sh(`git init` 失敗 →… | 通過 |
| REQ-001-028 | Unwanted | E-007 / UF-001-003 | UF-001-003 | 1 | lib/session-open.sh(`nav_tmux has-sess… | 通過 |
| REQ-001-029 | Unwanted | E-006 / E-011(レビュー指摘: 空の位置引数と MAX_ARG_STRLEN 超過) | UF-001-006 | 1 | lib/session-open.sh `prompt_to_file`(空… | 通過 |

## 穴

なし。全要求が UF・シナリオ・実装・実行結果まで繋がっている。

## 中核フローの要求

中核 23 件中 **23 件が通過**。
