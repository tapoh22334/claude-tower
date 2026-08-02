---
id: TASK-13
title: Navigator 起動時に、端末を失った古いプロセスを掃除する
status: To Do
assignee: []
created_date: '2026-08-02 07:51'
labels: []
dependencies: []
ordinal: 13000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
busy-loop 本体は PR #20 で根治したが(端末喪失を検知して自滅するようになった)、修正前に生まれた既存の孤児プロセスは残ったままで、次に自滅するまでは CPU を食い続ける。実際に8日間 40% CPU を焼く孤児が観測された。ユーザーが tmux を落とすたびに孤児が増える運用実態を踏まえ、Navigator 起動時に『端末を失った古い navigator-list.sh プロセス』を検出して片付ければ、暴走が累積せず、再起動するだけで健全な状態に戻せる。今は手動 kill が必要なのが実害。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Navigator 起動時、tmux ペインから切り離された既存の navigator/view プロセスが検出され、終了される
- [ ] #2 稼働中の正規の Navigator や他ユーザー/他ソケットのプロセスは誤って kill されない
<!-- AC:END -->
