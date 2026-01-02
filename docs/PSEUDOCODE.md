# Claude Tower Navigator 疑似コード

Version: 3.0
Date: 2026-01-02

本ドキュメントは SPECIFICATION.md の操作定義を実装するための疑似コードを提供する。

---

## 1. claude-tower.tmux

```bash
# ═══════════════════════════════════════════════════════════════════════════
# キーバインド設定
# ═══════════════════════════════════════════════════════════════════════════

TOWER_PREFIX = get_option("@tower-prefix", "t")

# Tower key table
bind $TOWER_PREFIX switch-client -T tower

# prefix + t, c → Navigator起動
bind -T tower c  run-shell -b {
    # caller を保存（run-shell は format string を展開する）
    mkdir -p /tmp/claude-tower
    echo '#{session_name}' > /tmp/claude-tower/caller

    # detach-client -E で現在のセッションから離脱し、navigator.sh を実行
    tmux detach-client -E "$SCRIPT_DIR/navigator.sh"
}

# prefix + t, n → セッション作成（Navigator外から）
bind -T tower n  run-shell -b {
    # 現在のpane_current_pathを環境変数で渡す
    env TOWER_WORKING_DIR='#{pane_current_path}' \
        tmux new-window -n "tower-new" "$SCRIPT_DIR/session-new.sh"
}
```

---

## 2. navigator.sh（エントリーポイント）

```bash
# ═══════════════════════════════════════════════════════════════════════════
# Navigator エントリーポイント
# detach-client -E から呼ばれる（ターミナル直接実行）
# ═══════════════════════════════════════════════════════════════════════════

main():
    caller = read_file("/tmp/claude-tower/caller")

    # Navigator セッションが既に存在するか確認
    IF nav_session_exists():
        # 既存セッションにアタッチ（高速）
        signal_list_refresh()
        TMUX= exec tmux -L claude-tower attach -t navigator
    END

    # tower_sessions を取得
    sessions = get_tower_sessions()

    # Navigator セッション作成
    TMUX= tmux -L claude-tower new-session -d -s navigator \
        -x $(tput cols) -y $(tput lines)

    # 2ペイン構成（左30%:list、右70%:view）
    tmux -L claude-tower split-window -t navigator -h -l 70%

    # 初期選択・初期フォーカス
    IF sessions.count > 0:
        set_selected(sessions.first)
    ELSE:
        set_selected("none")
    END
    set_focus("list")

    # 各ペインでスクリプト起動
    tmux -L claude-tower send-keys -t navigator:0.0 \
        "$SCRIPT_DIR/navigator-list.sh" Enter
    tmux -L claude-tower send-keys -t navigator:0.1 \
        "$SCRIPT_DIR/navigator-view.sh" Enter

    # list pane にフォーカス
    tmux -L claude-tower select-pane -t navigator:0.0

    # Navigator にアタッチ
    TMUX= exec tmux -L claude-tower attach -t navigator
```

---

## 3. navigator-list.sh（list pane）

