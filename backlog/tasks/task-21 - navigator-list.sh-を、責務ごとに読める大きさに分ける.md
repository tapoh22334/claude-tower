---
id: TASK-21
title: navigator-list.sh を、責務ごとに読める大きさに分ける
status: To Do
assignee: []
created_date: '2026-09-07 08:39'
labels: []
dependencies: []
ordinal: 21000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
navigator-list.sh が約1470行あり、CLAUDE.md が掲げる『Files under 500 lines』を大きく超えている。この一つのファイルに、行のレンダリング、バックグラウンド再構築とキャッシュ、キー入力ループ、削除・追加の各サブフローが同居していて、どれか一つを変えるときに全体を読む必要がある。実際この規模ゆえに、削除マークの実装ではサブシェルによる変更破棄を見落とした(直接呼ぶユニットテストは全て通っていた)。既存の違反であり特定の機能追加の産物ではないので、機能作業のついでではなく独立して扱う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 navigator-list.sh が 500 行以下になる
- [ ] #2 分割後も既存の bats テストが、ベースラインと同じ結果で通る
- [ ] #3 各ファイルの責務が、先頭のコメントで一言で言える
<!-- AC:END -->
