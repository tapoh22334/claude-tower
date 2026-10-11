# トレーサビリティ報告 — 002-project-rows

> この文書は `generate-trace.py` の生成物。**手で編集しない。**
> 直したくなったら元の ID かスクリプトを直す。

- 要求 21 件 / ユーザフロー 5 件 / シナリオ 11 件
- 実行結果: 20261011-185614
- 穴: **0 件**

## 追跡表

| 要求 | 型 | 由来 | UF | シナリオ | 実装 | 結果 |
|---|---|---|---|---|---|---|
| REQ-002-001 | Ubiquitous | VH-001 / UF-002-001 / E-001 | UF-002-001 | 1 | lib/common.sh 台帳(`list_projects` 他)、li… | 通過 |
| REQ-002-002 | Event-driven | VH-001 / UF-002-001 / E-007 | UF-002-001 | 1 | lib/common.sh `start_claude_session` →… | 通過 |
| REQ-002-003 | Event-driven | VH-001 / UF-002-001 / E-001 | UF-002-001 | 1 | `delete_session` / `_forget_session_ro… | 通過 |
| REQ-002-004 | Ubiquitous | E-007 / harness DEF-T3 | UF-002-001 | 1 | lib/common.sh `register_project` / `un… | 通過 |
| REQ-002-005 | State-driven | E-011 / UF-002-001 | UF-002-001 | 1 | nav-build.sh(台帳が無ければ現在の dir で初期化) test… | 通過 |
| REQ-002-006 | Ubiquitous | VH-002 / UF-002-002 / E-002 | UF-002-002 | 1 | nav-build.sh(見出しを `dir:` 行として配列へ)、nav-… | 通過 |
| REQ-002-007 | State-driven | VH-002 / UF-002-002 / E-002 / E-010 | UF-002-002 | 1 | nav-loop.sh(`set_nav_selected` に行 id)、… | 通過 |
| REQ-002-008 | State-driven | VH-003 / UF-002-002 / E-003 | UF-002-002 | 1 | scripts/navigator-view.sh `show_projec… | 通過 |
| REQ-002-009 | Ubiquitous | E-002 / harness DEF-T5 | UF-002-002 | 1 | 既存の消費者は `has-session` 失敗 → 無選択相当(nav_r… | 通過 |
| REQ-002-010 | Ubiquitous | E-002 / harness DEF-T5 | UF-002-002 | 1 | nav-cache.sh(形式不変、見出し行も ROW) test_proj… | 通過 |
| REQ-002-011 | Event-driven | VH-002 / UF-002-003 / E-004 / E-005 | UF-002-003 | 1 | nav-actions.sh `new_session_in_project… | 通過 |
| REQ-002-012 | Event-driven | UF-002-004 / E-006 | UF-002-004 | 1 | nav-actions.sh `remove_project_row`、na… | 通過 |
| REQ-002-013 | Event-driven | E-009 | UF-002-005 | 1 | nav-actions.sh `handle_project_key`(i/… | 通過 |
| REQ-002-014 | Event-driven | UF-002-004 / E-008 | UF-002-004 | 1 | scripts/project-rm.sh、scripts/tower.sh… | 通過 |
| REQ-002-015 | Ubiquitous | E-008 | UF-002-004 | 1 | scripts/tower.sh `show_help` test_proj… | 通過 |
| REQ-002-020 | Unwanted | UF-002-004 / E-006 | UF-002-004 | 1 | nav-actions.sh `remove_project_row`(`_… | 通過 |
| REQ-002-021 | Unwanted | UF-002-004 / E-008 | UF-002-004 | 1 | scripts/project-rm.sh(`project_session… | 通過 |
| REQ-002-022 | Unwanted | E-008 | UF-002-004 | 1 | scripts/project-rm.sh(未登録 → exit 1) te… | 通過 |
| REQ-002-023 | Unwanted | UF-002-003 / E-004 | UF-002-003 | 1 | nav-actions.sh `new_session_in_project… | 通過 |
| REQ-002-024 | Unwanted | E-001 / harness DEF-T2 | UF-002-001 | 1 | lib/common.sh `list_projects`(空行・相対パスを… | 通過 |
| REQ-002-025 | Unwanted | UF-002-002 / E-002(空状態) | UF-002-002 | 1 | nav-loop.sh `move_selection`/`go_first… | 通過 |

## 穴

なし。全要求が UF・シナリオ・実装・実行結果まで繋がっている。

## 中核フローの要求

中核 14 件中 **14 件が通過**。