```bash
# ═══════════════════════════════════════════════════════════════════════════
# List Pane プロセス
# セッション一覧表示、キー入力処理
# ═══════════════════════════════════════════════════════════════════════════

# 状態
sessions = []          # tower_session のリスト
selected_index = 0     # 現在の選択インデックス

main_loop():
    build_session_list()

    LOOP:
        render()

        key = read_key(timeout: 2sec)

        IF timeout:
            # 定期リフレッシュ
            build_session_list()
            validate_selection()
            CONTINUE
        END

        handle_key(key)
    END

handle_key(key):
    SWITCH key:
        CASE 'j', DOWN:
            select_next()

        CASE 'k', UP:
            select_prev()

        CASE 'g':
            select_first()

        CASE 'G':
            select_last()

        CASE 'i':
            focus_view()

        CASE ENTER:
            full_attach()

        CASE 'n':
            create_session_inline()

        CASE 'd':
            delete_session_with_confirm()

        CASE 'R':
            restart_claude()

        CASE 'q':
            quit_navigator()

        CASE '?':
            show_help()
    END

# ─────────────────────────────────────────────────────────────────────────
# 選択操作
# ─────────────────────────────────────────────────────────────────────────

select_next():
    IF sessions.count == 0:
        RETURN
    END
    selected_index = (selected_index + 1) % sessions.count
    update_selection()

select_prev():
    IF sessions.count == 0:
        RETURN
    END
    selected_index = (selected_index - 1 + sessions.count) % sessions.count
    update_selection()

select_first():
    IF sessions.count == 0:
        RETURN
    END
    selected_index = 0
    update_selection()

select_last():
    IF sessions.count == 0:
        RETURN
    END
    selected_index = sessions.count - 1
    update_selection()

update_selection():
    selected = sessions[selected_index]
    write_file("/tmp/claude-tower/selected", selected.id)
    signal_view_update()

signal_view_update():
    # view pane に更新シグナル送信
    # Escape を送って現在の接続を切断させる
    tmux -L claude-tower send-keys -t navigator:0.1 Escape

# ─────────────────────────────────────────────────────────────────────────
# フォーカス切り替え
# ─────────────────────────────────────────────────────────────────────────

focus_view():
    selected = get_selected()
    IF selected == "none":
        RETURN
    END

    state = get_session_state(selected)
    IF state == "dormant":
        RETURN  # dormant セッションには focus_view 不可
    END

    set_focus("view")
    tmux -L claude-tower select-pane -t navigator:0.1

# ─────────────────────────────────────────────────────────────────────────
# アタッチ・終了
# ─────────────────────────────────────────────────────────────────────────

full_attach():
    selected = get_selected()
    IF selected == "none":
        RETURN
    END

    state = get_session_state(selected)
    IF state == "dormant":
        restore_session(selected)
        # 復元失敗時はリスト再構築して終了
        IF NOT session_exists(selected):
            show_error("Failed to restore session")
            build_session_list()
            RETURN
        END
    END

    IF NOT session_exists(selected):
        show_error("Session not found")
        build_session_list()
        RETURN
    END

    # Navigator を離れて default server にアタッチ
    tmux -L claude-tower detach-client -E "TMUX= tmux attach -t '$selected'"

quit_navigator():
    caller = read_file("/tmp/claude-tower/caller")

    IF caller exists AND session_exists(caller):
        target = caller
    ELSE:
        target = get_any_session_from_default()
    END

    IF target != none:
        tmux -L claude-tower detach-client -E "TMUX= tmux attach -t '$target'"
    ELSE:
        # default server にセッションがない
        tmux -L claude-tower detach-client
    END

# ─────────────────────────────────────────────────────────────────────────
# セッション操作
# ─────────────────────────────────────────────────────────────────────────

create_session_inline():
    # list pane 内でインライン入力
    clear_prompt_area()
    print "Name: "
    name = read_line()

    IF name is empty:
        RETURN  # キャンセル
    END

    print "Worktree? [y/N]: "
    worktree = read_char() in ['y', 'Y']

    # セッション作成（default server に）
    result = create_tower_session(name, worktree)

    IF result.success:
        build_session_list()
        select_session_by_id(result.session_id)
    ELSE:
        show_error(result.error)
    END

delete_session_with_confirm():
    selected = get_selected()
    IF selected == "none":
        RETURN
    END

    name = selected.replace("tower_", "")
    print "Delete '$name'? [y/N]: "
    confirm = read_char()

    IF confirm in ['y', 'Y']:
        delete_session(selected)
        build_session_list()
        validate_selection()
    END

restart_claude():
    selected = get_selected()
    IF selected == "none":
        RETURN
    END

    # default server のセッションに対して操作
    TMUX= tmux send-keys -t "$selected" C-c
    sleep 0.2
    TMUX= tmux send-keys -t "$selected" "claude" Enter

# ─────────────────────────────────────────────────────────────────────────
# 表示
# ─────────────────────────────────────────────────────────────────────────

render():
    clear()

    print_header("Sessions")

    IF sessions.count == 0:
        print "(no sessions)"
    ELSE:
        FOR i, session IN sessions:
            IF i == selected_index:
                print_highlighted(format_session(session))
            ELSE:
                print(format_session(session))
        END
    END

    print_footer()  # キーバインドヘルプ

validate_selection():
    # セッションが削除された場合の選択補正
    IF sessions.count == 0:
        set_selected("none")
        selected_index = 0
        RETURN
    END

    IF selected_index >= sessions.count:
        selected_index = sessions.count - 1
    END

    update_selection()
```

---

## 4. navigator-view.sh（view pane）

