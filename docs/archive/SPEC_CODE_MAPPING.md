# 仕様書とコードの対応表

## 1. スクリプト構成（仕様書セクション7）

### 仕様書で定義されたスクリプト構成

```
tmux-plugin/
├── claude-tower.tmux          # エントリポイント（キーバインド設定）
├── lib/
│   └── common.sh              # 共通ライブラリ
└── scripts/
    ├── tower.sh               # メインコマンド（Navigator起動）
    ├── navigator.sh           # Navigatorモード
    ├── tile.sh                # Tileモード
    ├── session-new.sh         # セッション作成
    ├── session-delete.sh      # セッション削除
    ├── session-restore.sh     # セッション復元
    ├── session-list.sh        # セッション一覧取得
    ├── session-status.sh      # 状態検出
    ├── input.sh               # 入力モード
    └── preview.sh             # プレビュー生成
```

### 実際のスクリプト構成

```
tmux-plugin/
├── claude-tower.tmux          ✅ 存在
├── lib/
│   └── common.sh              ✅ 存在
└── scripts/
    ├── tower.sh               ✅ 存在
    ├── navigator.sh           ✅ 存在
    ├── navigator-list.sh      ⚠️ 追加（仕様書に記載なし）
    ├── navigator-preview.sh   ⚠️ 追加（仕様書に記載なし）
    ├── tile.sh                ✅ 存在
    ├── session-new.sh         ✅ 存在
    ├── session-delete.sh      ✅ 存在
    ├── session-restore.sh     ✅ 存在
    ├── session-list.sh        ✅ 存在
    ├── session-status.sh      ❌ 不在（common.shに統合）
    ├── input.sh               ✅ 存在
    ├── preview.sh             ✅ 存在
    ├── cleanup.sh             ⚠️ 追加（仕様書に記載なし）
    ├── diff.sh                ⚠️ 追加（仕様書に記載なし）
    ├── help.sh                ⚠️ 追加（仕様書に記載なし）
    ├── kill.sh                ⚠️ 追加（仕様書に記載なし）
    ├── rename.sh              ⚠️ 追加（仕様書に記載なし）
    ├── sidebar.sh             ⚠️ 追加（仕様書に記載なし）
    ├── statusline.sh          ⚠️ 追加（仕様書に記載なし）
    └── tree-view.sh           ⚠️ 追加（仕様書に記載なし）
```

### 差異の詳細

| 仕様書 | 実装 | ステータス | 備考 |
|--------|------|------------|------|
| session-status.sh | - | ❌ 不在 | common.sh内の`get_session_state()`に機能統合 |
| - | navigator-list.sh | ⚠️ 追加 | Navigatorの左ペイン（リスト表示）を分離 |
| - | navigator-preview.sh | ⚠️ 追加 | Navigatorの右ペイン（プレビュー）を分離 |
| - | cleanup.sh | ⚠️ 追加 | 不要リソースのクリーンアップ |
| - | diff.sh | ⚠️ 追加 | 差分表示機能 |
| - | help.sh | ⚠️ 追加 | ヘルプ表示 |
| - | kill.sh | ⚠️ 追加 | セッション強制終了 |
| - | rename.sh | ⚠️ 追加 | セッション名変更 |
| - | sidebar.sh | ⚠️ 追加 | サイドバー表示 |
| - | statusline.sh | ⚠️ 追加 | ステータスライン設定 |
| - | tree-view.sh | ⚠️ 追加 | ツリービュー表示 |

---

## 2. ユーザーインターフェース（仕様書セクション3）

### 2.1 Navigatorモードのキー操作

| 仕様書キー | コード実装 | ステータス | 実装場所 |
|------------|------------|------------|----------|
| `j` / `↓` | `j` / `\x1b[B` | ✅ 一致 | navigator-list.sh:369-381 |
| `k` / `↑` | `k` / `\x1b[A` | ✅ 一致 | navigator-list.sh:383-385 |
| `g` | `g` | ✅ 一致 | navigator-list.sh:386-388 |
| `G` | `G` | ✅ 一致 | navigator-list.sh:389-391 |
| `5G` (数字+G) | - | ❌ 未実装 | 数字+Gでの指定ジャンプなし |
| `/pattern` | - | ❌ 未実装 | 検索機能なし |
| `N` | - | ❌ 未実装 | 次の検索結果なし |
| `Enter` | `''` (Enter) | ✅ 一致 | navigator-list.sh:392-394 |
| `i` | `i` | ✅ 一致 | navigator-list.sh:395-397 |
| `n` (新規セッション) | `n` | ✅ 一致 | navigator-list.sh:398-401 |
| `d` | `d` | ✅ 一致 | navigator-list.sh:402-406 |
| `R` | `R` | ✅ 一致 | navigator-list.sh:418-420 |
| `T` (Tileモードへ) | `T` | ✅ 一致 | navigator-list.sh:421-423 |
| `?` | `?` | ✅ 一致 | navigator-list.sh:424-426 |
| `q` | `q` / `Q` | ✅ 一致 | navigator-list.sh:427-429 |

