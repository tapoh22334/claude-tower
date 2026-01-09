# Claude Tower Navigator 仕様書

Version: 3.4
Date: 2026-01-10

## 1. 概要

Claude Tower は tmux プラグインであり、複数の Claude Code セッションを管理・切り替えるための Navigator UI を提供する。

### 1.1 設計原則

- **tmux ネイティブ**: TUI フレームワークを使わず、tmux の機能のみで実装
- **ソケット分離**: Navigator は専用の tmux サーバーで動作し、ユーザーのセッションと分離
- **永続性**: Navigator セッションは常に生存し、高速な再表示を実現
- **シンプルなフォーカスモデル**: list / view の2つのフォーカス状態のみ
- **冪等性**: 同じ操作を複数回実行しても結果は同じ。状態の不整合があっても安全に動作する

---

## 2. ドメイン語彙

### 2.1 Server（tmuxサーバー）

| 名前 | ソケット | 説明 |
|------|----------|------|
| `default` | (なし) | ユーザーの通常の tmux サーバー |
| `navigator` | `-L claude-tower` | Navigator UI 専用サーバー（制御プレーン） |
| `session` | `-L claude-tower-sessions` | Claude Code セッション専用サーバー（データプレーン） |

**ソケット分離アーキテクチャ**:
- ユーザーの default サーバーから完全に分離
- Navigator がセッションを干渉なく管理可能
- セッションは独立して管理可能
- 懸念事項の明確な分離

### 2.2 Session（tmuxセッション）

| 名前 | 説明 | 所属サーバー |
|------|------|--------------|
| `tower_session` | `tower_{name}` 形式の Claude 作業用セッション | session |
| `navigator` | Navigator UI セッション（常に1つ） | navigator |
| `caller` | Navigator 起動前のセッション（戻り先として記録） | session または default |

### 2.3 View（Navigator の表示モード）

| 名前 | 説明 |
|------|------|
| `list_view` | リスト表示：左に一覧、右に選択中セッションの詳細 |
| `tile_view` | タイル表示：全セッションをグリッド表示、プレビュー付き |

### 2.4 Pane（list_view 内のペイン）

| 名前 | 説明 |
|------|------|
| `list` | 左ペイン、tower_session 一覧を表示 |
| `view` | 右ペイン、選択中セッションの Live 表示 |

### 2.5 Focus（フォーカス位置、list_view のみ）

| 名前 | 説明 | 入力の行き先 |
|------|------|--------------|
| `list` | list ペインにフォーカス | Navigator のキー操作 |
| `view` | view ペインにフォーカス | 選択中の tower_session |

### 2.6 Selection（選択状態）

| 名前 | 説明 |
|------|------|
| `selected` | 現在選択中の tower_session、または `none` |

### 2.7 SessionState（セッションの状態）

| 状態 | アイコン | 説明 |
|------|----------|------|
| `active` | `▶` | tmux セッションが存在する |
| `dormant` | `○` | tmux セッションなし、メタデータのみ存在 |

**状態判定ルール**（冪等性のため単純化）:
- `session_tmux has-session -t $session_id` が成功 → `active`
- `session_tmux has-session` が失敗 かつ メタデータ存在 → `dormant`
- どちらでもない → 存在しない

**注記**: `session_tmux` は session サーバー (`-L claude-tower-sessions`) へのコマンド実行ヘルパー

**注意**: `exited` 状態（Claude が終了済み）は廃止。tmux セッションが存在すれば `active` として扱う。Claude の実行状態はセッション内で判断すべき情報であり、Navigator の状態判定を複雑化させない。

---

## 3. 状態遷移

### 3.1 ユーザーターミナル状態

```
                               prefix+t
    ┌──────────────┐ ────────────────────────> ┌──────────────┐
    │              │                           │              │
    │   WORKING    │                           │  NAVIGATOR   │
    │  (default)   │ <──────────────────────── │ (navigator)  │
    │              │      q / Enter            │              │
    └──────────────┘                           └──────────────┘
           ▲                                          │
           │                                          │
           └──────────── prefix+t ────────────────────┘
                      (from full attach)
```

