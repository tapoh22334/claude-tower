# claude-tower 機能仕様書 v2.1

## 1. 概要

### 1.1 プロジェクト名
claude-tower

### 1.2 コンセプト
**並列Claude Codeオーケストレーター**

複数のClaude Codeセッションを効率的に管理・監視・操作するためのtmuxプラグイン。
複数プロジェクト・複数ブランチでの並行開発を支援する。

### 1.3 設計哲学
- **Unix哲学**: tmuxの機能を活用し、足りない部分だけ補う
- **シンプルな状態モデル**: 最小限の状態で最大の効果
- **明示的な操作**: 削除は明示的、復元は自動的

---

## 2. 核となる概念

### 2.1 claude-tower session

セッションの管理単位。メタデータで定義され、tmux session + claude processとして実体化する。

```
claude-tower session = メタデータ（定義）
                     + tmux session（実体、揮発）
                     + claude process（実体、揮発）
                     + worktree（オプション、永続）
```

### 2.2 セッション種別

| 種別 | 識別子 | 永続性 | 自動復元 | ディレクトリ |
|------|--------|--------|----------|--------------|
| **Worktree** | `[W]` | 永続 | あり | 専用worktree |
| **Simple** | `[S]` | 揮発 | なし | 任意ディレクトリ |

**Worktreeセッション**:
- git worktreeによる分離環境
- メタデータ永続化
- tmux/システム再起動後も `claude --continue` で復元可能

**Simpleセッション**:
- 任意のディレクトリで動作
- メタデータは揮発（tmux再起動で消失）
- 軽量な実験・一時作業用

### 2.3 セッション状態

| 状態 | 表示 | 意味 | 対象 |
|------|------|------|------|
| **Running** | `◉` | Claude実行中（出力中） | Active |
| **Idle** | `▶` | Claude入力待ち | Active |
| **Exited** | `!` | Claudeプロセス終了 | Active |
| **Dormant** | `○` | 実体なし（復元待ち） | Worktreeのみ |

---

## 3. ユーザーインターフェース

### 3.1 UIモード

#### 3.1.1 Navigatorモード（デフォルト）

セッションの選択・操作を行うメインUI。

```
┌─ Sessions ─────────────────┐┌─ Preview ─────────────────────────────┐
│ ◉ [W] project-a/feat-login ││                                       │
│ ▶ [W] project-a/fix-perf   ││  [選択中セッションの出力]              │
│ ○ [W] project-b/main       ││                                       │
│ ◉ [S] experiment           ││  user: fix the login bug              │
│                            ││  assistant: I'll analyze the...       │
├────────────────────────────┤│                                       │
│ ⎇ feat-login  +3,-1        ││                                       │
├────────────────────────────┤│                                       │
│ i:input  t:tile  d:delete  ││                                       │
│ n:new    r:restart  ?:help ││                                       │
└────────────────────────────┘└───────────────────────────────────────┘
```

**操作（Vim風）**:
| キー | アクション | 実装状況 |
|------|------------|----------|
| `j` / `↓` | 次のセッションへ | ✅ |
| `k` / `↑` | 前のセッションへ | ✅ |
| `g` | 先頭セッションへ | ✅ |
| `G` | 末尾セッションへ | ✅ |
| `Enter` | セッションにアタッチ | ✅ |
| `i` | 入力モード（選択セッションに指示） | ✅ |
| `n` | 新規セッション作成 | ✅ |
| `d` | セッション削除 | ✅ |
| `R` | Claudeプロセス再起動（大文字） | ✅ |
| `T` | Tileモードへ切り替え（大文字） | ✅ |
| `?` | ヘルプ表示 | ✅ |
| `q` | 終了 | ✅ |

**将来実装予定**:
| キー | アクション |
|------|------------|
| `5G` | 5番目のセッションへ（数字+G） |
| `/pattern` | セッション検索 |
| `N` | 次の検索結果へ |

#### 3.1.2 入力モード

Navigatorから `i` で遷移。選択中のセッションに指示を送信。

- テキスト入力 → Enter で送信
- `Ctrl-C` / `Ctrl-D` で終了
- 送信後も入力モード継続（連続指示可能）

> **Note**: Navigator右ペインから直接セッションに入力可能。`Esc`でリスト操作に戻る。

#### 3.1.3 Tileモード

全セッションを並べて監視する観察専用モード。

```
┌─────────────────────┬─────────────────────┬─────────────────────┐
│ ◉ project-a/login   │ ▶ project-a/perf    │ ◉ experiment        │
│                     │                     │                     │
│ Analyzing the       │ > waiting for input │ Running tests...    │
│ authentication...   │                     │                     │
│                     │                     │                     │
└─────────────────────┴─────────────────────┴─────────────────────┘
```

