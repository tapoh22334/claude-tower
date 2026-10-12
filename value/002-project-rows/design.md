# 設計記録(O2) — 002-project-rows

engine: native。

- **見出しを行にする**(id `dir:<path>`、表示 = 見出し文字列)。「見出しは先頭行に乗る文字列」という旧モデルでは、カーソルが止まれず、削除時に見出しが隣グループへ渡る欠陥もあった。行にすると j/k・キャッシュ形式・楽観編集のすべてが単純になる。
- **台帳** `projects.list`(1 行 1 正規化パス、tmp+mv、flock)。セッション開始で自動登録、削除では残す、台帳が無ければ現在の見出しで初期化。
- **選択の第 2 種 `dir:`** を `selected` に入れる。読者を全部点検: view はカード、`nav_redirect_view` は id の形で先に判定(tmux の前方一致対策)、Tile/Tail/Queue は無選択扱い、list の resync は未一覧の `dir:` を「消えた行」として扱う。
- **見出しでのキー**は `handle_project_key` に集約し、移動とグローバルキーだけ既存の case に落とす。
- **D の件数**は画面上の行数と台帳の件数の大きい方(dead/lost を含め、`tower project rm` と揃える)。

詳細は `articulation.md`・`requirements.md`、逸脱は `deviations.md`。
