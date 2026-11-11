# トレーサビリティ報告 — 004-nav-r-start

> この文書は `generate-trace.py` の生成物。**手で編集しない。**
> 直したくなったら元の ID かスクリプトを直す。

- 要求 9 件 / ユーザフロー 3 件 / シナリオ 6 件
- 実行結果: 20261111-145238
- 穴: **0 件**

## 追跡表

| 要求 | 型 | 由来 | UF | シナリオ | 実装 | 結果 |
|---|---|---|---|---|---|---|
| REQ-004-001 | Event-driven | VH-001 / UF-004-001 | UF-004-001 | 1 | lib/nav/nav-loop.sh の `r` の分岐 → lib/na… | 通過 |
| REQ-004-002 | Event-driven | VH-002 / UF-004-002 | UF-004-002 | 1 | lib/nav/nav-start.sh `start_under_curs… | 通過 |
| REQ-004-003 | Event-driven | VH-002 / UF-004-002 | UF-004-002 | 1 | lib/nav/nav-start.sh `start_under_curs… | 通過 |
| REQ-004-004 | Ubiquitous | VH-001, VH-002 | UF-004-001,UF-004-002 | 2 | lib/nav/nav-start.sh `_state_is_starta… | 通過 |
| REQ-004-005 | Ubiquitous | VH-001 | UF-004-001 | 1 | lib/nav/nav-render.sh `show_help` e2e,… | 通過 |
| REQ-004-010 | Unwanted | VH-001 | UF-004-003 | 1 | lib/nav/nav-start.sh `_unstartable_rea… | 通過 |
| REQ-004-011 | Unwanted | VH-002 | UF-004-002,UF-004-003 | 1 | lib/nav/nav-start.sh `start_under_curs… | 通過 |
| REQ-004-012 | Unwanted | VH-001, VH-002 | UF-004-001,UF-004-002 | 2 | lib/nav/nav-start.sh `_start_one_sessi… | 通過 |
| REQ-004-013 | Unwanted | VH-001 | UF-004-001 | 1 | lib/nav/nav-start.sh `start_under_curs… | 通過 |

## 穴

なし。全要求が UF・シナリオ・実装・実行結果まで繋がっている。

## 中核フローの要求

中核 7 件中 **7 件が通過**。
