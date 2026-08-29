---
id: TASK-12
title: CI が main で赤いまま — 幅テストが環境依存で落ちる
status: Done
assignee: []
created_date: '2026-08-02 07:46'
updated_date: '2026-08-29 16:40'
labels:
  - bug
  - ci
dependencies: []
priority: high
ordinal: 12000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
2026-07-20 以降、main への push が 5 回連続で CI 失敗している。公開リポジトリの main に赤バッジが出続けている状態。

失敗しているのは 1 件だけ: tests/test_list_columns.bats の 'build_session_list: header rule fills to the cap, not the raw terminal'。CI では 'not ok 213'、手元の bats 1.13.0 では ok。つまりテスト対象の不具合ではなく、テストが環境に依存している。

原因: _content_width() (navigator-list.sh:76-81) は tput cols をコマンド置換 $(...) の中で呼ぶ。テストは tput をシェル関数で差し替えて 140 を返させるが、この関数がサブシェルに届くかは bats/bash のバージョンと実行形態で変わる。CI (apt の bats) では届かず実端末幅が使われ、アサーション 80 < len < 260 の外に出る。手元では 219 バイトで通る。

直し方には設計判断が要る: (a) _content_width が環境変数 (TOWER_LIST_MAX_WIDTH など既存のもの) を見る形にしてテストから制御可能にする、(b) tput 呼び出しをサブシェル外に出す、(c) アサーションを緩める。(c) は本来の意図 (キャップが効いていること) を検証しなくなるので避けたい。

付随して見つかった環境の綻び: CLAUDE.md は bats を 'submodule at tests/bats/' と書いているが .gitmodules は存在せず tests/bats も無い。CI は apt install bats で用意している。新規コントリビューターが CLAUDE.md 通りにしても動かない。
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-08-02: リポジトリ整理の 4 コミットを push 後も同じ状態を確認 (run 30740544462)。失敗は依然この 1 件のみで、同時に追加した 40 テストは CI 上でも全て通っている。つまりこの失敗は今回の変更とは独立した既存問題。Unit Tests と Docker Tests がこれ 1 件で赤くなり、E2E / Integration / ShellCheck は緑。

2026-08-30 健全性調査で判明: この問題は『CI で 1 件落ちる』より広い。

同じ tput 依存が、ローカルでも実行のたびに結果を変えるフレーキーを起こしている。tests/test_coverage_gaps_9.bats を 4 回連続実行した実測:

  run1: ok=15  run2: ok=14  run3: ok=16  run4: ok=13   (いずれも '1..17' 宣言)

毎回 'bats warning: Executed N instead of expected 17 tests' が出る。not ok (アサーション失敗) ではなく、テストが実行されずに消える。消えるのは render_list を通るテストの直後。

原因の裏付け: TERM=dumb COLUMNS=80 LINES=24 に固定して同じファイルを 3 回走らせると ok=16 で完全に安定した (変動なし)。tput が制御端末の有無で異なる値を返すことが原因と確定。

該当箇所は navigator-list.sh の tput 直接呼び出し 3 箇所 (_content_width の tput cols、render_list の tput lines、tput ed)。tests/test_helper.bash には TERM や tput のスタブ、固定端末サイズの用意が一切ない。

なお全スイート (bats tests/*.bats) では 511/0 で安定するため、この問題は個別ファイル実行時に顕在化する。CI は個別ジョブで走るので影響を受ける。

対処の方向: TASK-12 を『幅テスト 1 件の修正』ではなく『tput 依存をテストから注入可能にする』として扱うべき。test_helper.bash 側で tput をスタブして固定サイズを与えれば、このクラスのフレーキーが一括で消える見込み。

副次的に見つかった別件: tests/integration/test_display_snapshot.bats でも not ok 9-12 が出ることがある (Sessions / proj-alpha / unrecoverable の文字列が出力に現れない)。根本原因は同じ tput 依存と見られる。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
tput 依存を _term_cols/_term_lines に集約し、tput が答えられない環境では TOWER_TERM_COLS/LINES にフォールバックするようにした。test_helper.bash が 80x24 を固定。tput を先に試すので既存のスタブ方式テストはそのまま動く。検証: test_coverage_gaps_9.bats を5回連続実行して全て同一結果 (修正前は 15/14/16/13 と変動し毎回 'Executed N instead of expected 17' が出ていた)。全スイートの実行数が 512→525 に増え (消えていたテストが復活)、未完走警告はゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