### 3.2 Navigator ビュー状態

```
                          Tab
    ┌──────────────┐ ─────────────────────────> ┌──────────────┐
    │              │                            │              │
    │  list_view   │                            │  tile_view   │
    │              │ <───────────────────────── │              │
    └──────────────┘      Tab / 1-9             └──────────────┘
           │                                           │
           │ Enter                                     │ Enter / 1-9
           ▼                                           ▼
    ┌──────────────┐                            ┌──────────────┐
    │  FULL ATTACH │                            │  FULL ATTACH │
    │  (default)   │                            │  (default)   │
    └──────────────┘                            └──────────────┘
```

### 3.3 list_view フォーカス状態

```
                                   i
    ┌──────────────┐ ────────────────────────> ┌──────────────┐
    │              │                           │              │
    │  focus:list  │                           │  focus:view  │
    │              │ <──────────────────────── │              │
    └──────────────┘      j/k または            └──────────────┘
                       ペイン移動で戻る
```

**注意**: focus:view から focus:list への遷移は、ユーザーがペイン移動（prefix + 矢印など）で
list ペインに戻り、j/k を押した時に発生する。Escape キーによる戻りは廃止。

---

## 4. 操作定義

### 4.1 open_navigator

| 項目 | 内容 |
|------|------|
| トリガー | `prefix + t` |
| コンテキスト | default server のセッションにアタッチ中 |
| 前提条件 | current ∈ Session(default) |
| 事後条件 | caller := current, user attached to navigator, focus := list |
| 不変条件 | default server sessions unchanged |

**セッション0個の場合**:
- Navigator を表示
- view ペインに案内メッセージ表示: "No sessions. Press 'n' to create."
- selected := none

### 4.2 select_next / select_prev

| 項目 | 内容 |
|------|------|
| トリガー | `j` / `k` |
| コンテキスト | Navigator, focus = list, selected ≠ none |
| 前提条件 | tower_sessions.count > 0 |
| 事後条件 | selected := next/prev (wrap around), view reconnects |
| 不変条件 | focus = list |

### 4.3 focus_view

| 項目 | 内容 |
|------|------|
| トリガー | `i` |
| コンテキスト | Navigator, focus = list, selected ≠ none |
| 前提条件 | selected.state = active |
| 事後条件 | focus := view, user input → selected session |
| 不変条件 | Navigator visible, list pane visible |

### 4.4 focus_list

| 項目 | 内容 |
|------|------|
| トリガー | `j/k` または ペイン移動 |
| コンテキスト | Navigator, focus = view, user navigated to list pane |
| 前提条件 | focus = view |
| 事後条件 | focus := list, view uses switch-client for session switching |

**注意**: Escape キーによる戻りは廃止。ユーザーは tmux のペイン移動（prefix + 矢印など）で
list ペインに戻り、j/k を押すことで focus:list に遷移する。

### 4.5 full_attach

| 項目 | 内容 |
|------|------|
| トリガー | `Enter` |
| コンテキスト | Navigator, focus = list, selected ≠ none |
| 前提条件 | selected ∈ tower_sessions |
| 事後条件 | user attached to selected (session server), navigator session alive |

**dormant セッションの場合**: 自動 restore 後にアタッチ

### 4.6 quit_navigator

| 項目 | 内容 |
|------|------|
| トリガー | `q` |
| コンテキスト | Navigator, focus = list |
| 事後条件 | user attached to caller (or any session), navigator session alive |

**caller が存在しない場合**: session server を優先して検索し、見つからなければ default server の任意のセッションにアタッチ

### 4.7 create_session

| 項目 | 内容 |
|------|------|
| トリガー | `n` |
| コンテキスト | Navigator, focus = list |
| 事後条件 | new tower_session created, selected := new session, focus := list |

