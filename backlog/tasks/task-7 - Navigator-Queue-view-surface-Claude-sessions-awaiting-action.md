---
id: TASK-7
title: 'Navigator Queue view: surface Claude sessions awaiting action'
status: Done
assignee: []
created_date: '2026-07-25 03:38'
updated_date: '2026-07-25 03:54'
labels: []
dependencies: []
ordinal: 7000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Fourth Navigator view (after list/tile/tail) that collects every Claude session waiting on the user and shows them as a queue, ordered oldest-wait-first, so nothing that is blocked or finished gets forgotten. Visualization only — no auto-response this scope. Detection is two-tier: process state file (~/.claude/sessions/<pid>.json status) plus pane capture for permission/question prompts on Tower-managed sessions; Tower-external sessions are detected coarsely (idle=waiting) since their pane can't be captured.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Pressing 'w' from the list view opens the Queue view
- [x] #2 Queue lists sessions in these wait states: input-wait (finished, idle), permission-prompt, question, error/stopped
- [x] #3 Rows are ordered by wait duration, longest wait first
- [x] #4 Each row shows a wait-kind icon, the session label, and how long it has waited
- [x] #5 Selecting a row (Enter or 1-9) returns to the list view focused on that session, same handoff as tile/tail
- [x] #6 Permission/question detection works for Tower-managed sessions via pane capture; external sessions fall back to a coarse idle=waiting signal
- [x] #7 Frame never exceeds terminal height (no endless-scroll), width capped like the list view
- [x] #8 New bats tests cover wait-state classification and queue ordering; make test-docker green
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Implemented the Queue view (PR #19, merged to main 237698e). Two-tier wait detection in claude-sessions.sh (classify_pane_wait / get_wait_state / wait_since), queue-view.sh rendering ordered by wait duration desc, w key wired in navigator-list.sh. Verified: 21 new bats tests (classification of all 4 wait signatures incl. esc-to-interrupt skip, tier fallbacks, ordering, frame height/overflow), full Docker gate green (533/533), and a live-data preview showing 12 waiting sessions ordered 5d→1m with aligned ages.
<!-- SECTION:FINAL_SUMMARY:END -->
