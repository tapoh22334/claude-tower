---
id: TASK-5
title: 『compaction を fork と誤検出しない』保証を、テストで固定する
status: To Do
assignee: []
created_date: '2026-07-25 00:44'
updated_date: '2026-07-25 15:26'
labels:
  - fork-detection
dependencies: []
ordinal: 5000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
compaction(同一 sessionId でファイルが分かれるが uuid をファイル跨ぎで共有しない)は fork ではない、というのが設計の明示的な保証。だが、それを守るテストが無い。テストが無いと、fork 検出ロジックをいじった際に compaction を誤って fork と判定する回帰が入っても気づけず、履歴表示が壊れる。誤検出しないことを回帰テストで固定するのが目的。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 同一 sessionId・ファイル分割・uuid のファイル跨ぎ共有なし の状況で find_fork_parent が『親なし』を返すことを検証するテストがある
- [ ] #2 そのテストが test_fork_detection.bats にあり、通る
<!-- AC:END -->
