---
id: TASK-17
title: Tile ビューに実機での回帰テストを用意する
status: To Do
assignee: []
created_date: '2026-08-27 15:02'
labels:
  - test
  - tile
dependencies: []
ordinal: 17000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Tile の不具合が単体テストをすり抜けて 2 回起きている。TASK-6 (Tab が握り潰されて起動しない) と、今回の『window と attach 先が別セッションで、Tile が見えない』(d693a54 で修正)。どちらも 9 件ある tile.sh の単体テストは通ったまま素通りした。単体テストは関数を個別に見るので、tmux を挟んだ組み立ての誤りを捕まえられない。

今回 tests/integration/test_view_handoff.bats を追加して『window と attach 先が同一セッションか』は固定したが、これはハンドオフ 1 点のみ。Tile 自体の描画・操作・復帰は依然として実機で検証されていない。

未マージブランチ origin/003-simplify (最終更新 2026-06-11、main より古い設計) に、参考になるテストが 2 つある:
- tests/e2e/test_tile_live_client.bats — 実クライアントを繋いだ状態でのペイン高さの安定性、2 つ目の小さいクライアントが繋がってもレイアウトが崩れないこと、prefix+Tab での離脱
- tests/integration/test_tile_join_pane.bats — N セッションのタイル化と往復 (PID 同一性)、5 セッションで 'pane too small' が出ないこと、クラッシュしたペインのスキップ、複数ウィンドウのセッションのスキップ

ただしこれらは tile_collapse / tile_disband という 003-simplify 固有の関数を直接呼ぶ。あちらは join-pane 方式 (tile-exit.sh + tile-sweep.sh)、main は attach-session 方式 (tile.sh) で、実装が別物なのでそのままは動かない。検証している『性質』を借りて、main の tile.sh 向けに書き起こす作業になる。

このタスクが片付くまで origin/003-simplify は消さないこと (テストの唯一の出所)。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Tile を実機の tmux 上で起動し、落ちずにグリッドが描画されることがテストで固定されている
- [ ] #2 セッション数が画面に収まらない場合 (6 件超) の挙動がテストで固定されている
- [ ] #3 Tile から list ビューへ戻ったとき、選択が保たれることがテストで固定されている
- [ ] #4 追加したテストが、修正前のコードに対して実際に失敗することを確認済み
<!-- AC:END -->
