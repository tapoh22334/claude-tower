# トレーサビリティ報告 — 003-nav-keys

> この文書は `generate-trace.py` の生成物。**手で編集しない。**
> 直したくなったら元の ID かスクリプトを直す。

- 要求 24 件 / ユーザフロー 8 件 / シナリオ 12 件
- 実行結果: 20261103-164416
- 穴: **0 件**

## 追跡表

| 要求 | 型 | 由来 | UF | シナリオ | 実装 | 結果 |
|---|---|---|---|---|---|---|
| REQ-003-001 | Ubiquitous | VH-001 / UF-003-001 / E-010 | UF-003-007 | 1 | lib/nav/nav-loop.sh `main_loop` のキー分岐(… | 通過 |
| REQ-003-002 | Ubiquitous | VH-001 / UF-003-001 / E-001, E-002 | UF-003-001,UF-003-004 | 1 | lib/nav/nav-actions.sh `handle_project… | 通過 |
| REQ-003-003 | Event-driven | VH-001 / UF-003-001 / E-001 | UF-003-001 | 1 | lib/nav/nav-actions.sh `open_selected`… | 通過 |
| REQ-003-004 | Event-driven | VH-001 / UF-003-001 / E-001 | UF-003-001 | 1 | lib/nav/nav-actions.sh `open_selected`… | 通過 |
| REQ-003-005 | Event-driven | VH-001 / UF-003-001 / E-001 | UF-003-004 | 1 | lib/nav/nav-actions.sh `handle_project… | 通過 |
| REQ-003-006 | Event-driven | VH-001 / UF-003-001 / E-003 | UF-003-004 | 1 | lib/nav/nav-actions.sh `_add_default_d… | 通過 |
| REQ-003-007 | Ubiquitous | VH-001 / UF-003-001 / E-010 | UF-003-007 | 1 | lib/nav/nav-render.sh `show_help` とフッタ… | 通過 |
| REQ-003-010 | Event-driven | VH-002 / UF-003-002 / E-004 | UF-003-002 | 2 | lib/common.sh `copy_session`、`start_cl… | 通過 |
| REQ-003-011 | Event-driven | VH-002 / UF-003-002 / E-005 | UF-003-002 | 1 | lib/common.sh `copy_session`(名前 `<name… | 通過 |
| REQ-003-012 | Event-driven | VH-002 / UF-003-002 / E-004 | UF-003-002 | 1 | lib/nav/nav-actions.sh `copy_selected`… | 通過 |
| REQ-003-013 | Ubiquitous | VH-002 / UF-003-002 / E-004 | UF-003-002 | 1 | lib/common.sh `copy_session`(元の metada… | 通過 |
| REQ-003-020 | Event-driven | VH-003 / UF-003-003 / E-007 | UF-003-003 | 1 | lib/nav/nav-jump.sh `_jump_assign_labe… | 通過 |
| REQ-003-021 | Event-driven | VH-003 / UF-003-003 / E-008 | UF-003-003 | 1 | lib/nav/nav-jump.sh `_jump_cell`(`NAV_… | 通過 |
| REQ-003-022 | Event-driven | VH-003 / UF-003-003 / E-007 | UF-003-003 | 1 | lib/nav/nav-jump.sh `jump_prompt` → `_… | 通過 |
| REQ-003-023 | Event-driven | VH-003 / UF-003-003 / E-009 | UF-003-006 | 1 | lib/nav/nav-jump.sh `_jump_assign_labe… | 通過 |
| REQ-003-024 | State-driven | VH-003 / UF-003-003 / E-007 | UF-003-003 | 1 | lib/nav/nav-jump.sh `NAV_JUMP_IDS`(f を… | 通過 |
| REQ-003-030 | Unwanted | VH-002 / UF-003-002 / E-006 | UF-003-005 | 1 | lib/nav/nav-actions.sh `copy_selected`… | 通過 |
| REQ-003-031 | Unwanted | VH-002 / UF-003-002 / E-006 | UF-003-005 | 2 | lib/nav/nav-actions.sh `copy_selected`… | 通過 |
| REQ-003-032 | Unwanted | VH-002 / UF-003-002 / E-004 | UF-003-005 | 1 | lib/common.sh `copy_session`(起動に失敗したら … | 通過 |
| REQ-003-033 | Unwanted | VH-001 / UF-003-001 / E-001 | UF-003-001 | 1 | lib/nav/nav-actions.sh `open_selected`… | 通過 |
| REQ-003-034 | Unwanted | VH-003 / UF-003-003 / E-009 | UF-003-006 | 1 | lib/nav/nav-jump.sh `jump_prompt`(Esc … | 通過 |
| REQ-003-035 | Unwanted | VH-003 / UF-003-003 / E-007 | UF-003-006 | 1 | lib/nav/nav-jump.sh `_jump_land`(行が消えて… | 通過 |
| REQ-003-036 | Unwanted | VH-003 / UF-003-003 / E-007 | UF-003-008 | 1 | lib/nav/nav-jump.sh `jump_prompt`(`_ju… | 通過 |
| REQ-003-037 | Unwanted | VH-001 / UF-003-001 / E-001 | UF-003-001 | 1 | lib/nav/nav-actions.sh `open_selected`… | 通過 |

## 穴

なし。全要求が UF・シナリオ・実装・実行結果まで繋がっている。

## 中核フローの要求

中核 13 件中 **13 件が通過**。
