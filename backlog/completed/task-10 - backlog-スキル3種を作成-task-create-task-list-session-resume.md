---
id: TASK-10
title: 'backlog スキル3種を作成: task-create / task-list / session-resume'
status: Done
assignee: []
created_date: '2026-07-25 11:48'
updated_date: '2026-07-25 11:48'
labels: []
dependencies: []
ordinal: 10000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
session-suspend の意味論・KISS 思想を backlog タスク操作に展開した3スキルを ~/.claude/skills/ に作成。task-create は『手順(how)ではなく目的+理由(outcome+why)で書き、一枚に一つの結果に絞る』。task-list は状況が一目でわかる状態別一覧。session-resume は suspend の対で、残された記録から再開する。subagent 評価(with/without 各3ケース)で task-create の優位を実証: multi-scope ケースで with-skill は3タスクに分割、baseline は1タスクに詰め込んだ。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 3スキルが ~/.claude/skills/ に存在し、システムのスキル一覧に登録されている
- [ ] #2 task-create の評価で、複数成果の要望を別タスクに分割する挙動が baseline より優れることが確認済み
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
3 skills created and evaluated. Eval workspace: ~/.claude/skills/backlog-task-create-workspace/iteration-1 (benchmark delta +0.11, discriminating case = multi-scope split 3-vs-1).
<!-- SECTION:FINAL_SUMMARY:END -->
