# Tower v2 コード変更計画

## 変更概要

| カテゴリ | 変更内容 |
|---------|---------|
| CLI | `tower add`, `tower rm` コマンド追加 |
| Navigator | `n`, `D` キーバインド削除、表示形式変更 |
| Metadata | フィールド簡素化 |
| Common | Worktree 関連関数の廃止 |

## 新規ファイル

### `tmux-plugin/scripts/session-add.sh`

```bash
#!/usr/bin/env bash
# session-add.sh - Add a directory as a Tower session
# Usage: session-add.sh <path> [-n name]

# 主な処理:
# 1. パス検証
# 2. セッション名決定（引数 or ディレクトリ名）
# 3. 重複チェック
# 4. metadata 保存
# 5. tmux session 作成
# 6. Claude 起動
```

### `tmux-plugin/scripts/tower`

```bash
#!/usr/bin/env bash
# tower - CLI entry point
# Usage:
#   tower add <path> [-n name]
#   tower rm <name> [-f]

case "$1" in
    add)
        shift
        exec "$SCRIPT_DIR/session-add.sh" "$@"
        ;;
    rm)
        shift
        exec "$SCRIPT_DIR/session-delete.sh" "$@"
        ;;
    *)
        usage
        ;;
esac
```

## 変更ファイル

### `tmux-plugin/scripts/navigator-list.sh`

**削除する処理:**

```bash
# 削除: create_session_inline() 関数全体 (L291-L378)
# 削除: delete_selected() 関数全体 (L381-L421)
# 削除: 'n' キー処理 (L683-L690)
# 削除: 'D' キー処理 (L691-L699)
```

**変更する処理:**

```bash
# 変更: build_session_list() - タイプアイコン廃止
# 変更前:
SESSION_DISPLAYS+=("${NAV_C_ACTIVE}▶${NAV_C_NORMAL} ${type_icon} ${name}")

# 変更後:
SESSION_DISPLAYS+=("${NAV_C_ACTIVE}▶${NAV_C_NORMAL} ${name}  ${path}")

# 変更: フッター表示
# 変更前:
"j/k:nav Enter:attach i:input n:new D:del r:restore q:quit"

# 変更後:
"j/k:nav  Enter:attach  i:input  r:restore  q:quit"
```

### `tmux-plugin/scripts/session-new.sh`

**廃止候補:**

このファイル自体を廃止し、`session-add.sh` に置き換える。
または、互換性のため残して内部で `session-add.sh` を呼ぶ。

### `tmux-plugin/scripts/session-delete.sh`

**変更する処理:**

```bash
# 削除: Worktree 削除処理
# 削除: branch 削除処理
# 変更: タイプ判定の削除

# 変更後の delete_session():
delete_session() {
    local session_id="$1"
    local force="${2:-}"

    # 確認プロンプト
    if [[ "$force" != "force" && "$force" != "-f" ]]; then
        # 確認処理
    fi

    # tmux session 終了
    if session_tmux has-session -t "$session_id" 2>/dev/null; then
        session_tmux kill-session -t "$session_id"
    fi

    # metadata 削除
    delete_metadata "$session_id"

    # 完了（ディレクトリは触らない）
    handle_success "Session deleted: ${session_id#tower_}"
}
```

### `tmux-plugin/lib/common.sh`

**削除する関数:**

```bash
# 削除候補（Worktree 関連）:
_create_worktree_session()
find_orphaned_worktrees()
remove_orphaned_worktree()
cleanup_orphaned_worktree()

# 削除候補（タイプ関連）:
TYPE_WORKTREE
TYPE_SIMPLE
ICON_TYPE_WORKTREE
ICON_TYPE_SIMPLE
get_session_type()
get_type_icon()
```

**変更する関数:**

