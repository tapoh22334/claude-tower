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