**処理フロー**:
1. list ペイン内でインライン入力プロンプト表示
2. セッション名入力
3. Worktree 選択（オプション）
4. セッション作成（Navigator に留まる）

### 4.8 delete_session

| 項目 | 内容 |
|------|------|
| トリガー | `D` |
| コンテキスト | Navigator, focus = list, selected ≠ none |
| 事後条件 | selected session deleted, selected := next available or none |

### 4.9 restore_session

| 項目 | 内容 |
|------|------|
| トリガー | `r` |
| コンテキスト | Navigator, focus = list, selected ≠ none |
| 前提条件 | なし（冪等） |
| 事後条件 | selected session が active 状態になる |

**冪等動作**:
- `dormant` → 復元して `active` に
- `active` → 何もしない（すでに active）
- メタデータなし → 何もしない（復元不可）

**注意**: エラーにしない。状態不整合があっても安全に最終状態を達成する。

### 4.10 restore_all_sessions

| 項目 | 内容 |
|------|------|
| トリガー | `R` |
| コンテキスト | Navigator, focus = list |
| 前提条件 | dormant_sessions.count > 0 |
| 事後条件 | all dormant sessions restored, リスト更新 |

**dormant セッションがない場合**: "No dormant sessions" を表示

### 4.11 switch_to_tile_view

| 項目 | 内容 |
|------|------|
| トリガー | `Tab` |
| コンテキスト | Navigator, list_view |
| 事後条件 | view := tile_view, selected unchanged |

### 4.10 switch_to_list_view

| 項目 | 内容 |
|------|------|
| トリガー | `Tab` |
| コンテキスト | Navigator, tile_view |
| 事後条件 | view := list_view, selected unchanged |

### 4.11 tile_select_and_switch

| 項目 | 内容 |
|------|------|
| トリガー | `1-9` |
| コンテキスト | Navigator, tile_view |
| 事後条件 | selected := session at index, view := list_view |

**補足**: 存在しないインデックスの場合は無視

---

## 5. エッジケース

| ケース | 挙動 |
|--------|------|
| tower_sessions.count = 0 at open | Navigator 表示、view に案内メッセージ |
| caller not exists at quit | session server → default server の順で検索してアタッチ |
| selected deleted externally | リスト再構築、次のセッションを選択 |
| full_attach to dormant session | 自動 restore 後にアタッチ |
| focus:view から戻る | ペイン移動で list に戻り、j/k で focus:list に遷移 |

---

## 6. キーバインド一覧

### 6.1 tmux キーバインド

| キー | 動作 |
|------|------|
| `prefix + t` | Navigator 起動（直接） |

**廃止**: `prefix + t, c/n/l/r` の2段階キーバインドを廃止。すべての操作は Navigator 内で行う。

### 6.2 Navigator キーバインド（list_view, focus: list）

| キー | 動作 |
|------|------|
| `j` / `↓` | 次のセッションを選択 |
| `k` / `↑` | 前のセッションを選択 |
| `g` | 最初のセッションを選択 |
| `G` | 最後のセッションを選択 |
| `1-9` | 該当セッションを選択 |
| `Enter` | Full Attach（dormant の場合は復元してアタッチ） |
| `i` | focus:view に切り替え（入力可能） |
| `Tab` | tile_view に切り替え |
| `n` | 新規セッション作成 |
| `D` | 選択セッション削除 |
| `r` | 選択中の dormant セッションを復元 |
| `R` | 全 dormant セッションを復元 |
| `q` | Navigator 終了（caller に戻る） |
| `?` | ヘルプ表示 |

### 6.3 Navigator キーバインド（list_view, focus: view）

| キー | 動作 |
|------|------|
| すべて | 選択セッションに送信 |

**注意**: focus:view からの戻りは、ペイン移動（prefix + 矢印など）で list ペインに戻り、
j/k を押すことで実現する。Escape キーによる戻りは廃止。

### 6.4 Navigator キーバインド（tile_view）

