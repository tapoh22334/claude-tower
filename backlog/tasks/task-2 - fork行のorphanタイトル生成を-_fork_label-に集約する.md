---
id: TASK-2
title: 親未登録の fork 行のタイトルが、他の行と同じ規則で表示されるようにする
status: To Do
assignee: []
created_date: '2026-07-25 00:44'
updated_date: '2026-07-25 15:26'
labels:
  - fork-detection
dependencies: []
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
fork 行のうち、親セッションが Tower に未登録の『orphan』な行だけ、タイトル生成が共通の _fork_label を通らず短縮ID生成を独自に再実装している。同じ『fork 行のタイトル』が2つの経路で作られている状態で、片方を直してももう片方が古びる危険がある。表示規則を一本化して、将来の食い違いを防ぐのが狙い。レビューの Minor 指摘。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 orphan fork 行も、他の fork 行と同一の経路(_fork_label)でタイトルが生成される
- [ ] #2 既存の fork 検出テスト(7件)が引き続き通る
<!-- AC:END -->
