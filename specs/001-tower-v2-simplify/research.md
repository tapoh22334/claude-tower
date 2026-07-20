# Research: Tower v2 - セッション管理の簡素化

**Date**: 2026-02-05
**Branch**: `001-tower-v2-simplify`

## 技術調査項目

### 1. 既存コードベース分析

**Decision**: 既存のBash実装を維持し、リファクタリングする

**Rationale**:
- プロジェクトは全てBashで書かれており、一貫性を保つ
- 外部依存なしで動作する設計思想と合致
- テストフレームワーク（bats）も既に整備済み

**Alternatives considered**:
- Python/Node.jsへの書き換え → 不採用: 依存増加、既存ユーザーへの影響大

### 2. CLIエントリポイント設計

**Decision**: `tower` コマンドを新規作成、サブコマンドでルーティング

**Rationale**:
- `tower add <path>` / `tower rm <name>` という直感的なインターフェース
- 既存の `session-new.sh` / `session-delete.sh` は内部で利用または廃止

**Implementation**:
```bash
# tmux-plugin/scripts/tower
case "$1" in
    add) exec session-add.sh "$@" ;;
    rm)  exec session-delete.sh "$@" ;;
    *)   usage ;;
esac
```

### 3. Metadata構造の変更

**Decision**: v2形式に移行しつつ、v1との後方互換性を維持

**v2 Metadata Format**:
```ini
session_id=tower_my-session
session_name=my-session
directory_path=/path/to/directory
created_at=2026-02-05T10:30:00+09:00
```

**後方互換性マッピング**:
| v1 Field | v2 Handling |
|----------|-------------|
| `session_type` | 無視（全セッション同一扱い） |
| `repository_path` | `directory_path`として読み込み |
| `worktree_path` | `directory_path`として読み込み（優先） |
| `source_commit` | 無視 |
| `branch_name` | 無視 |

### 4. Navigator表示変更

**Decision**: タイプアイコン廃止、パス表示追加

**Current Display**:
```
  ▶ [W] my-feature
  ○ [S] experiment
```

**New Display**:
```
  ▶ my-feature    ~/projects/api
  ○ experiment    ~/work/exp
```

**Implementation**:
- `navigator-list.sh` の `build_session_list()` を変更
- パス表示用に `~` 短縮処理追加
- フッター文字列変更

### 5. キーバインド変更

**Decision**: Navigator内の `n` / `D` キーを削除

**Rationale**:
- セッション作成・削除はCLIに統一
- Navigatorは閲覧・選択に特化
- 予期せぬ削除を防止

**Affected Code**:
- `navigator-list.sh` のキーハンドラから該当case文削除
- `create_session_inline()` / `delete_selected()` 関数削除

### 6. 削除対象コード

**Functions to Remove** (common.sh):
- `_create_worktree_session()`
- `find_orphaned_worktrees()`
- `remove_orphaned_worktree()`
- `cleanup_orphaned_worktree()`
- `TYPE_WORKTREE`, `TYPE_SIMPLE` 定数
- `ICON_TYPE_WORKTREE`, `ICON_TYPE_SIMPLE` 定数
- `get_session_type()`
- `get_type_icon()`

**Files to Modify**:
- `cleanup.sh` - Worktreeクリーンアップ処理削除

### 7. テスト戦略

**Decision**: 既存テストを修正し、新テストを追加

**New Tests**:
- `test_session_add.bats` - tower add コマンド
- `test_session_delete_v2.bats` - ディレクトリ保持の確認

**Modified Tests**:
- `test_metadata.bats` - v2形式対応
- `test_navigator.bats` - n/Dキー削除反映

### 8. 移行ガイド

**Decision**: READMEに移行セクション追加

**Key Points**:
1. v1セッションは引き続き動作
2. セッション削除時、Worktreeは自動削除されなくなる
3. 新規セッション作成は `tower add` を使用
4. Navigator内での n/D キーは使用不可

## リスク分析

| リスク | 影響 | 対策 |
|--------|------|------|
| v1 metadata読み込み失敗 | 既存セッション消失 | 後方互換性テスト徹底 |
| ユーザー混乱（n/Dキー廃止） | UX低下 | ヘルプ画面更新、エラーメッセージ |
| Worktree削除忘れ | ディスク浪費 | 警告メッセージ、ドキュメント |

## 結論

全ての技術調査項目が解決済み。Phase 1に進行可能。