### 2.2 入力モードの仕様対応

| 仕様書 | コード実装 | ステータス |
|--------|------------|------------|
| テキスト入力 → Enter で送信 | ✅ 実装 | input.sh:78-84 |
| `Ctrl-[` でNavigatorに戻る | ❌ 未実装 | Ctrl-C/Ctrl-Dで終了 |
| 送信後も入力モード継続 | ✅ 実装 | input.sh:72-85のループ |

### 2.3 Tileモードのキー操作

| 仕様書キー | コード実装 | ステータス |
|------------|------------|------------|
| `Esc` / `q` | `$'\x1b'` / `q` | ✅ 一致 | tile.sh:147-149, 184-186 |
| `1-9` | `[1-9]` | ✅ 一致 | tile.sh:165-169 |

---

## 3. tmuxキーバインド（仕様書セクション3.2）

| 仕様書キー | 実装 | ステータス | 備考 |
|------------|------|------------|------|
| `prefix + t, c` | ✅ | 一致 | Navigator起動 |
| `prefix + t, t` / `n` | ✅ | 一致 | 新規セッション作成 |
| `prefix + t, l` | ✅ | 一致 | セッション一覧表示 |
| `prefix + t, r` | ✅ | 一致 | 全Dormantセッション復元 |
| `prefix + t, ?` | ✅ | 一致 | ヘルプ表示 |

---

## 4. セッションライフサイクル（仕様書セクション4）

### 4.1 セッション作成コマンド

| 仕様書コマンド | 実装 | ステータス |
|----------------|------|------------|
| `tower new feat-login --worktree` | `-w, --worktree` オプション | ✅ 一致 |
| `tower new feat-login -w` | `-w` オプション | ✅ 一致 |
| `tower new experiment` | デフォルト（Simple） | ✅ 一致 |
| `tower new experiment --dir ~/projects/app` | `-d, --dir DIR` オプション | ✅ 一致 |

### 4.2 Worktree作成フロー

| 仕様書ステップ | 実装 | ステータス | 実装場所 |
|----------------|------|------------|----------|
| 1. セッション名をサニタイズ | ✅ | 一致 | common.sh:sanitize_name() |
| 2. worktreeパス作成 | ✅ | 一致 | `$TOWER_WORKTREE_DIR/<name>` |
| 3. `tower/<name>` ブランチ作成 | ✅ | 一致 | _create_worktree_session() |
| 4. メタデータ保存 | ✅ | 一致 | save_metadata() |
| 5. tmuxセッション作成 | ✅ | 一致 | _start_session_with_claude() |
| 6. `claude` 起動 | ✅ | 一致 | tmux send-keys |

### 4.3 削除確認ダイアログ

仕様書:
```
セッション 'feat-login' を削除します:
  - tmux session: tower_feat-login
  - worktree: ~/.claude-tower/worktrees/feat-login
  - branch: tower/feat-login

本当に削除しますか？ [y/N]
```

実装: `confirm()` 関数（common.sh:413-432）でtmux display-menuを使用
→ ⚠️ 簡略化されている（詳細情報は表示されない）

---

## 5. セッション状態（仕様書セクション2.3）

| 状態 | 仕様書アイコン | コード定数 | コードアイコン | ステータス |
|------|----------------|------------|----------------|------------|
| Running | `◉` | STATE_RUNNING | `◉` | ✅ 一致 |
| Idle | `▶` | STATE_IDLE | `▶` | ✅ 一致 |
| Exited | `!` | STATE_EXITED | `!` | ✅ 一致 |
| Dormant | `○` | STATE_DORMANT | `○` | ✅ 一致 |

---

## 6. データ構造（仕様書セクション6）

### 6.1 ディレクトリ構成

| 仕様書パス | 実装 | ステータス |
|------------|------|------------|
| `~/.claude-tower/metadata/` | `$TOWER_METADATA_DIR` | ✅ 一致 |
| `~/.claude-tower/worktrees/` | `$TOWER_WORKTREE_DIR` | ✅ 一致 |

### 6.2 メタデータファイル

仕様書の形式:
```ini
session_id=tower_feat-login
session_type=worktree
session_name=feat-login
repository_path=/Users/user/projects/my-app
repository_name=my-app
source_commit=abc123def456
worktree_path=/Users/user/.claude-tower/worktrees/feat-login
branch_name=tower/feat-login
created_at=2025-01-01T00:00:00+00:00
```

