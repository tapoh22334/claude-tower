# Claude Tower Navigator 仕様書

Version: 3.0
Date: 2026-01-02

## 1. 概要

Claude Tower は tmux プラグインであり、複数の Claude Code セッションを管理・切り替えるための Navigator UI を提供する。

### 1.1 設計原則

- **tmux ネイティブ**: TUI フレームワークを使わず、tmux の機能のみで実装
- **ソケット分離**: Navigator は専用の tmux サーバーで動作し、ユーザーのセッションと分離
- **永続性**: Navigator セッションは常に生存し、高速な再表示を実現
- **シンプルなフォーカスモデル**: list / view の2つのフォーカス状態のみ

---

## 2. ドメイン語彙

### 2.1 Server（tmuxサーバー）

| 名前 | 説明 |
|------|------|
| `default` | ユーザーの通常の tmux サーバー（ソケット指定なし） |
| `navigator` | Navigator 専用サーバー（`-L claude-tower`） |

### 2.2 Session（tmuxセッション）

| 名前 | 説明 | 所属サーバー |
|------|------|--------------|
| `tower_session` | `tower_{name}` 形式の Claude 作業用セッション | default |
| `navigator` | Navigator UI セッション（常に1つ） | navigator |
| `caller` | Navigator 起動前のセッション（戻り先として記録） | default |

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
| `active` | `▶` | claude が動作中 |
| `exited` | `!` | claude が終了済み |
| `dormant` | `○` | tmux セッションなし、メタデータのみ存在 |

---

## 3. 状態遷移

### 3.1 ユーザーターミナル状態

```
                              prefix+tc
    ┌──────────────┐ ────────────────────────> ┌──────────────┐
    │              │                           │              │
    │   WORKING    │                           │  NAVIGATOR   │
    │  (default)   │ <──────────────────────── │ (navigator)  │
    │              │      q / Enter            │              │
    └──────────────┘                           └──────────────┘
           ▲                                          │
           │                                          │
           └──────────── prefix+tc ───────────────────┘
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
    └──────────────┘         Escape            └──────────────┘
```

---

## 4. 操作定義

### 4.1 open_navigator

| 項目 | 内容 |
|------|------|
| トリガー | `prefix + t, c` |
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
| 前提条件 | selected.state ∈ {active, exited} |
| 事後条件 | focus := view, user input → selected session |
| 不変条件 | Navigator visible, list pane visible |

### 4.4 focus_list

| 項目 | 内容 |
|------|------|
| トリガー | `Escape` |
| コンテキスト | Navigator, focus = view |
| 前提条件 | focus = view |
| 事後条件 | focus := list, view continues showing selected |

### 4.5 full_attach

| 項目 | 内容 |
|------|------|
| トリガー | `Enter` |
| コンテキスト | Navigator, focus = list, selected ≠ none |
| 前提条件 | selected ∈ tower_sessions |
| 事後条件 | user attached to selected (default server), navigator session alive |

**dormant セッションの場合**: 自動 restore 後にアタッチ

### 4.6 quit_navigator

| 項目 | 内容 |
|------|------|
| トリガー | `q` |
| コンテキスト | Navigator, focus = list |
| 事後条件 | user attached to caller (or any session), navigator session alive |

**caller が存在しない場合**: default server の任意のセッションにアタッチ

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
| トリガー | `d` |
| コンテキスト | Navigator, focus = list, selected ≠ none |
| 事後条件 | selected session deleted, selected := next available or none |

### 4.9 switch_to_tile_view

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
| caller not exists at quit | default server の任意のセッションにアタッチ |
| selected deleted externally | リスト再構築、次のセッションを選択 |
| full_attach to dormant session | 自動 restore 後にアタッチ |
| Escape when focus = list | 無視（何もしない） |
| view pane で Escape 連打 | 最初の Escape で focus:list、以降は無視 |

---

## 6. キーバインド一覧

### 6.1 tmux キーバインド

| キー | 動作 |
|------|------|
| `prefix + t, c` | Navigator 起動 |
| `prefix + t, n` | 新規セッション作成（Navigator 外から） |
| `prefix + t, l` | セッション一覧表示 |
| `prefix + t, r` | 全 Dormant セッション復元 |

### 6.2 Navigator キーバインド（list_view, focus: list）

| キー | 動作 |
|------|------|
| `j` / `↓` | 次のセッションを選択 |
| `k` / `↑` | 前のセッションを選択 |
| `g` | 最初のセッションを選択 |
| `G` | 最後のセッションを選択 |
| `1-9` | 該当セッションを選択 |
| `Enter` | Full Attach（選択セッションに直接アタッチ） |
| `i` | focus:view に切り替え（入力可能） |
| `Tab` | tile_view に切り替え |
| `n` | 新規セッション作成 |
| `d` | 選択セッション削除 |
| `R` | Claude 再起動 |
| `q` | Navigator 終了（caller に戻る） |
| `?` | ヘルプ表示 |

### 6.3 Navigator キーバインド（list_view, focus: view）

| キー | 動作 |
|------|------|
| `Escape` | focus:list に戻る |
| その他 | 選択セッションに送信 |

### 6.4 Navigator キーバインド（tile_view）

| キー | 動作 |
|------|------|
| `j` / `↓` | 次のセッションを選択 |
| `k` / `↑` | 前のセッションを選択 |
| `1-9` | 該当セッションを選択 + list_view に切替 |
| `Enter` | 選択中のセッションで list_view に切替 |
| `Tab` | list_view に切り替え |
| `r` | 表示を更新 |
| `q` / `Escape` | Navigator 終了（caller に戻る） |

**補足**: tile_view からの Full Attach はなし。list_view で操作する設計。

---

## 7. ファイル構成

```
tmux-plugin/
├── claude-tower.tmux          # キーバインド設定
├── lib/
│   └── common.sh              # 共通関数・定数・ドメインロジック
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
| view からの戻り | Escape | 直感的、vim と競合しても Full Attach を使う |
| tile_view の役割 | 俯瞰・選択のみ | list_view で詳細操作する設計 |
| tile_view からの Full Attach | なし | シンプルさ優先、list_view 経由で操作 |

---

## 更新履歴

| バージョン | 日付 | 内容 |
|------------|------|------|
| 3.1 | 2026-01-02 | tile_view 追加。list_view/tile_view の2ビュー切替方式を採用 |
| 3.0 | 2026-01-02 | 厳密な仕様書として再作成。ドメイン語彙・操作定義・エッジケースを明確化 |
| 2.x | - | 旧仕様（navigator-architecture.md 参照） |
