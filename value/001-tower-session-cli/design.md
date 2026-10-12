# 設計記録(O2) — 001-tower-session-cli

engine: native。計画は会話中の暫定裁定として記録し、ここにまとめる。

- **CLI が正、スキルは利用者**: 3 コマンドは `tower` のサブコマンド。契約は「stdout は id のみ / 対話確認なし / 終了コード 2=使い方・1=実行時」。スキル `skills/tower` はこの契約だけに依存する。
- **rename は単一キーの原子的書き換え**(`set_session_name`、`record_live_id` と同型)。`save_metadata` は全体上書きで `created_at` を再スタンプし、再構築が途中状態を読む。
- **「自分」の解決**は `$TMUX` のソケット名が `TOWER_SESSION_SOCKET` と一致するときだけ `TMUX_PANE` から(`current_tower_session`、`-S` で同じサーバに問い合わせ)。
- **open のプロンプトはファイル経由**: `<id>.prompt` を保存し、起動行は `claude --session-id X "$(cat <file>)"`。引用符・`$`・改行がシェル引用を通らない。空白のみ・100 KiB 超は CLI が断る。
- **Navigator への通知**: `set_nav_selected` + Navigator があれば `nav_redirect_view`。list ループの resync は未一覧の id を区別して即時再構築(レビュー指摘)。
- **project new は `git init` まで**。GitHub 作成は非スコープ。

詳細は `articulation.md`(分節)と `requirements.md`、逸脱は `deviations.md`。
