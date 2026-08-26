---
id: decision-1
title: Navigator は Bash + tmux のまま維持し、TUI ライブラリへ移行しない
date: '2026-08-26 15:03'
status: accepted
---
## Context

Navigator の UI はおよそ 2,600 行の Bash で、ANSI エスケープと tput を直書き
している。ちらつき・操作の重さ・機能追加のしにくさを理由に、Go や Rust の TUI
ライブラリ (bubbletea / ratatui) へ移す案を検討した。

実在する tmux プラグイン 15 個を調べたところ、次が分かった。

- スター上位はほぼ全て Shell で、かつ UI を持たない。UI を持つプラグインは
  自前描画ではなく fzf 委譲 (tmux-fzf 1.5k, extrakto 1.1k) か tmux 組み込みの
  display-menu (tmux-menus) が主流。
- 自前 ANSI 描画は tmux-thumbs と tmux-fingers だけで、どちらもヒント文字の
  オーバーレイという単純な用途。リスト+プレビューの複合 UI を自前で描いている
  著名プラグインは見つからなかった。
- TPM は git clone と source しかせず、ビルドステップも post-install フックも
  ない。そのためバイナリ配布のプラグインは全員が独自インストーラを書いており、
  実際のリリースアセットは tmux-thumbs が 2 種 (Apple Silicon なし)、
  tmux-fingers が 2 種 (Linux arm64 も macOS x86_64 もなし)。残りのユーザーは
  ソースビルドに落ち、「install loop」「github API rate limit breaks install
  wizard」「Consider adding pre-built binaries for macOS」といった issue が
  実際に立っている。単体 CLI として配る sesh は 8 種、gitmux は 5 種を用意して
  おり、sesh は README で自らを "not a tmux plugin" と明言している。

決定打は tmux 側の制約だった。man tmux 3.6a に "Panes are not updated while a
popup is present" とある。Tower の右ペインは入れ子の tmux が本物のセッションに
attach しており、見ながらそのまま入力できる。これは popup でも fzf --preview
でも再現できず、TUI ライブラリが画面を管理する構造とも両立しない。

あわせて、移行の動機だった重さは TASK-16 で解消した。外部コマンド起動を
1584→275 回 (-82%)、実時間 7.2→2.5 秒 (-65%)、アイドル時の再構築を 12 秒あたり
24→3 回に削減している。原因は描画層ではなく、セッションごとに stat を起動して
いたデータ取得側だった。

## Decision

Navigator は Bash + tmux のまま維持する。TUI ライブラリへは移行しない。

右ペインのライブ attach を手放さないことを前提条件とする (利用者の明示的な
判断)。これを維持する限り、TUI ライブラリでも fzf 委譲でも代替できない。

## Consequences

描画・幅計算・キー入力の面倒は今後も自前で見ることになる。パフォーマンスの
問題は描画層ではなくデータ取得側に出るので、同種の症状が再発したら TASK-16 と
同じく execve 数を strace で数えるところから入るのがよい。

Tile / Tail / Queue の 3 ビュー (計 820 行) は「移動して選んで戻る」だけで、
入力も対話もない。fzf の得意分野そのものなので、委譲する余地は残っている。
この決定はそこまでは否定しない — 否定するのは Navigator 本体の置き換えである。

前半のブレストで挙がった機能 (/ 検索ジャンプ、手動命名、n のモード分離と
パス補完) は Bash で実装することになる。fzf の --print-query を使えば入力欄を
自前で書かずに済む道もあり、必要になった時点で個別に判断する。
