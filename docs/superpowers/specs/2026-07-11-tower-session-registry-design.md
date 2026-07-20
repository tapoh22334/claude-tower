# Tower 再設計: ファイルベース管理から Claude セッション台帳へ

日付: 2026-07-11
ステータス: レビュー済み(アーキテクチャ/UX/敵対的エッジケースの3レビュー + claude CLI 2.1.207 での実機検証を反映)
本設計は `plan/` 配下の旧 v2 設計書を置き換える。

## 1. 思想とスコープ

Tower の管理対象を「ディレクトリ/worktree」から「Claude セッション(sessionId)」に置き換える。
Tower の責務は3つ:

1. **台帳**: どの sessionId を管理下に置くかの記録
2. **tmux オーケストレーション**: セッションの起動・attach・kill
3. **Navigator UI**: 一覧・稼働状況表示・操作

セッションの実体情報(cwd、更新時刻、存在)は Claude Code 自身が書く
`~/.claude/projects/<slug>/<sessionId>.jsonl` から都度導出し、Tower は複製を持たない。
git 操作は worktree の「作成」ヘルパ(1行の `git worktree add` ラッパ)のみ提供し、
削除・孤児掃除・ブランチ管理は一切行わない(ユーザの責任範囲)。

## 2. データモデル

### 台帳(残す・極小化)

`~/.claude-tower/metadata/<sessionId>.meta`

```
session_name=my-feature        # 任意。ユーザが付ける表示ラベル。無くてよい
created_at=2026-07-11T10:00:00
```

`session_type` / `repository_path` / `source_commit` / `worktree_path` / `branch_name` は全廃。
旧形式 .meta は読み込み時に未知キーを無視することで互換維持。

### 導出情報(jsonl から都度取得)

- **jsonl の所在**: `~/.claude/projects/*/<sessionId>.jsonl` を glob(slug 直下のみ。
  サブエージェントは `<sessionId>/subagents/agent-*.jsonl` の入れ子なので構造上拾われない。実データで検証済み)
- **cwd**: jsonl 中で**最初に出現した** `"cwd":"..."` を採用(grep + パラメータ展開、jq 不使用)。
  cwd はセッション途中の `cd` で変化しうる(実例確認済み)が、slug および `--resume` の
  検索スコープに対応するのは起動時 cwd なので、最初の値が正しい
- **稼働状況**: 次の3つの mtime の最新値
  1. `<sessionId>.jsonl` 本体
  2. `<sessionId>/subagents/` 配下の最新 jsonl
  3. `$TMPDIR/claude-<uid>/<slug>/<sessionId>/tasks/` 配下の最新 `*.output`
     (バックグラウンドエージェント実行中は親 jsonl が数分更新されないため。claude-aquarium 同方式)

## 3. 状態モデル

| 表示 | 条件 | 意味 |
|---|---|---|
| `●` Busy | tmux セッションあり かつ 稼働 mtime ≤ TOWER_BUSY_WINDOW(デフォルト45秒) | Claude が働いている |
| `▶` Active | tmux セッションあり | 起動中・待機 |
| `○` Dormant | .meta のみ(tmux なし)、cwd 存続 | `--resume` で復帰可能 |
| `✗` Dead | .meta あり、jsonl はあるが cwd のディレクトリが消失 | **復帰不能**(--resume は cwd スコープのため)。D で整理 |
| `?` Lost | .meta あり、jsonl が消失(Claude の30日自動削除等) | 復帰不能。D で整理 |

- tmux セッション名 = `tower_<sessionId>`。tmux ↔ jsonl の対応は名前だけで解決(マッピングファイル不要)
- `✗` / `?` は一覧末尾にセパレータを挟んで表示し、通常セッションと混ざらないようにする
- 閾値45秒は環境変数 `TOWER_BUSY_WINDOW` で変更可能

### 既知の制限(ドキュメント明記事項)

- resume/新規起動の直後は jsonl が touch されるため、45秒間は入力待ちでも `●` になる(実測確認済み)
- 45秒を超える長時間ツール実行中(長いビルド等)は jsonl が更新されず `▶` に落ちる。
  mtime 方式の構造的限界であり、プロセス検出は行わない
- attach 自体は jsonl に触れないため状態表示に影響しない(実測確認済み)

## 4. フロー

### `n`(追加・新規の統一フロー)

`TOWER_FINDER` 環境変数(デフォルト: fzf のフラグ込みコマンド文字列)に候補を流す。
プロトコルは「stdin から候補行、stdout に選択行、キャンセルは非ゼロ終了」。
fzy / peco / skim 等に差し替え可能。**finder が存在しない場合は番号選択のプレーン
フォールバック**(候補を番号付きで列挙し `read` で選ばせる)に自動で切り替わる。

```
[new]    新しいセッションを開始
a1b2c3d  ~/working/foo   (my-feature)  2分前
e4f5a6b  ~/working/bar                 3時間前
```

- 行頭は短縮ID(選択結果のパースを空白入り cwd から守るため行頭固定)。
  主表示は cwd 末尾、session_name があれば括弧で併記、mtime 相対時刻
- 候補 = slug 直下の全 jsonl のうち、以下を除外したもの(mtime 降順):
  - 登録済み(.meta が存在する)
  - 空セッション(user/assistant メッセージ 0 件)
  - cwd が `$TMPDIR` 配下(scratchpad 等の内部セッション)
  - cwd のディレクトリが消失しているもの
- **既存を選択** → .meta 作成 → `tmux new-session -d -s tower_<id> -c <cwd>` →
  `claude --resume <id>` を send-keys → attach
