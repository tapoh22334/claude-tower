---
id: TASK-23
title: 'Navigator の n → [new] でディレクトリ入力が見えず補完も効かない'
status: Done
assignee: []
created_date: '2026-09-12 11:23'
updated_date: '2026-09-12 11:35'
labels:
  - bug
dependencies: []
priority: high
ordinal: 23000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Navigator から n → [new] を選んだ後の Directory / Name / y-N プロンプトで、打った文字が画面に出ない。さらにパスの Tab 補完が効かず、新規ディレクトリの指定が手探りになる。

原因: Navigator は自身のキー入力が画面に漏れないよう stty -echo にしており、session-add.sh のプロンプトはそれを戻さない(fzf は termios を『元の状態』= echo off に復元するので fzf を通っても直らない)。補完は素の read -r で readline を使っていないため。

やること: 対話プロンプトの直前に端末エコーを戻す(Navigator は復帰時に自分で切り直す)。ディレクトリ指定は fzf があれば候補(既定 dir・その直下・既知プロジェクト)をプレビュー付きで選べ、打ち込んだ文字列をそのまま新規パスとしても使える形にする。fzf が無ければ read -e で readline のファイル名補完を使う。
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
原因: Navigator は自分のキー入力(j/k)が一覧に描かれないよう stty -echo で走り、その状態のまま session-add.sh に端末を渡す。session-add.sh の read -r はエコーを戻さず、fzf も『見つけた termios(=echo off)』を復元するので直らない。補完が効かないのは素の read -r で readline を使っていなかったため。fzf は必須ではない(数字ピッカーへのフォールバックあり)。

直し方(session-add.sh):
- 端末プロンプトを read_line 1本に集約。読む前に stty echo を戻し、read -e で readline(Tab のファイル名補完)を使う。Navigator 側は復帰時に _return_from_subflow が echo を切り直すので、責務の境界はそのまま。
- [new] のディレクトリ指定は fzf があれば候補(既定 dir → その直下 → 既知プロジェクト dir)をツリープレビュー付きで選べる。打った文字列に一致が無ければ Enter(または Ctrl-N)でそれを新規パスとして扱い、従来どおり作成確認 → mkdir -p。'+' の worktree ヘルパーも同じ経路で残した。
- fzf 無し / TOWER_FINDER が fzf 以外 / tty 無しのときは readline プロンプト。補完は既定 dir を cwd にして行うので、相対入力の解釈(既定 dir 基準)と一致する。fzf のエラー終了(exit 2)は『既定を採用』と誤読せず失敗にする。
- main を BASH_SOURCE ガードで包み、TOWER_TTY 環境変数でプロンプトの読み元を差し替えられるようにしてテストから直接駆動できるようにした(既存テストの sed 抽出ハックを置換)。

検証: tests/test_session_add.bats に pty(script)で echo 復活を確認するテスト含め 16 本追加、全 607 テスト green(main の baseline も 0 fail)。tmux 使い捨てサーバー上で fzf ピッカー(選択・新規パス作成・プレビュー)と readline フォールバック(Tab 補完)の実機確認済み。
<!-- SECTION:NOTES:END -->
