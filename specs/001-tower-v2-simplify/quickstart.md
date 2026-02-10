# Quickstart: Tower v2 開発ガイド

**Branch**: `001-tower-v2-simplify`

## 前提条件

- tmux 3.2+
- bash 4.0+
- bats (テスト用)

## 開発環境セットアップ

```bash
# リポジトリクローン
git clone https://github.com/tapoh22334/claude-tower.git
cd claude-tower

# 開発ブランチに切り替え
git checkout 001-tower-v2-simplify

# batsインストール (未インストールの場合)
git submodule update --init tests/bats
```

## ディレクトリ構造

```
tmux-plugin/
├── scripts/
│   ├── tower              # [NEW] CLI エントリポイント
│   ├── session-add.sh     # [NEW] tower add 実装
│   ├── session-delete.sh  # [MODIFY] シンプル化
│   ├── navigator-list.sh  # [MODIFY] n/D削除、パス表示
│   └── ...
├── lib/
│   └── common.sh          # [MODIFY] metadata, create/delete簡素化
└── conf/
```

## 主要な変更箇所

### 1. CLI追加

```bash
# 新規作成: tmux-plugin/scripts/tower
tower add /path/to/dir [-n name]
tower rm session-name [-f]
```

### 2. Metadata関数変更

```bash
# common.sh

# 変更前
save_metadata() {
    # session_type, repository_path, source_commit, worktree_path
}

# 変更後
save_metadata() {
    local session_id="$1"
    local directory_path="$2"
    # session_id, session_name, directory_path, created_at のみ
}
```

### 3. Navigator表示変更

```bash
# navigator-list.sh

# 変更前
"${state_icon} ${type_icon} ${name}"

# 変更後
"${state_icon} ${name}  ${short_path}"
```

## テスト実行

```bash
# 全テスト
make test

# 特定テスト
./tests/bats/bin/bats tests/test_metadata.bats

# 新規テスト (実装後)
./tests/bats/bin/bats tests/test_session_add.bats
```

## 実装チェックリスト

### Phase 1: CLI追加
- [ ] `tmux-plugin/scripts/tower` 作成
- [ ] `tmux-plugin/scripts/session-add.sh` 作成
- [ ] `tmux-plugin/scripts/session-delete.sh` 変更

### Phase 2: Common変更
- [ ] `save_metadata()` 変更
- [ ] `load_metadata()` 変更 (後方互換)
- [ ] `create_session()` シンプル化
- [ ] `delete_session()` からWorktree処理削除
- [ ] 不要関数削除

### Phase 3: Navigator変更
- [ ] `n`, `D` キーバインド削除
- [ ] 表示形式変更 (パス追加)
- [ ] フッター更新

### Phase 4: クリーンアップ
- [ ] 不要関数・定数削除
- [ ] テスト更新
- [ ] README更新

## デバッグ

```bash
# デバッグモード有効化
export CLAUDE_TOWER_DEBUG=1

# ログ確認
tail -f ~/.claude-tower/metadata/tower.log

# 状態確認
make status
```

## コーディング規約

- ShellCheck準拠
- 関数はアンダースコアで内部関数を示す (`_internal_func`)
- エラーは `handle_error` / `error_log` を使用
- セキュリティ: 入力は `sanitize_name` / `validate_*` を通す
