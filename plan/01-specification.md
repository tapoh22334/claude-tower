# Tower v2 仕様書

## 概要

Tower v2 は「セッション管理」に特化したシンプルな設計に移行する。
Worktree 管理機能を廃止し、ディレクトリは「参照」するだけとする。

## インターフェース

### CLI

#### `tower add <path>` - セッション追加

```bash
# 指定ディレクトリでセッション作成
tower add /path/to/directory

# カレントディレクトリでセッション作成
tower add .

# 名前を明示的に指定
tower add /path/to/directory -n my-session
```

**オプション:**

| オプション | 説明 | デフォルト |
|-----------|------|-----------|
| `-n, --name <name>` | セッション名 | ディレクトリ名から自動生成 |

**挙動:**

1. パスの存在確認
2. セッション名の決定（指定 or ディレクトリ名）
3. 重複チェック（同名セッションがあればエラー）
4. metadata 保存
5. tmux session 作成（session server 上）
6. Claude Code 起動

**出力:**

```
✓ Session created: my-session
  Path: /path/to/directory
```

#### `tower rm <name>` - セッション削除

```bash
tower rm my-session
```

**オプション:**

| オプション | 説明 |
|-----------|------|
| `-f, --force` | 確認プロンプトをスキップ |

**挙動:**

1. セッション存在確認
2. 確認プロンプト（`-f` でスキップ）
3. tmux session 終了（active の場合）
4. metadata 削除

**注意:** ディレクトリは削除しない

**出力:**

```
Delete session 'my-session'? [y/N]: y
✓ Session deleted: my-session
```

### Navigator

`prefix + t` で起動。

#### キーバインド

| キー | アクション |
|------|-----------|
| `j` / `↓` | 下に移動 |
| `k` / `↑` | 上に移動 |
| `g` | 最初のセッションへ |
| `G` | 最後のセッションへ |
| `Enter` | セッションにアタッチ |
| `i` | 入力モード |
| `r` | dormant セッションを復元 |
| `R` | 全 dormant セッションを復元 |
| `Tab` | Tile ビューに切替 |
| `?` | ヘルプ表示 |
| `q` | Navigator 終了 |

#### 廃止するキーバインド

| キー | 旧アクション | 理由 |
|------|-------------|------|
| `n` | 新規セッション作成 | CLI に統一 |
| `D` | セッション削除 | CLI に統一 |

#### 表示形式

```
Sessions

  ▶ project-api    ~/projects/api
  ▶ feature-x      ~/work/feature-x
  ○ old-session    ~/old/proj

j/k:nav  Enter:attach  i:input  r:restore  q:quit
```

- `▶` = Active（tmux session 存在）
- `○` = Dormant（metadata のみ、復元可能）
- パス表示で作業ディレクトリを明示

## セッションモデル

### 状態

```
┌──────────┐  create   ┌──────────┐
│  (なし)   │ ────────▶ │  Active  │
└──────────┘           └────┬─────┘
                            │
              ┌─────────────┼─────────────┐
              │ tmux再起動  │ restore     │
              ▼             │             │
        ┌──────────┐        │             │
        │ Dormant  │ ───────┘             │
        └────┬─────┘                      │
             │                            │
             │ delete                     │ delete
             ▼                            ▼
        ┌─────────────────────────────────────┐
        │              (削除)                  │
        └─────────────────────────────────────┘
```

| 状態 | 条件 | 表示 |
|------|------|------|
| Active | tmux session 存在 | `▶` |
| Dormant | metadata のみ存在 | `○` |

### Metadata

保存先: `~/.claude-tower/metadata/<session_id>.meta`

```ini
session_id=tower_my-session
session_name=my-session
directory_path=/path/to/directory
created_at=2024-01-15T10:30:00+09:00
```

**v1 からの変更点:**

| フィールド | v1 | v2 |
|-----------|----|----|
| `session_type` | `worktree` / `simple` | 廃止 |
| `repository_path` | git repo パス | 廃止 |
| `source_commit` | 作成時のコミット | 廃止 |
| `worktree_path` | worktree パス | 廃止 |
| `branch_name` | tower/* ブランチ名 | 廃止 |
| `directory_path` | - | **新規追加** |

### タイプ分類の廃止

v1:
```
[W] Worktree - git worktree + 永続
[S] Simple   - volatile、非永続
```

v2:
```
タイプなし - 全セッションが同じ挙動
```

## UX フロー

### 1. 生成 (Create)

```bash
# ユーザーがディレクトリを用意（Tower の責務外）
mkdir ~/projects/my-app
cd ~/projects/my-app
git init

# Tower でセッション追加
tower add .
# または
tower add ~/projects/my-app
```

### 2. 作業 (Work)

```
prefix + t → Navigator 起動
         ↓
    セッション選択
         ↓
    Enter でアタッチ
         ↓
    Claude Code と対話
         ↓
    prefix + t で Navigator に戻る
```

### 3. 削除 (Delete)

```bash
tower rm my-app

# ディレクトリは残る（Tower は触らない）
# 必要なら手動で削除
rm -rf ~/projects/my-app
```

## エラーハンドリング

### `tower add`

| エラー | メッセージ |
|--------|-----------|
| パスが存在しない | `Error: Directory does not exist: /path` |
| ディレクトリでない | `Error: Not a directory: /path` |
| 同名セッション存在 | `Error: Session already exists: name` |

### `tower rm`

| エラー | メッセージ |
|--------|-----------|
| セッションが存在しない | `Error: Session not found: name` |