実装（save_metadata + _create_worktree_session）:
```ini
session_id=${session_id}
session_type=${session_type}  # "worktree" (仕様書と一致)
created_at=$(date -Iseconds)
repository_path=${repository_path}
source_commit=${source_commit}
worktree_path=${TOWER_WORKTREE_DIR}/${session_id#tower_}
session_name=${name}          # ⚠️ 後から追加
branch_name=${branch_name}    # ⚠️ 後から追加
repository_name=$(basename "$repo_path")  # ⚠️ 後から追加
```

→ ✅ 全フィールド実装済み（追加順序は異なる）

### 6.3 tmuxセッション命名規則

| 仕様書 | 実装 | ステータス |
|--------|------|------------|
| `tower_<session_name>` | `normalize_session_name()` → `tower_${name}` | ✅ 一致 |

---

## 7. 状態検出（仕様書セクション8）

### 7.1 Running/Idle判定

仕様書:
- **Idle**: プロンプト表示中（`>` で終わる、または出力停止）
- **Running**: 出力が流れている

実装（get_session_state, common.sh:858-896）:
```bash
# Idle patterns: '> ', 'claude>', '$', 'What would you like', etc.
if echo "$last_lines" | grep -qE '^\s*>\s*$|^\s*claude>\s*$|...'; then
    echo "$STATE_IDLE"
else
    echo "$STATE_RUNNING"
fi
```

→ ✅ 一致（ただし精度は完全ではない）

### 7.2 Exited判定

仕様書:
```bash
pane_cmd=$(tmux display-message -t "$session" -p '#{pane_current_command}')
if [[ "$pane_cmd" != "claude" ]]; then
    # Exited状態
fi
```

実装（get_session_state）:
```bash
if [[ "$pane_cmd" != "$program_name" && "$pane_cmd" != "claude" ]]; then
    echo "$STATE_EXITED"
```

→ ✅ 一致（TOWER_PROGRAMも考慮して拡張）

### 7.3 Dormant判定

仕様書:
```bash
if [[ -f "$metadata_file" ]] && ! tmux has-session -t "$session_id" 2>/dev/null; then
    # Dormant状態
fi
```

実装（get_session_state）:
```bash
if ! tmux has-session -t "$session_id" 2>/dev/null; then
    if has_metadata "$session_id"; then
        echo "$STATE_DORMANT"
```

→ ✅ 一致

---

## 8. 環境変数（仕様書セクション10.2）

| 仕様書変数 | 実装 | デフォルト値 | ステータス |
|------------|------|--------------|------------|
| `CLAUDE_TOWER_PROGRAM` | `TOWER_PROGRAM` | `claude` | ✅ 一致 |
| `CLAUDE_TOWER_WORKTREE_DIR` | `TOWER_WORKTREE_DIR` | `~/.claude-tower/worktrees` | ✅ 一致 |
| `CLAUDE_TOWER_METADATA_DIR` | `TOWER_METADATA_DIR` | `~/.claude-tower/metadata` | ✅ 一致 |
| `CLAUDE_TOWER_DEBUG` | `TOWER_DEBUG` | `0` | ✅ 一致 |

---

## 不整合・不足箇所サマリー

### ❌ 仕様書にあってコードにない機能（将来実装予定）

1. **数字+Gでのジャンプ** (Navigator): `5G`で5番目のセッションへ
2. **検索機能** (Navigator): `/pattern` での検索と `N` での次へ

### ✅ 解決済み（2025-12-27更新）

1. ~~**Tileモードへの遷移**~~: `T` キーで実装済み
2. ~~**session-status.sh**~~: common.shに`get_session_state()`として統合
3. ~~**仕様書の更新**~~: v2.1で全体を更新済み

### ⚠️ 意図的な仕様変更

1. **新規セッション作成キー**: `n` キーを使用（`c`は将来の別機能のため予約）
2. **終了キー**: `q` のみ使用（`Esc`は矢印キーエスケープシーケンスと競合するため）
3. **入力モード終了**: `Ctrl-C`/`Ctrl-D` 使用（`Ctrl-[`はtmux prefix競合の可能性）

### 📝 仕様書に追記済みの機能

1. **navigator-list.sh / navigator-preview.sh**: Navigator分割実装
2. **Socket Separation Architecture**: Navigatorの専用tmuxサーバー
3. **追加スクリプト群**: cleanup.sh, diff.sh, help.sh, kill.sh, rename.sh, etc.

---

## 推奨アクション

### ✅ 完了済み

1. ✅ 仕様書v2.1へ更新（スクリプト構成、キーバインド、アーキテクチャ）
2. ✅ NavigatorにTileモード遷移機能（`T`キー）を追加
3. ✅ 対応表ドキュメント作成

### 📋 将来の実装候補（優先度低）

1. 数字+Gでのジャンプ機能（`5G`で5番目のセッションへ）
2. Navigator検索機能（`/pattern`, `N`）

---

## 更新履歴

| 日付 | 内容 |
|------|------|
| 2025-12-27 | 初版作成、仕様書v2.1との対応確認完了 |