```bash
# ═══════════════════════════════════════════════════════════════════════════
# View Pane プロセス
# 選択中セッションの Live 表示
# ═══════════════════════════════════════════════════════════════════════════

main_loop():
    LOOP:
        selected = read_file("/tmp/claude-tower/selected")
        focus = read_file("/tmp/claude-tower/focus")

        IF selected is empty OR selected == "none":
            show_no_session_message()
            sleep 1
            CONTINUE
        END

        state = get_session_state(selected)

        SWITCH state:
            CASE "dormant":
                show_dormant_info(selected)
                wait_for_signal()  # Escape待ち

            CASE "active", "exited":
                attach_to_session(selected, focus)
                # Escape で戻ってくる
                # focus を list に戻す
                set_focus("list")

            DEFAULT:
                show_error("Session not found")
                sleep 1
        END
    END

attach_to_session(session_id, focus):
    IF focus == "view":
        # 入力可能モード
        TMUX= tmux -f $CONF_DIR/view-focus.conf attach -t $session_id
    ELSE:
        # 表示のみモード（read-only）
        TMUX= tmux -f $CONF_DIR/view-focus.conf attach -t $session_id -r
    END

show_no_session_message():
    clear()
    print "
    ┌───────────────────────────────────────┐
    │                                       │
    │   No sessions available               │
    │                                       │
    │   Press 'n' to create a new session   │
    │                                       │
    └───────────────────────────────────────┘
    "

show_dormant_info(session_id):
    clear()
    name = session_id.replace("tower_", "")
    print "
    ┌───────────────────────────────────────┐
    │                                       │
    │   Session: $name                      │
    │   Status: Dormant (not running)       │
    │                                       │
    │   Press Enter to restore and attach   │
    │                                       │
    └───────────────────────────────────────┘
    "
    # メタデータがあれば表示
    IF has_metadata(session_id):
        load_metadata(session_id)
        print "  Repository: $META_REPOSITORY_PATH"
        print "  Worktree: $META_WORKTREE_PATH"
    END
```

---

## 5. view-focus.conf

```bash
# ═══════════════════════════════════════════════════════════════════════════
# View Pane 用 tmux 設定
# Escape のみを intercept し、他は全て透過
# ═══════════════════════════════════════════════════════════════════════════

# Prefix 無効化
set -g prefix None
set -g prefix2 None
unbind-key -a

# Escape で detach
bind-key -n Escape detach-client

# ステータスバー非表示
set -g status off

# 高速 Escape（遅延なし）
set -sg escape-time 0

# マウス無効
set -g mouse off

# ターミナル設定
set -g default-terminal "screen-256color"
set -ga terminal-overrides ",*256col*:Tc"

# 大きな履歴
set -g history-limit 50000
```

---

## 6. 状態ファイル操作

```bash
# ═══════════════════════════════════════════════════════════════════════════
# 状態ファイル操作（common.sh に実装）
# ═══════════════════════════════════════════════════════════════════════════

STATE_DIR = "/tmp/claude-tower"

ensure_state_dir():
    mkdir -p "$STATE_DIR"
    chmod 700 "$STATE_DIR"

get_selected():
    IF file_exists("$STATE_DIR/selected"):
        RETURN read_file("$STATE_DIR/selected")
    ELSE:
        RETURN "none"
    END

set_selected(session_id):
    ensure_state_dir()
    write_file("$STATE_DIR/selected", session_id)

get_focus():
    IF file_exists("$STATE_DIR/focus"):
        RETURN read_file("$STATE_DIR/focus")
    ELSE:
        RETURN "list"
    END

set_focus(focus):
    ensure_state_dir()
    write_file("$STATE_DIR/focus", focus)

get_caller():
    IF file_exists("$STATE_DIR/caller"):
        RETURN read_file("$STATE_DIR/caller")
    ELSE:
        RETURN ""
    END
```

---

## 7. ヘルパー関数

```bash
# ═══════════════════════════════════════════════════════════════════════════
# ヘルパー関数（common.sh に実装）
# ═══════════════════════════════════════════════════════════════════════════

nav_session_exists():
    tmux -L claude-tower has-session -t navigator 2>/dev/null

session_exists(session_id):
    TMUX= tmux has-session -t "$session_id" 2>/dev/null

get_tower_sessions():
    # default server から tower_* セッションを取得
    sessions = []
    FOR session IN $(TMUX= tmux list-sessions -F '#{session_name}'):
        IF session.startswith("tower_"):
            sessions.append(session)
        END
    END
    RETURN sessions

get_session_state(session_id):
    IF NOT session_exists(session_id):
        IF has_metadata(session_id):
            RETURN "dormant"
        ELSE:
            RETURN ""
        END
    END

    pane_cmd = TMUX= tmux display-message -t "$session_id" -p '#{pane_current_command}'
    IF pane_cmd in ["claude", TOWER_PROGRAM]:
        RETURN "active"
    ELSE:
        RETURN "exited"
    END

get_any_session_from_default():
    sessions = TMUX= tmux list-sessions -F '#{session_name}' 2>/dev/null
    IF sessions.count > 0:
        RETURN sessions.first
    ELSE:
        RETURN ""
    END
```