- **[new] を選択** → ディレクトリ入力(デフォルト = 呼び出し元 pane の cwd。
  **Enter 一発でデフォルト確定**できること)。入力プロンプトで `+` を選ぶと
  worktree 作成ヘルパ(`git worktree add <path> -b <branch>` を裏で叩くだけ。
  掃除は関知しない)。→ UUID 事前生成(`uuidgen`、なければ
  `/proc/sys/kernel/random/uuid`)→ `claude --session-id <uuid>` で起動 →
  .meta 即作成(jsonl 出現を待つ検出処理は不要)
- `tmux new-session` が失敗した場合は .meta を作らない(作成順: tmux 成功 → .meta)。
  同名 tmux セッションが既に存在する場合は「既に起動しています」と表示して attach に切り替える

### `r`(個別 restore)

Dormant セッションで押すと、jsonl から cwd を引いて
`tmux new-session -d -s tower_<id> -c <cwd>` + `claude --resume <id>`。
`--resume` は cwd スコープなので必ずこの cwd で起動する。
cwd 消失時は「ディレクトリが見つかりません。D で台帳から外すか、ディレクトリを復元してください」
と表示して何もしない。

**`R`(全復帰)は廃止**(誤操作時の一斉起動被害、未 trust ディレクトリでの一括停止のため)。

### `D`(削除)

tmux セッション kill + .meta 削除のみ。**jsonl には一切触れない**
(Claude 側の30日自動削除までは `n` から再追加できる。30日を超えた分は Claude が消す)。
worktree/ブランチの掃除は行わない。

### Enter / i / Tab(tile)

現行のまま変更なし。footer のキーラベルは `n:add/new`、`R` 削除、`r:resume` に更新する。

## 5. 実装規約(レビューで実際に踏んだ罠)

- slug ディレクトリ名は必ず `-` 始まり(cwd が `/` 始まりのため)。
  grep/stat 等へは**絶対パスで渡すか `--` 区切り必須**
- `grep -o` は POSIX ではなく GNU/BSD 拡張。短フラグは結合せず `grep -o -m 1` と分離して書く。
  この環境の grep は ugrep であることに注意し、CI では GNU grep で検証する
- cwd を1行も含まない jsonl があり得る(先頭行は `queue-operation` 等で cwd を持たない)。
  **cwd が空のときは `✗` 扱い**にし、`tmux new-session -c ""` へ流さない
- finder / フォールバックの選択結果から取り出した ID は `^[0-9a-f-]{36}$` で検証してから使う
- cwd・パスの変数展開はすべてクォートする(スペース入り cwd は実在・動作確認済み)
- jsonl 走査はファイルの並行削除に耐える(存在チェック+失敗許容)
- cwd 内の `"` `\` エスケープは非対応(既知の制限。Linux 実運用では未観測)
- 一覧描画ループでは mtime をキーにした結果キャッシュを推奨
  (433ファイル/484MB の全件走査は実測0.5秒だが、毎フレーム実行は避ける)

## 6. エラーメッセージ指針

「何が起きたか」+「次に何をすべきか」を必ず含める。例:

- cwd 消失: `ディレクトリがありません: <path> — D で台帳から外せます`
- finder 欠如(フォールバック時の補足): `fzf を入れると絞り込み選択が使えます`
- jsonl 消失: `Claude 側の記録が見つかりません(30日で自動削除されます)— D で整理してください`

## 7. 廃止するもの

- worktree/ブランチの削除・孤児掃除(`find_orphaned_worktrees` 系、`cleanup.sh` の大半)。
  ※「作成」だけは [new] フロー内の1行ヘルパとして残る
- `_create_worktree_session`(worktree 作成が [new] フローに統合されるため)
- `[W]`/`[S]` タイプ分類と関連コード(`session_type`、`get_type_icon` 等)
- `create_session_inline` の現行実装(`n` の新フローに置換)
- `R`(全復帰)キーと `restore_all_dormant` 系
- 未接続のレガシースクリプト群(`new-session.sh`、`rename.sh`、`preview.sh`、
  `sidebar.sh`、`tree-view.sh`、`kill.sh`、`diff.sh`、`input.sh`、`statusline.sh`、`help.sh`)
- 旧 v2 設計書(`plan/`)

### 移行ノート(README に記載)

- 既存の worktree はそのまま使える(`n` で当該 cwd のセッションを追加するだけ)
- セッション削除時の worktree/ブランチ自動掃除は無くなった。
  `git worktree remove` / `git branch -d` は各自で実行すること

## 8. 依存関係

- **必須**: bash, tmux, GNU grep/sed/stat(coreutils)— 追加依存ゼロ
- **推奨**: fzf(`TOWER_FINDER` デフォルト)。欠如時は番号選択フォールバックで全機能動作
- **UUID 生成**: `uuidgen` または `/proc/sys/kernel/random/uuid`

## 9. テスト

既存の bats テスト体制を踏襲。

- jsonl パース系ヘルパー(`find_session_jsonl` / `get_session_cwd` / `get_session_activity` /
  候補フィルタ)はフィクスチャ jsonl(cwd 無し行のみ・空セッション・スペース入り cwd を含む)で単体テスト
- 状態判定(5状態)のテーブルテスト
- 廃止機能のテストは削除

## 検証済みの前提(実機実験の記録)

claude CLI 2.1.207 にて:

- `claude --resume <id>` は sessionId を**フォークしない**(同一 jsonl に追記。
  fork は `--fork-session` オプトイン)→ `tower_<sessionId>` 命名は resume で壊れない
- `claude --session-id <uuid>` は実在し、指定 UUID がファイル名になる
- `--resume` は cwd スコープ(別ディレクトリからは `No conversation found`)
- Claude 側の30日自動削除(`cleanupPeriodDays`)は実際に稼働している
- 未 trust ディレクトリでは起動時に trust 確認画面で停止する(attach すれば操作可能。制限事項)