**操作**:
| キー | アクション |
|------|------------|
| `Esc` / `q` | Navigatorに戻る |
| `1-9` | 該当セッションにフォーカス |

### 3.2 キーバインド（tmux）

2段階キーバインド方式（`prefix + t` でtowerモード → 次のキーで操作）:

| キー | アクション |
|------|------------|
| `prefix + t, c` | Navigator起動 |
| `prefix + t, t` / `n` | 新規セッション作成 |
| `prefix + t, l` | セッション一覧表示 |
| `prefix + t, r` | 全Dormantセッション復元 |
| `prefix + t, ?` | ヘルプ表示 |

---

## 4. セッションライフサイクル

### 4.1 作成

```bash
# Worktreeセッション（永続）
tower new feat-login --worktree
tower new feat-login -w

# Simpleセッション（揮発）
tower new experiment
tower new experiment --dir ~/projects/app
```

**Worktree作成フロー**:
1. セッション名をサニタイズ
2. `~/.claude-tower/worktrees/<name>` にworktree作成
3. `tower/<name>` ブランチ作成
4. メタデータ保存
5. tmuxセッション作成
6. `claude` 起動

**Simple作成フロー**:
1. セッション名をサニタイズ
2. tmuxセッション作成（指定ディレクトリで）
3. `claude` 起動
4. （メタデータは保存しない）

### 4.2 状態遷移

```
                        ┌─────────────┐
        tower new       │   (なし)    │      tower delete
       ┌───────────────►│             │◄────────────────────┐
       │                └─────────────┘                     │
       │                                                    │
       │  ┌──────────────────────────────────────────────┐  │
       │  │             Active States                    │  │
       │  │                                              │  │
       │  │   ┌─────────┐   完了   ┌─────────┐          │  │
       │  │   │ Running │────────►│  Idle   │          │  │
       │  │   │   (◉)   │◄────────│   (▶)   │          │  │
       │  │   └────┬────┘  入力   └────┬────┘          │  │
       │  │        │                   │               │  │
       │  │        │ crash             │               │  │
       │  │        ▼                   │               │  │
       │  │   ┌─────────┐              │               │  │
       │  │   │ Exited  │◄─────────────┘ exit         │  │
       │  │   │   (!)   │                              │  │
       │  │   └────┬────┘                              │  │
       │  │        │ restart                           │  │
       │  │        └──────────────────►(Running)       │  │
       │  │                                              │  │
       │  └────────────────────┬─────────────────────────┘  │
       │                       │                            │
       │                       │ tmux終了/再起動            │
       │                       ▼ (Worktreeのみ)             │
       │                ┌─────────────┐                     │
       │   tower起動時   │  Dormant   │                     │
       └────────────────│    (○)     │─────────────────────┘
           自動復元      └─────────────┘
```

### 4.3 復元（Worktreeセッションのみ）

tower起動時、Dormant状態のセッションを検出して自動復元：
1. メタデータからworktreeパスを取得
2. tmuxセッション作成
3. `claude --continue` で会話継続

### 4.4 削除

```bash
tower delete feat-login
```

**削除対象**:
- tmuxセッション
- メタデータファイル
- worktree（Worktreeセッションの場合）
- ローカルブランチ（リモートにpush済みなら安全）

**確認ダイアログ**:
```
セッション 'feat-login' を削除します:
  - tmux session: tower_feat-login
  - worktree: ~/.claude-tower/worktrees/feat-login
  - branch: tower/feat-login

本当に削除しますか？ [y/N]
```

---

## 5. 表示形式

### 5.1 セッション一覧

```
[状態] [種別] リポジトリ/セッション名   ブランチ      変更状態
  ◉    [W]   project-a/feat-login     ⎇ feat-login   +3,-1
  ▶    [W]   project-a/fix-perf       ⎇ fix-perf
  ○    [W]   project-b/main           ⎇ main         *
  ◉    [S]   experiment               ~/projects/app
```

### 5.2 アイコン凡例

| アイコン | 意味 |
|----------|------|
| `◉` | Running（Claude実行中） |
| `▶` | Idle（入力待ち） |
| `!` | Exited（プロセス終了） |
| `○` | Dormant（復元待ち） |
| `[W]` | Worktreeセッション |
| `[S]` | Simpleセッション |
| `⎇` | Gitブランチ |
| `*` | 未コミット変更あり |
| `+N,-M` | 差分統計 |

---

## 6. データ構造

### 6.1 ディレクトリ構成

```
~/.claude-tower/
├── metadata/
│   └── <session_id>.meta      # Worktreeセッションのメタデータ
└── worktrees/
    └── <session_name>/        # Git worktree
        ├── .git               # Worktree git link
        ├── .claude/           # Claude状態（会話履歴等）
        └── ...                # プロジェクトファイル
```

