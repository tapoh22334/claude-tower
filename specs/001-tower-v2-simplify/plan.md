# Implementation Plan: Tower v2 - セッション管理の簡素化

**Branch**: `001-tower-v2-simplify` | **Date**: 2026-02-05 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/001-tower-v2-simplify/spec.md`

## Summary

Tower v2は「セッション管理」に特化したシンプルな設計への移行。Worktree管理機能を廃止し、ディレクトリは「参照」するだけとする。CLIコマンド（`tower add`/`tower rm`）を追加し、Navigatorを簡素化する。

## Technical Context

**Language/Version**: Bash 4.0+ (POSIX互換シェルスクリプト)
**Primary Dependencies**: tmux 3.2+, git (オプション)
**Storage**: ファイルベース (`~/.claude-tower/metadata/*.meta`)
**Testing**: bats (Bash Automated Testing System)
**Target Platform**: Linux, macOS
**Project Type**: tmux plugin (シェルスクリプト)
**Performance Goals**: 即座に応答（<100ms）
**Constraints**: 外部依存なし、POSIX互換
**Scale/Scope**: 個人開発者向け、10-50セッション程度

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

プロジェクト固有のconstitutionは未設定のため、一般的なベストプラクティスに従う:

- [x] シンプルさ優先
- [x] 後方互換性維持
- [x] テスト駆動開発
- [x] セキュリティ考慮（入力検証）

## Project Structure

### Documentation (this feature)

```text
specs/001-tower-v2-simplify/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   └── cli.md           # CLI contract
└── tasks.md             # Phase 2 output (by /speckit.tasks)
```

### Source Code (repository root)

```text
tmux-plugin/
├── scripts/
│   ├── tower              # [NEW] CLI entry point
│   ├── session-add.sh     # [NEW] tower add implementation
│   ├── session-delete.sh  # [MODIFY] Simplify (remove worktree logic)
│   ├── navigator-list.sh  # [MODIFY] Remove n/D, add path display
│   ├── navigator.sh       # [MINOR] Footer update
│   ├── cleanup.sh         # [MODIFY] Remove worktree cleanup
│   └── ...
├── lib/
│   ├── common.sh          # [MODIFY] Metadata, create/delete simplification
│   └── error-recovery.sh  # No change
└── conf/
    └── ...

tests/
├── test_session_add.bats    # [NEW]
├── test_session_delete_v2.bats  # [NEW]
├── test_metadata.bats       # [MODIFY] v2 format
├── test_navigator.bats      # [MODIFY] n/D removal
└── ...
```

**Structure Decision**: 既存のtmux-plugin構造を維持。新規ファイルは`scripts/`配下に追加。

## Implementation Phases

### Phase 1: CLI追加

| File | Action | Description |
|------|--------|-------------|
| `scripts/tower` | Create | CLIエントリポイント |
| `scripts/session-add.sh` | Create | `tower add` 実装 |
| `scripts/session-delete.sh` | Modify | `-f` オプション追加、確認プロンプト |

### Phase 2: Common変更

| File | Action | Description |
|------|--------|-------------|
| `lib/common.sh` | Modify | `save_metadata()` 簡素化 |
| `lib/common.sh` | Modify | `load_metadata()` 後方互換対応 |
| `lib/common.sh` | Modify | `create_session()` シンプル化 |
| `lib/common.sh` | Modify | `delete_session()` Worktree処理削除 |
| `lib/common.sh` | Delete | Worktree関連関数削除 |
| `lib/common.sh` | Delete | タイプ関連定数・関数削除 |

### Phase 3: Navigator変更

| File | Action | Description |
|------|--------|-------------|
| `scripts/navigator-list.sh` | Modify | `n`/`D` キーバインド削除 |
| `scripts/navigator-list.sh` | Modify | 表示形式変更（パス追加） |
| `scripts/navigator-list.sh` | Delete | `create_session_inline()` 関数 |
| `scripts/navigator-list.sh` | Delete | `delete_selected()` 関数 |

### Phase 4: クリーンアップ

| File | Action | Description |
|------|--------|-------------|
| `scripts/cleanup.sh` | Modify | Worktreeクリーンアップ削除 |
| `tests/*.bats` | Modify/Create | テスト更新・追加 |
| `README.md` | Modify | 移行ガイド追加 |

## Deleted Code Summary

### Functions to Remove (common.sh)

- `_create_worktree_session()`
- `find_orphaned_worktrees()`
- `remove_orphaned_worktree()`
- `cleanup_orphaned_worktree()`
- `get_session_type()`
- `get_type_icon()`

### Constants to Remove (common.sh)

- `TYPE_WORKTREE`
- `TYPE_SIMPLE`
- `ICON_TYPE_WORKTREE`
- `ICON_TYPE_SIMPLE`

## Breaking Changes

1. **Navigator `n`/`D` キー廃止**: CLIを使用
2. **セッション削除時Worktree保持**: 手動削除が必要
3. **タイプ表示廃止**: [W]/[S] → パス表示

## Complexity Tracking

違反なし。設計はシンプルで、既存アーキテクチャを踏襲。

## Generated Artifacts

- [research.md](./research.md) - 技術調査結果
- [data-model.md](./data-model.md) - データモデル定義
- [quickstart.md](./quickstart.md) - 開発ガイド
- [contracts/cli.md](./contracts/cli.md) - CLI契約

## Next Steps

`/speckit.tasks` コマンドで実装タスクを生成する。
