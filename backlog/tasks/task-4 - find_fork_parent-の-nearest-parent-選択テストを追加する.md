---
id: TASK-4
title: 『最も近い親が選ばれる』という設計保証を、テストで固定する
status: To Do
assignee: []
created_date: '2026-07-25 00:44'
updated_date: '2026-07-25 15:26'
labels:
  - fork-detection
dependencies: []
ordinal: 4000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
複数の古い候補が uuid を共有するとき、find_fork_parent は『子に mtime が最も近い候補』を親に選ぶ設計。これは意図した挙動だが、それを守るテストが無い。テストが無いと、将来のリファクタで nearest-wins がうっかり壊れても気づけない。設計上の約束を回帰テストで固定し、壊れたら検知できるようにするのが目的。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 複数の古い共有uuid候補がある状況で、子に最も近い候補が親として返ることを検証するテストがある
- [ ] #2 そのテストが test_fork_detection.bats にあり、通る
<!-- AC:END -->
