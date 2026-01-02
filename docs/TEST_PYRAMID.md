# Claude Tower Test Pyramid

テスト構造とSPECIFICATION.mdへのマッピング

## テスト統計

| カテゴリ | テスト数 | パス率 |
|----------|----------|--------|
| Unit Tests | 174 | 173/174 (1件 macOSでスキップ) |
| Integration Tests | 58 | 環境依存 |
| Scenario Tests | 13 | 環境依存 |
| E2E Tests | 5 | tmux環境必須 |
| **合計** | **250** | |

## テストピラミッド

```
                    ┌─────────────────────────┐
                    │      E2E Tests (5)      │ ← 実際のtmuxとの統合
                    │  tests/e2e/             │   tmux環境必須
                    └─────────────────────────┘
                   ┌───────────────────────────┐
                   │   Scenario Tests (13)     │ ← ユーザーシナリオ
                   │   tests/scenarios/        │   実行可能スクリプト
                   └───────────────────────────┘
                  ┌─────────────────────────────┐
                  │  Integration Tests (58)    │ ← tmuxサーバー間の連携
                  │  tests/integration/        │   サーバー分離テスト
                  └─────────────────────────────┘
         ┌─────────────────────────────────────────┐
         │          Unit Tests (174)               │ ← 個別関数のテスト
         │  tests/test_*.bats                      │   環境非依存
         └─────────────────────────────────────────┘
```

## ファイル別テスト数

### Unit Tests (174 tests)

| ファイル | テスト数 | 主要テスト対象 |
|----------|----------|----------------|
| test_navigator.bats | 35 | Navigator状態管理、ソケット分離 |
| test_sanitize.bats | 29 | 入力サニタイズ、XSS防止 |
| test_server_separation.bats | 25 | サーバー分離、TMUX=プレフィックス |
| test_metadata.bats | 24 | メタデータ永続化 |
| test_validation.bats | 20 | 入力バリデーション |
| test_error_handling.bats | 13 | エラーハンドリング |
| test_orphan.bats | 12 | オーファンセッション検出 |
| test_safe_wrappers.bats | 8 | 安全なラッパー関数 |
| test_dependencies.bats | 8 | 依存関係チェック |

### Integration Tests (58 tests)

| ファイル | テスト数 | 主要テスト対象 |
|----------|----------|----------------|
| test_server_switch.bats | 19 | サーバー間切り替え |
| test_navigation_contract.bats | 17 | 状態ファイル契約 |
| test_display_snapshot.bats | 14 | 表示スナップショット |
| test_tmux_integration.bats | 8 | tmux統合 |

### Scenario Tests (13 tests)

| ファイル | テスト数 | 主要テスト対象 |
|----------|----------|----------------|
| test_scenarios.bats | 13 | ユーザーシナリオ |

### E2E Tests (5 tests)

| ファイル | テスト数 | 主要テスト対象 |
|----------|----------|----------------|
| test_workspace_workflow.bats | 5 | ワークスペース全体フロー |

## SPECIFICATION.md へのマッピング

### 1. Navigator ライフサイクル
- **SPEC**: `prefix + t, c` でNavigator起動
- **Tests**: `test_navigator.bats` (35 tests)
  - `TOWER_NAV_SOCKET: is set to claude-tower`
  - `navigator.sh: exists and is executable`
  - `claude-tower.tmux: Navigator uses run-shell not display-popup`

### 2. フォーカスモデル (list/view)
- **SPEC**: フォーカスは `list` または `view`
- **Tests**:
  - `test_navigator.bats`: `get_nav_focus: returns 'list' as default`
  - `test_navigation_contract.bats`: `focus can switch to view`

### 3. セッション状態管理
- **SPEC**: `running`, `idle`, `exited`, `dormant`
- **Tests**: `test_navigator.bats`
  - `get_state_icon: returns correct icon for running`
  - `get_session_state: returns dormant for session with metadata but no tmux session`

### 4. サーバー分離アーキテクチャ
- **SPEC**: Navigator専用サーバー (`-L claude-tower`)
- **Tests**:
  - `test_server_separation.bats` (25 tests)
  - `test_server_switch.bats` (19 tests)

### 5. セキュリティ (入力バリデーション)
- **SPEC**: セッションID形式 `tower_[name]`
- **Tests**:
  - `test_sanitize.bats` (29 tests)
  - `test_validation.bats` (20 tests)
  - `validate_tower_session_id: rejects command injection`

### 6. メタデータ永続化
- **SPEC**: `~/.claude-tower/metadata/`
- **Tests**: `test_metadata.bats` (24 tests)

## プラットフォーム依存テスト

### macOSでスキップされるテスト (1件)

| テスト | 理由 |
|--------|------|
| `validate_path_within: rejects symlink escape` | `realpath -m` がmacOSに存在しない |

このテストはLinuxでは実行されます。

## テスト実行コマンド

```bash
# 全Unit Tests
bats tests/*.bats

# Integration Tests
bats tests/integration/

# Scenario Tests
bats tests/scenarios/

# E2E Tests (tmux環境必須)
bats tests/e2e/

# 特定ファイル
bats tests/test_navigator.bats

# フィルター実行
bats --filter "contract:" tests/

# Makefile経由
make test        # Unit Tests
make lint        # shellcheck
make format-fix  # shfmt
```

## 静的解析

```bash
# shellcheck (静的解析)
make lint

# shfmt (フォーマット)
make format      # 差分表示
make format-fix  # 自動修正
```

---
Last Updated: 2026-01-02
