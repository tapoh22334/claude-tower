---
id: TASK-1
title: fork-detection の成果を main に取り込むか、破棄するかを確定させる
status: To Do
assignee: []
created_date: '2026-07-25 00:43'
updated_date: '2026-08-26 15:10'
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

2026-08-27 コードレビュー結果 (feature/fork-detection の 11 コミットが対象)。マージ可否の判断材料として記録する。

未検証の指摘なので、着手時に各項目を実際に確かめること。私が main 側で検証した 13 件中 2 件は誤検出だった (無限ループの主張は実際には起きない、空タイトルの主張は原因が別の場所) ので、この一覧も鵜呑みにしない。

【性能】fork 行の描画が、直前に TASK-16 で潰したプロセス生成の問題を戻す可能性がある。list_fork_sessions → find_fork_parent が live な未登録プロセスごとに slug ディレクトリ内の全 *.jsonl を grep し、さらに fork 行ごとに get_session_title が走る。指摘では『10 セッション × 30 兄弟ファイル = 1 リフレッシュあたり 300 回の grep』。TASK-16 で 1584→275 回まで落とした直後なので、マージ前に strace -f -e trace=execve で実測すべき。

【正しさ】find_fork_parent (claude-sessions.sh:56) の tie-break が非決定的。比較が ((cand_mtime >= best_mtime)) と >= なので、mtime が同一の候補群では『最後に走査されたもの』が勝つ。glob 順は UUID の辞書順で、fork の親子関係とは無関係。親の直後に fork を作ると mtime が同秒になりやすく、まさにこの条件を踏む。TASK-3 が『非決定的である旨をコードに残す』としているが、レビューは実害があると見ている。

【正しさ】_FORK_SCAN_LINES の grep -o -m 5 は『最初の 5 uuid』ではなく『マッチを含む最初の 5 行』を意味する。同じ -m 5 を親候補側にも適用しているため、前置きの長い親では共有 uuid が 5 行目より後ろにあり、本物の fork が黙って検出漏れする。

【安全性】D (削除) が fork 行を守っていない。r (resume) は fork 行を判定して弾くよう直されたが、delete_selected は $selected が登録済み tower セッションか確認せずに session-delete.sh を呼ぶ。fork 行は登録されていない生の Claude sessionId なので、未登録 id に対して削除が走る。

【UI】fork 行が SESSION_IDS に混ざることで、リビルド間に fork が消えるとカーソル位置が別セッションを指す。既存のクランプは index >= len しか見ておらず、範囲内で中身が変わるケースを扱わない。set_nav_selected も呼ばれないので、リストと右ペインの認識がずれる。

【UI】fork 行で r を押したときの sleep 0.5 が、隣接する未登録パスの sleep 0.3 より長く、r を押しっぱなしにするとループが目に見えて止まる。
<!-- SECTION:NOTES:END -->