### 6.2 メタデータファイル

**ファイル名**: `~/.claude-tower/metadata/tower_<session_name>.meta`

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

### 6.3 tmuxセッション命名規則

```
tower_<session_name>
```

例: `tower_feat-login`, `tower_experiment`

---

## 7. スクリプト構成

```
tmux-plugin/
├── claude-tower.tmux          # エントリポイント（キーバインド設定）
├── lib/
│   └── common.sh              # 共通ライブラリ（状態検出含む）
└── scripts/
    ├── tower.sh               # メインコマンド（Navigator起動）
    ├── navigator.sh           # Navigatorモード（メイン）
    ├── navigator-list.sh      # Navigator左ペイン（セッション一覧）
    ├── navigator-preview.sh   # Navigator右ペイン（プレビュー）
    ├── tile.sh                # Tileモード
    ├── session-new.sh         # セッション作成
    ├── session-delete.sh      # セッション削除
    ├── session-restore.sh     # セッション復元
    ├── session-list.sh        # セッション一覧取得（CLI出力）
    ├── input.sh               # 入力モード
    ├── preview.sh             # プレビュー生成（fzf用、レガシー）
    ├── cleanup.sh             # 孤立リソースのクリーンアップ
    ├── diff.sh                # Git差分表示
    ├── help.sh                # ヘルプ表示
    ├── kill.sh                # セッション強制終了
    ├── rename.sh              # セッション名変更
    ├── sidebar.sh             # サイドバー表示
    ├── statusline.sh          # ステータスライン設定
    └── tree-view.sh           # ツリービュー表示
```

> **Note**: 状態検出ロジック(`get_session_state()`)は`common.sh`に統合済み。

### 7.1 Navigatorアーキテクチャ（Socket Separation + Live Preview）

Navigatorは専用のtmuxサーバー（`-L claude-tower`）を使用し、ユーザーのデフォルトtmuxサーバーとは分離されている。

```
┌─────────────────────────────────────────────────────────────────┐
│                   Default tmux server                           │
│  ┌────────────┐ ┌────────────┐ ┌────────────┐                 │
│  │ tower_api  │ │ tower_feat │ │ user_shell │                 │
│  │ (Claude)   │ │ (Claude)   │ │            │                 │
│  └────────────┘ └────────────┘ └────────────┘                 │
└───────────────────────────┬─────────────────────────────────────┘
                            │ Right pane connects via:
                            │ TMUX= tmux -f inner.conf attach -t <session>
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│              Navigator server (-L claude-tower)                 │
│  ┌────────────────┬─────────────────────────────────────────┐  │
│  │ Session List   │           Live Preview                   │  │
│  │                │                                          │  │
│  │ ▶ tower_api    │  ┌─────────────────────────────────────┐ │  │
│  │   tower_feat   │  │ [Nested tmux: tower_api session]    │ │  │
│  │   tower_exp    │  │                                     │ │  │
│  │                │  │ user: fix the login bug             │ │  │
│  │ ────────────── │  │ assistant: I'll analyze the auth... │ │  │
│  │ j/k: navigate  │  │                                     │ │  │
│  │ i: focus right │  │ (Real-time output from Claude)      │ │  │
│  │ q: quit        │  └─────────────────────────────────────┘ │  │
│  └────────────────┴─────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

**アーキテクチャの特徴**:

1. **Socket Separation**: Navigatorは専用サーバー（`-L claude-tower`）で動作
2. **Live Preview**: 右paneはデフォルトサーバーのセッションにnested tmuxで接続
3. **Seamless Switching**: `switch-client`で自然にNavigator ↔ セッション間を遷移

**右pane（ライブプレビュー）の動作**:

```
navigator-preview.sh のメインループ:

1. 選択中セッションIDを取得 (state file)
2. セッション状態を確認
   - Active: nested tmuxでattach（inner-tmux.confを使用）
   - Dormant: 復元待ちメッセージを表示
   - なし: プレースホルダーを表示
3. Escapeで detach → ループ先頭へ（新しい選択を反映）
```

**inner-tmux.conf**:
```bash
set -g prefix None      # プレフィックス無効化
bind -n Escape detach   # Escapeでdetach（Navigatorに戻る）
set -g status off       # ステータスバー非表示
```

**遷移フロー**:

```
User's Session                   Navigator
     │                              │
     │ ── prefix + t c ──────────►  │ (switch to Navigator)
     │                              │
     │                         ┌────┴────┐
     │                         │ Session │ ◄── j/k で選択
     │                         │  List   │
     │                         └────┬────┘
     │                              │
     │                         ┌────┴────┐
     │ ◄── Enter (attach) ─── │ Preview │ ◄── i で入力モード
     │                         │ (nested)│     Esc でリストに戻る
     │                         └─────────┘
     │                              │
     │ ◄── q (quit) ─────────────── │ (switch back)
