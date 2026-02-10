# CLI Contract: Tower v2

**Version**: 2.0.0

## Commands

### `tower add`

セッションを追加する。

**Syntax**:
```
tower add <path> [-n|--name <name>]
```

**Arguments**:

| Argument | Required | Description |
|----------|----------|-------------|
| `path` | Yes | 作業ディレクトリのパス (絶対パスまたは相対パス) |

**Options**:

| Option | Description | Default |
|--------|-------------|---------|
| `-n, --name <name>` | セッション名 | ディレクトリ名 |

**Exit Codes**:

| Code | Meaning |
|------|---------|
| 0 | 成功 |
| 1 | エラー (パス不正、重複等) |

**Output** (stdout):
```
✓ Session created: my-session
  Path: /home/user/projects/my-app
```

**Errors** (stderr):
```
Error: Directory does not exist: /invalid/path
Error: Not a directory: /path/to/file
Error: Session already exists: my-session
```

---

### `tower rm`

セッションを削除する。

**Syntax**:
```
tower rm <name> [-f|--force]
```

**Arguments**:

| Argument | Required | Description |
|----------|----------|-------------|
| `name` | Yes | セッション名 |

**Options**:

| Option | Description |
|--------|-------------|
| `-f, --force` | 確認プロンプトをスキップ |

**Exit Codes**:

| Code | Meaning |
|------|---------|
| 0 | 成功 |
| 1 | エラー (セッション不存在、キャンセル) |

**Output** (stdout):
```
Delete session 'my-session'? [y/N]: y
✓ Session deleted: my-session
```

**Errors** (stderr):
```
Error: Session not found: unknown-session
```

---

## Metadata Format

### v2 Format

```ini
session_id=tower_<name>
session_name=<name>
directory_path=<absolute_path>
created_at=<ISO8601>
```

**Example**:
```ini
session_id=tower_my-session
session_name=my-session
directory_path=/home/user/projects/my-app
created_at=2026-02-05T10:30:00+09:00
```

### v1 Compatibility (Read-Only)

v1形式のmetadataは読み込み可能:

```ini
session_id=tower_my-session
session_type=worktree
repository_path=/home/user/repos/app
worktree_path=/home/user/.claude-tower/worktrees/my-session
source_commit=abc123
branch_name=tower/my-session
```

**Mapping**:
- `worktree_path` → `directory_path` (優先)
- `repository_path` → `directory_path` (fallback)
- その他 → 無視

---

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `CLAUDE_TOWER_PROGRAM` | 起動するプログラム | `claude` |
| `CLAUDE_TOWER_METADATA_DIR` | metadataディレクトリ | `~/.claude-tower/metadata` |
| `CLAUDE_TOWER_DEBUG` | デバッグモード | `0` |

---

## Behavioral Guarantees

1. **ディレクトリ不変**: `tower rm` はディレクトリを削除しない
2. **後方互換**: v1 metadataは読み込み可能
3. **冪等性**: 同じ操作を繰り返しても安全
4. **入力検証**: 全ての入力はサニタイズされる
