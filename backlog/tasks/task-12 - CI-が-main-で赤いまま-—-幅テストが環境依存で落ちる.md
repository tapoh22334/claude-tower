---
id: TASK-12
title: CI が main で赤いまま — 幅テストが環境依存で落ちる
status: To Do
assignee: []
created_date: '2026-08-02 07:46'
updated_date: '2026-08-02 08:52'
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
<!-- SECTION:NOTES:END -->
