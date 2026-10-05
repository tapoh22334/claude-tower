# 逸脱報告(O6) — 001-tower-session-cli

要求・分節・非スコープからの逸脱と、構築中に下した裁定。

| # | 内容 | 種別 | 理由 / 影響 |
|---|---|---|---|
| 1 | エラー文言は英語(要求本文の日本語は意味の記述として扱った) | 裁定 | 既存 CLI の文言がすべて英語で、混在させない。受入は "--session" / "typo" / "lready exists" のトークンで判定 |
| 2 | `generate_uuid` を session-add.sh から lib/common.sh へ移動 | 内部変更 | 3 スクリプトで共有するため。session-add.sh の挙動は不変。これに依存していた tests/test_session_dashboard.bats の eval 型テストを、lib を後から source する形に修正(テストの前提の修正であり、製品の回帰ではない) |
| 3 | `delete_metadata` が `<id>.prompt` も削除する | 追加 | open が残すプロンプトファイルの後始末。要求外だが非スコープにも当たらず、残すと metadata dir にゴミが溜まる |
| 4 | spec-kit エンジンを使わず native(TDD)で構築 | 裁定 | vf-construct のアダプタ/`verify-contract.sh` がこの環境に無い。O1〜O6 は手で揃えた(本ディレクトリ) |
| 5 | `tower open` の view 切り替えは「Navigator セッションが存在するとき」のみ試みる | 要求どおり | REQ-001-028。失敗しても成功扱い(`|| true`) |
| 6 | スキルの symlink は `~/.claude/skills/tower` に直接作成(dotfiles には入れていない) | 裁定 | dotfiles 管理下に入れるかは利用者の判断。README に手順を記載 |

非スコープ違反の点検: `gh` 呼び出しなし / 空プロジェクト台帳なし / 元セッションを閉じる処理なし /
Navigator の UI 追加なし / CLAUDE.md・Issue 初期化なし。`tower project add` は実装していない。

## レビュー(tower-reviewer)後の追補

| # | 内容 | 種別 | 理由 |
|---|---|---|---|
| 7 | list ループの resync: `selected` が一覧に無い id なら index を動かさず `_spawn_background_rebuild force` | 欠陥修正(CONFIRMED) | CLI が未一覧の id を書くと `get_selection_index` が 0 を返し、ハイライトが先頭行へ飛んで Enter/D が新 id に作用する窓(≤2 s)ができていた |
| 8 | `prompt_to_file` が cat 失敗・空白のみ・100 KiB 超を exit 1 で拒否(REQ-001-029 を追加) | 欠陥修正(CONFIRMED) | 空の `""` 位置引数や `argument list too long` が pane 側で起き、CLI は成功を返していた |
| 9 | `current_tower_session` は `$TMUX` のソケット path(`-S`)に問い合わせる | 堅牢化(PLAUSIBLE) | `-L 名前` は呼び手の `TMUX_TMPDIR` で解決され、別サーバに届き得る |
| 10 | `set_session_name` の `mv` を if/then に | 堅牢化(PLAUSIBLE) | `set -e` を保つ呼び手(将来の Navigator キー)が mv 失敗で死なないように |