```

**利点**:
- Navigatorがユーザーのセッションを汚染しない
- ネストされたtmuxでリアルタイムプレビューが可能
- 独立したライフサイクル管理
- `switch-client`による自然な遷移（popupの割り込みなし）

---

## 8. 状態検出

状態検出ロジックは `common.sh` の `get_session_state()` 関数に実装されている。

### 8.1 Running/Idle判定

Claude Codeの出力パターンで判定:
- **Idle**: プロンプト表示中（`>` で終わる、`claude>`、入力待ちメッセージなど）
- **Running**: 出力が流れている

**実装** (`common.sh:858-896`):
```bash
# paneの最終5行を取得
last_lines=$(tmux capture-pane -t "$session_id" -p -S -5 2>/dev/null | tail -5 || echo "")

# Idleパターンの検出
if echo "$last_lines" | grep -qE '^\s*>\s*$|^\s*claude>\s*$|^\s*\$\s*$|What would you like|waiting for input|Ready'; then
    echo "$STATE_IDLE"
else
    echo "$STATE_RUNNING"
fi
```

### 8.2 Exited判定

**実装**:
```bash
# claudeプロセス（または設定プログラム）の存在確認
pane_cmd=$(tmux display-message -t "$session_id" -p '#{pane_current_command}')
program_name=$(basename "$TOWER_PROGRAM")  # デフォルト: claude

if [[ "$pane_cmd" != "$program_name" && "$pane_cmd" != "claude" ]]; then
    echo "$STATE_EXITED"
fi
```

### 8.3 Dormant判定

**実装**:
```bash
# tmuxセッションなし + メタデータあり
if ! tmux has-session -t "$session_id" 2>/dev/null; then
    if has_metadata "$session_id"; then
        echo "$STATE_DORMANT"
    else
        echo ""  # セッションは存在しない
    fi
fi
```

---

## 9. 依存関係

### 9.1 必須

| ソフトウェア | バージョン | 用途 |
|--------------|------------|------|
| tmux | 3.2+ | セッション管理（display-popup必須） |
| bash | 4.0+ | スクリプト実行 |
| git | 2.0+ | Worktree管理 |
| Claude Code CLI | - | AIアシスタント |

### 9.2 オプション

なし（fzf依存を削除済み）

---

## 10. 設定オプション

### 10.1 tmux設定（~/.tmux.conf）

```bash
# プラグイン読み込み
run-shell ~/.tmux/plugins/claude-tower/tmux-plugin/claude-tower.tmux

# キーバインドのカスタマイズ
set -g @tower-prefix 't'        # towerモード起動キー（デフォルト: t）
# 使用方法: prefix + t → c/t/n/l/r/?
```

### 10.2 環境変数

| 変数名 | 説明 | デフォルト値 |
|--------|------|--------------|
| `CLAUDE_TOWER_PROGRAM` | 起動するプログラム | `claude` |
| `CLAUDE_TOWER_WORKTREE_DIR` | Worktree保存先 | `~/.claude-tower/worktrees` |
| `CLAUDE_TOWER_METADATA_DIR` | メタデータ保存先 | `~/.claude-tower/metadata` |
| `CLAUDE_TOWER_DEBUG` | デバッグログ出力 | `0` |
| `CLAUDE_TOWER_NAV_SOCKET` | Navigatorのtmuxソケット名 | `claude-tower` |
| `CLAUDE_TOWER_NAV_WIDTH` | Navigator左ペインの幅 | `30` |
| `CLAUDE_TOWER_PREFIX` | towerモードのキー | `t` |

---

## 11. 用語集

| 用語 | 定義 |
|------|------|
| claude-tower session | メタデータで定義されるClaude Codeワーカーの管理単位 |
| Worktreeセッション | git worktreeで分離された永続セッション |
| Simpleセッション | 任意ディレクトリで動作する揮発セッション |
| Navigator | セッション選択・操作を行うメインUI |
| Tileモード | 全セッションを並べて監視するモード |
| Active | tmux session + claude processが存在する状態 |
| Dormant | メタデータのみ存在し、実体がない状態（要復元） |

---

## 12. バージョン履歴

| バージョン | 日付 | 概要 |
|------------|------|------|
| 2.1.0 | 2025-12-27 | 仕様書とコードの対応整備、Socket Separation Architecture追加 |
| 2.0.0 | 2025-01-xx | 設計刷新: 並列オーケストレーターへ |
| 1.0.0 | 2024-xx-xx | 初期リリース |

---

## 付録A: 仕様書とコードの対応表

詳細な対応表は [docs/SPEC_CODE_MAPPING.md](docs/SPEC_CODE_MAPPING.md) を参照。
