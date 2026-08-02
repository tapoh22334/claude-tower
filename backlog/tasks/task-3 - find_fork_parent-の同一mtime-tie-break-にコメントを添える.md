---
id: TASK-3
title: 同一 mtime の親候補が並んだときの選択順が非決定的である旨を、コードに残す
status: To Do
assignee: []
created_date: '2026-07-25 00:44'
updated_date: '2026-07-25 15:26'
labels:
  - fork-detection
dependencies: []
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
find_fork_parent は、親候補が複数あって mtime が同一秒のとき、どれを最近親に選ぶかが glob の列挙順に依存する=環境次第で結果が変わりうる。実害が出るのは稀だが、この非決定性を知らずに読んだ人が『なぜここでこの親?』と混乱する、あるいは決定的だと誤解してテストを書く恐れがある。挙動そのものは変えず、『ここは同一 mtime 時に非決定的』と分かる印をコードに残すのが目的。レビューの Minor 指摘。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 find_fork_parent の該当箇所を読んだ人が、同一 mtime 時の選択が非決定的だと分かる
<!-- AC:END -->
