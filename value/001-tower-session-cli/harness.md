# Claude セッションの中から Tower を操作する — 品質ハーネス

feature-id: 001-tower-session-cli

> ゲートは「防ぐ欠陥クラス」に紐づいていなければ儀式。紐づかないものは外す。

## 検知したい欠陥クラス

この repo で実際に起きたものから選ぶ(2026-09 の一連の修正、tower-reviewer の
定義、`.claude/agents/tower-reviewer.md` と memory に記録)。

| ID | 名称 | 症状 | 実績 | 検知する工程 | 費用 |
|---|---|---|---|---|---|
| DEF-T1 | 引用の層の取り違え | `%q` / 単一引用が tmux `run-shell` → sh → `$SHELL -c` のどこかで壊れる | #62 で 2 回 | 単体テスト(生成コマンド文字列)+ 実 tmux の受入 | 低 |
| DEF-T2 | 継承された `set -e` によるループ死 | common.sh の `set -euo pipefail` を受け継ぎ、素の `return` や失敗した `[[ ]] &&` で死ぬ | #60/#62/#65 | shellcheck では見えない。tower-reviewer + 「set -e 下で生き残る」テスト | 低 |
| DEF-T3 | metadata の非原子的書き換え | 再構築が途中状態を読む / `created_at` が再スタンプされ「starting」に戻る | `save_metadata` の既知の性質(#43 で `record_live_id` が回避) | 単体テスト(他キー保持・tmp+mv) | 低 |
| DEF-T4 | テストが本物の状態に触る | `/tmp/claude-tower` や利用者の tmux サーバを壊す | #41 | test_helper の隔離に乗る。受入ランナも per-run socket | 低 |
| DEF-T5 | 共有状態と画面の不一致 | `selected` を書いたのに view が追従しない | #35/#39/#40 | 受入(Navigator 起動時に view が切り替わる)+ tower-reviewer | 中 |
| DEF-T6 | 対話プロンプトがスキルを止める | tty の無い呼び出しで `[y/N]` 待ちになる | #23/#64 の系統 | 単体テスト(stdin を閉じて完走) | 低 |
| DEF-T7 | stdout/stderr の混在 | 機械可読出力に人向け文言が混ざり、呼び出し側が id を取れない | session-add の `--print-id` 導入時 | 単体テスト(stdout が id 1 行だけ) | 低 |

## ゲート配置

| ゲート | 位置 | 判定方法 | 防ぐ欠陥クラス | 費用 | 採否 |
|---|---|---|---|---|---|
| GATE-value-falsifiable | orient 出口 | 外れ判定の有無(3 仮説とも記入済み) | — | 低 | 採用 |
| GATE-articulation | articulate 出口 | `lint-articulation.py` 合格 | — | 低・自動 | 採用 |
| GATE-req-lint | requirements 出口 | `lint-requirements.py` 合格 | 曖昧要求 | 低・自動 | 採用 |
| GATE-flow-coverage | acceptance 準備 | `check-coverage.py` 合格 | 検証手段の無い要求 | 低・自動 | 採用 |
| GATE-unit | construct 中 | `make test`(bats 全件)+ `make lint` | DEF-T1/T2/T3/T6/T7 | 低・自動 | 採用 |
| GATE-review | construct 出口 | tower-reviewer(CONFIRMED は直してから PR) | DEF-T1/T2/T5 | 中 | 採用 |
| GATE-acceptance | acceptance 出口 | 中核フロー全通過(実 tmux、per-run socket) | DEF-T1/T4/T5 | 中 | 採用 |
| GATE-trace | trace 出口 | `generate-trace.py` の穴ゼロ | — | 低・自動 | 採用 |
| GATE-contract | construct 出口 | O1〜O6 の存在確認(手動。`verify-contract.sh` はこの環境に無い) | — | 低 | 採用(手動) |

## レビューエージェントの選定

| エージェント | 採否 | 理由 |
|---|---|---|
| tower-reviewer | 採用 | CLAUDE.md が名指し。DEF-T1/T2/T5 はこれしか捕まえない |
| code-practice-reviewer | 選外 | shellcheck と tower-reviewer で重なる。この repo で generic review が捕まえた欠陥の実績が無い |
| test-pyramid-reviewer | 選外 | 単体 / 結合 / 受入の配分は harness で既に決めている。費用に見合わない |
| document-reviewer | 選外 | 対象文書は SKILL.md 1 本。構造は REQ-001-016 で固定し bats で検査する |
| natural-language-reviewer | 選外 | 利用者向け文言は CLI のエラー 1 行ずつ。費用に見合わない |
| architecture-reviewer / product-design-reviewer | 選外 | 分節と要求で設計判断は済んでいる |

## 構築層への要求(契約の I4)

### テスト戦略
- 単体(bats、`tests/`): 新しい関数とスクリプトの引数解析・終了コード・stdout/stderr 分離・metadata の原子的書き換え・tty 無しでの完走。`CLAUDE_TOWER_PROGRAM="sleep 30"` で claude を代替
- 結合(bats、`tests/integration/`): `current_tower_session` の解決(実 tmux、per-run socket)、`tower open` 後の `selected` と view の切り替え
- 受入(bats、`tests/e2e/test_acceptance_001.bats`、ランナ `value/001-tower-session-cli/acceptance/run.sh`): 受入シナリオと 1:1 の名前。results.json を生成
- 比率の方針: 単体を厚く(異常系は全部ここ)、受入は中核フロー + 失敗経路 1 本ずつ

### 禁止する手法・ライブラリ
- `save_metadata` を rename に使うこと(全体上書き・`created_at` 再スタンプ)
- 対話的確認(`read -p` / `[y/N]`)を新コマンドに入れること
- `gh` の呼び出し(非スコープ: GitHub 作成)
- `tmux rename-session`(Tower のセッション名を壊す)

### 守るべき既存規約
- shellcheck 準拠、4 スペース、内部関数は `_` 接頭辞、500 行未満、`handle_error` 経由のエラー
- 新スクリプトは common.sh を source し、`set -euo pipefail` を受け継ぐことを前提に、素の `return` を書かない
- テストは test_helper の隔離(`CLAUDE_TOWER_*` 環境変数、`tower-test-*` socket)に乗る

### 非機能要求
- 性能: `tower rename` は 1 秒以内(tmux への問い合わせ 1 回 + ファイル 1 本)
- セキュリティ: `project new` の名前検証(REQ-001-026)。プロンプトは引数ではなくファイル経由で渡し、シェル引用に乗せない

### 「動けばよい」を許す範囲
- なし

## 費用対効果の点検

- [x] 前工程で防げるものを、後工程の高いゲートで捕まえていないか — DEF-T3/T6/T7 は単体で捕まえ、受入では見ない
- [x] 同じ欠陥クラスを複数ゲートで重複して見ていないか — DEF-T1 は単体(文字列)と受入(実 tmux)の 2 段。層が違うので重複ではない
- [x] 実績ゼロの欠陥クラスに高いゲートを張っていないか — 全クラスに実績あり

上流に移した判断:
| 欠陥クラス | 元の検知工程 | 移した先 | 理由 |
|---|---|---|---|
| DEF-T6 | 受入 | 単体 | stdin を閉じるだけで再現でき、受入まで持ち越す理由が無い |