```bash
# save_metadata() - フィールド簡素化
save_metadata() {
    local session_id="$1"
    local directory_path="$2"

    ensure_metadata_dir

    local metadata_file="${TOWER_METADATA_DIR}/${session_id}.meta"

    {
        echo "session_id=${session_id}"
        echo "session_name=${session_id#tower_}"
        echo "directory_path=${directory_path}"
        echo "created_at=$(date -Iseconds)"
    } >"$metadata_file"
}

# load_metadata() - 新フィールド対応
load_metadata() {
    local session_id="$1"
    local metadata_file="${TOWER_METADATA_DIR}/${session_id}.meta"

    META_SESSION_NAME=""
    META_DIRECTORY_PATH=""
    META_CREATED_AT=""

    if [[ -f "$metadata_file" ]]; then
        while IFS='=' read -r key value; do
            case "$key" in
                session_name) META_SESSION_NAME="$value" ;;
                directory_path) META_DIRECTORY_PATH="$value" ;;
                created_at) META_CREATED_AT="$value" ;;
                # 後方互換: 旧フィールドも読む
                worktree_path) META_DIRECTORY_PATH="$value" ;;
            esac
        done <"$metadata_file"
        return 0
    fi
    return 1
}

# create_session() - シンプル化
create_session() {
    local name="$1"
    local directory_path="$2"

    local session_id
    session_id=$(normalize_session_name "$(sanitize_name "$name")")

    if session_exists "$session_id"; then
        handle_error "Session already exists: $name"
        return 1
    fi

    if [[ ! -d "$directory_path" ]]; then
        handle_error "Directory does not exist: $directory_path"
        return 1
    fi

    # metadata 保存
    save_metadata "$session_id" "$directory_path"

    # tmux session 作成 & Claude 起動
    _start_session_with_claude "$session_id" "$directory_path"
}
```

### `tmux-plugin/scripts/cleanup.sh`

**変更:**

Worktree クリーンアップは不要になるため、大幅に簡素化。
orphaned metadata の削除のみ行う。

## 後方互換性

### 既存 Metadata の扱い

v1 形式の metadata（`session_type=worktree` 等）も読み込めるようにする:

```bash
load_metadata() {
    # ...
    case "$key" in
        # v2 フィールド
        directory_path) META_DIRECTORY_PATH="$value" ;;

        # v1 後方互換
        worktree_path) META_DIRECTORY_PATH="$value" ;;
        repository_path)
            # worktree_path がなければこちらを使う
            [[ -z "$META_DIRECTORY_PATH" ]] && META_DIRECTORY_PATH="$value"
            ;;
    esac
}
```

### 既存セッションの移行

既存の [W] セッション:
- 引き続き動作する（metadata 読み込み可能）
- 削除時は **worktree を削除しない**（新挙動）
- ユーザーが手動で `git worktree remove` する必要あり

**移行ガイドを README に追記する。**

## テスト

### 新規テスト

```bash
# tests/test-session-add.bats
@test "tower add creates session" { ... }
@test "tower add with custom name" { ... }
@test "tower add fails if path not exists" { ... }
@test "tower add fails if session exists" { ... }

# tests/test-session-delete-v2.bats
@test "tower rm deletes session" { ... }
@test "tower rm does not delete directory" { ... }
@test "tower rm with force skips confirmation" { ... }
```

### 削除するテスト

```bash
# Worktree 作成関連のテストを削除
# タイプ判定関連のテストを削除
```

## 実装順序

1. **Phase 1: CLI 追加**
   - [ ] `tower` エントリポイント作成
   - [ ] `session-add.sh` 作成
   - [ ] `session-delete.sh` 変更（Worktree 削除処理削除）

2. **Phase 2: Common 変更**
   - [ ] `common.sh` の metadata 関数変更
   - [ ] Worktree 関連関数削除
   - [ ] タイプ関連定数・関数削除

3. **Phase 3: Navigator 変更**
   - [ ] `n`, `D` キーバインド削除
   - [ ] 表示形式変更（パス表示追加）
   - [ ] フッター更新

4. **Phase 4: クリーンアップ**
   - [ ] 不要ファイル削除
   - [ ] テスト更新
   - [ ] README 更新（移行ガイド追加）

## Breaking Changes

1. **Navigator から `n`/`D` が使えなくなる**
   - CLI を使う必要あり

2. **セッション削除時に Worktree が削除されなくなる**
   - ユーザーが手動で削除

3. **[W]/[S] タイプ表示がなくなる**
   - 代わりにパスを表示
