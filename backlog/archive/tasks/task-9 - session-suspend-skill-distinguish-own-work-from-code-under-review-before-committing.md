---
id: TASK-9
title: >-
  session-suspend skill: distinguish own work from code-under-review before
  committing
status: To Do
assignee: []
created_date: '2026-07-25 11:28'
labels: []
dependencies: []
ordinal: 9000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Found during the skill's own eval (iteration-2, review-resume case). The suspend ritual's step 1 commits any uncommitted change to a branch, but it does not distinguish two cases: (a) the diff is MY work-in-progress → commit and land it; (b) the diff is the PR author's code I'm REVIEWING → committing it is wrong; I should leave it (or stash) and only record which diff I was reviewing. In the eval, the baseline (no skill) correctly refused to commit the reviewee's code, while the skill mechanically committed it. The skill overfits 'always commit uncommitted work'.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 SKILL.md step 1 tells the model to check whether the uncommitted diff is its own work or code under review, and to NOT commit code under review
- [ ] #2 A re-run of the review-resume eval shows the skill leaving the reviewee's diff uncommitted while still recording the review resume point
<!-- AC:END -->
