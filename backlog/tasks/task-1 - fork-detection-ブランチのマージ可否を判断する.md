---
id: TASK-1
title: fork-detection の成果を main に取り込むか、破棄するかを確定させる
status: To Do
assignee: []
created_date: '2026-07-25 00:43'
updated_date: '2026-07-25 15:26'
labels:
  - fork-detection
  - blocked
dependencies: []
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
fork 検出機能(_fork_label / list_fork_sessions / find_fork_parent)は feature/fork-detection 上で検証・レビュー済みだが、main には未反映のまま宙に浮いている。この判断が下りないと、機能が使えないだけでなく、後続の整理・テスト(TASK-2〜5)も全て着手できず、ブランチが古びてマージがさらに難しくなる。放置コストが時間とともに増すのが実害。判断材料は Implementation Notes に集約済み(現 tip・main との差分・想定コンフリクト箇所)。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 main へ取り込む / 破棄する のいずれかが決定され、実行される
- [ ] #2 取り込む場合、想定される claude-sessions.sh のタイトル生成部のコンフリクトが解消されている
- [ ] #3 決定後、このブランチが宙に浮いた状態でなくなる(マージ済み or 削除済み)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-07-25 追記 (事実更新のみ、マージ判断は未実施):
- 記載の tip bd33482 は古い。feature/fork-detection の現在の tip は 6cb0641。
- ブランチにはその後 409b378 'fix: fork rows showed Claude's raw command expansion as the title' が積まれている。
- ただしこのタイトル修正は main 側にも別途移植済み (ba34b56 / TASK-8)。main では find_session_jsonl が独自に書き換わっていたため cherry-pick ではなく手で移植した。したがってマージ時は claude-sessions.sh のタイトル生成部分がコンフリクトする可能性が高い。
- fork 検出本体 (_fork_label / list_fork_sessions / find_fork_parent) は main に未反映のままで、TASK-2〜5 はいずれもこのブランチがマージされて初めて着手可能。

2026-07-25 追記 (push 状況とtipの中身):
- 現tip 6cb0641 は TASK-6 のタイルモード修正 (Tabキーが IFS で握り潰されていた件 +
  起動失敗のサイレント握り潰し)。fork検出とは独立した修正で、
  navigator-list.sh / tile.sh / tail-view.sh のキー読み取りと
  switch_to_tile/switch_to_tail に触れている。
- feature/fork-detection を origin に push 済み (これまで remote 未存在だった)。
  以後どこからでも取得可能。PRは未作成。
- マージ判断時の注意: このブランチは main に対し11コミット差があり、
  fork検出本体 + タイルモード修正が同居している。タイルモード修正は
  fork検出のマージ可否とは独立に価値があるため、fork検出側を破棄する判断に
  なった場合でも 6cb0641 だけは main に取り込む価値がある (cherry-pick 可能)。
- 既知のコンフリクト予測は前回追記のとおり claude-sessions.sh のタイトル生成部。
<!-- SECTION:NOTES:END -->
