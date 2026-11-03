# 設計記録(O2) — 003-nav-keys

engine: native。

- **行に作用するキーは Enter と D だけにする。** Enter は行の状態で振る舞いを変える。動いている行は焦点を移し、休眠中の行は `restore_selected` で再開し、焦点を移す。外部の行と未登録の行は焦点を移すだけにする。`r` と `i` はこれで要らなくなる。再開は画面の行と selected ファイルの id が一致するときだけ行う。
- **見出しの行では `handle_project_key` が Enter と D だけを引き受ける。** ほかのキーは 1 を返し、通常の case に落ちる。見出しの行でもセッション行でも、同じキーは同じ意味になる。
- **copy は CLI の一経路にする。** `session-copy.sh` → `copy_session`(lib/common.sh)→ `start_claude_session` の mode `copy` の順に呼ぶ。起動するのは `claude --resume <元の claude id> --fork-session --session-id <新しい id>` である。作業ディレクトリは transcript から取る(CLAUDE.md の方針)。metadata は起動に成功した後で保存する。Navigator 側は `_remember_session_row` で `◐` の行を先に入れる。
- **ラベルジャンプは独立のファイル `nav-jump.sh` に置く。** `/` 検索と同じく、自前の読み取りループで描き直す。ラベルは `f` を押した時点の行 id に結び付けて固定する。着地は id で引くため、一覧が更新されても別の行へは飛ばない。描画はラベル列(3 セル)を行の前に置き、行は同じ幅だけ余白から詰める(`_jump_fit`)。
- **`a` の場所の初期値**は `_add_default_dir` で求める。見出しの行ならそのディレクトリを使う。セッション行ならそのセッションのディレクトリを使う。どちらでもなければ呼び出し元の cwd を使う。

詳細は `articulation.md` と `requirements.md` を、逸脱は `deviations.md` を参照する。