| キー | 動作 |
|------|------|
| `j` / `↓` | 次のセッションを選択 |
| `k` / `↑` | 前のセッションを選択 |
| `1-9` | 該当セッションを選択 + list_view に切替 |
| `Enter` | 選択中のセッションで list_view に切替 |
| `Tab` | list_view に切り替え |
| `r` | 表示を更新 |
| `q` | Navigator 終了（caller に戻る） |

**補足**: tile_view からの Full Attach はなし。list_view で操作する設計。Escape キーは使用不可。

---

## 7. ファイル構成

```
tmux-plugin/
├── claude-tower.tmux          # キーバインド設定
├── lib/
│   ├── common.sh              # 共通関数・定数・ドメインロジック
│   └── error-recovery.sh      # エラー処理・リカバリーユーティリティ
├── scripts/
│   ├── navigator.sh           # Navigator エントリーポイント
│   ├── navigator-list.sh      # list_view: list pane プロセス
│   ├── navigator-view.sh      # list_view: view pane プロセス
│   ├── tile.sh                # tile_view プロセス
│   ├── session-new.sh         # セッション作成
│   ├── session-delete.sh      # セッション削除
│   └── session-restore.sh     # セッション復元
└── conf/
    └── view-focus.conf        # focus:view 時の tmux 設定
```

## 7.1 ソケット設定

| 変数名 | デフォルト値 | 説明 |
|--------|--------------|------|
| `TOWER_NAV_SOCKET` | `claude-tower` | Navigator サーバーソケット |
| `TOWER_SESSION_SOCKET` | `claude-tower-sessions` | セッションサーバーソケット |
| `TOWER_NAV_WIDTH` | `24` | Navigator list ペイン幅（文字数） |

**ヘルパー関数**:
- `nav_tmux`: Navigator サーバーへのコマンド実行 (`tmux -L $TOWER_NAV_SOCKET`)
- `session_tmux`: Session サーバーへのコマンド実行 (`TMUX= tmux -L $TOWER_SESSION_SOCKET`)

---

## 8. 状態ファイル

```
/tmp/claude-tower/
├── caller      # Navigator 起動前のセッション名
├── selected    # 現在選択中の tower_session ID（"none" or "tower_xxx"）
├── focus       # 現在のフォーカス（"list" or "view"）
└── view        # 現在のビュー（"list_view" or "tile_view"）
```

---

## 9. 設計決定事項

| 項目 | 決定 | 理由 |
|------|------|------|
| セッション作成後の動作 | Navigator に留まる | 連続作成を可能に |
| Navigator の永続性 | 常に生存 | 高速な再表示 |
| セッション作成 UI | Navigator 内でインライン | コンテキスト切り替えなし |
| view からの戻り | ペイン移動 + j/k | Escape キーによる戻りは廃止 |
| セッションサーバー分離 | session server で隔離 | ユーザー環境から完全に分離 |
| tile_view の役割 | 俯瞰・選択のみ | list_view で詳細操作する設計 |
| tile_view からの Full Attach | なし | シンプルさ優先、list_view 経由で操作 |

---

## 更新履歴

| バージョン | 日付 | 内容 |
|------------|------|------|
| 3.4 | 2026-01-10 | キーバインド変更: 削除キーを `d` → `D` に変更。tile_view から Escape キーを削除 |
| 3.3 | 2026-01-04 | ソケット分離: セッションを専用サーバー (`claude-tower-sessions`) に隔離。Navigator 幅を 24 に変更 |
| 3.2 | 2026-01-03 | キーバインド簡素化: `prefix+t` で直接 Navigator 起動。dormant 復元キー追加 (`r`, `R`) |
| 3.1 | 2026-01-02 | tile_view 追加。list_view/tile_view の2ビュー切替方式を採用 |
| 3.0 | 2026-01-02 | 厳密な仕様書として再作成。ドメイン語彙・操作定義・エッジケースを明確化 |
| 2.x | - | 旧仕様（navigator-architecture.md 参照） |
