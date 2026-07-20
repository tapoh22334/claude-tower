# Data Model: Tower v2

**Date**: 2026-02-05
**Branch**: `001-tower-v2-simplify`

## Entities

### Session

Claude Codeが動作する作業単位。

| Field | Type | Description |
|-------|------|-------------|
| `session_id` | string | 内部識別子 (`tower_<name>`) |
| `session_name` | string | 表示名 |
| `directory_path` | string | 作業ディレクトリの絶対パス |
| `created_at` | ISO8601 | 作成日時 |

**State Machine**:

```
(none) --[tower add]--> Active --[tmux終了]--> Dormant --[restore]--> Active
                           |                      |
                           +-- [tower rm] --------+--------> (deleted)
```

| State | Condition | Display |
|-------|-----------|---------|
| Active | tmux session存在 | `▶` |
| Dormant | metadataのみ存在 | `○` |

### Metadata File

ファイルパス: `~/.claude-tower/metadata/<session_id>.meta`

**v2 Format**:
```ini
session_id=tower_my-session
session_name=my-session
directory_path=/home/user/projects/my-app
created_at=2026-02-05T10:30:00+09:00
```

**v1 Backward Compatibility**:

v1形式のフィールドも読み込み可能（廃止済みだが互換性維持）:

| v1 Field | Mapping |
|----------|---------|
| `session_type` | 無視 |
| `repository_path` | `directory_path`として使用 |
| `worktree_path` | `directory_path`として使用（優先） |
| `source_commit` | 無視 |
| `branch_name` | 無視 |

## Validation Rules

### Session Name

- 1-60文字
- 使用可能文字: `[a-zA-Z0-9_-]`
- 先頭・末尾に `-` `_` 不可
- 内部では `tower_` プレフィックス付与

### Directory Path

- 絶対パス
- 存在するディレクトリ
- ユーザーがアクセス可能

## Relationships

```
Session 1 ──── 1 Metadata File
    │
    └── references ──► Directory (external, not managed)
```

- Session と Metadata は1:1
- Directory は外部リソース（Towerは参照のみ、管理しない）

## Removed Entities (v1)

v2で廃止されるエンティティ/概念:

| Entity | Reason |
|--------|--------|
| Session Type (worktree/simple) | 全セッション同一扱い |
| Worktree | Tower責務外へ移行 |
| Branch (tower/*) | Tower責務外へ移行 |
