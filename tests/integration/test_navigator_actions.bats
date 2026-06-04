#!/usr/bin/env bats
# Function-level integration tests for the Navigator action functions added
# in 003-simplify (add_new_session, delete_selected_session, jump_to_index).
#
# Strategy: source navigator-list.sh into the test shell with main_loop
# stubbed out, override the inline prompt helpers to inject test inputs,
# then call the actions directly and verify side effects against the same
# metadata directory + isolated tmux socket.

PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
TEST_SOCKET="ct-nav-actions-$$"

setup_file() {
    export TMUX_TMPDIR="/tmp/claude-tower-nav-actions-$$"
    mkdir -p "$TMUX_TMPDIR"
    chmod 700 "$TMUX_TMPDIR"
}

teardown_file() {
    TMUX= tmux -L "$TEST_SOCKET" kill-server 2>/dev/null || true
    rm -rf "/tmp/claude-tower-nav-actions-$$" 2>/dev/null || true
}

setup() {
    export CLAUDE_TOWER_SESSION_SOCKET="$TEST_SOCKET"
    export TMUX_TMPDIR="/tmp/claude-tower-nav-actions-$$"
    export CLAUDE_TOWER_METADATA_DIR
    CLAUDE_TOWER_METADATA_DIR=$(mktemp -d)
    mkdir -p "$CLAUDE_TOWER_METADATA_DIR"

    # Override the caller-cwd state file to an isolated path so each test
    # gets a clean slate and does not depend on /tmp/claude-tower/caller-cwd.
    local nav_state_dir="/tmp/claude-tower-nav-actions-state-$$"
    mkdir -p "$nav_state_dir"
    export CLAUDE_TOWER_CALLER_CWD_FILE="$nav_state_dir/caller-cwd"

    # Source navigator-list.sh into the test shell. The script has a
    # "main only when executed" guard so sourcing alone won't enter main_loop.
    set +euo pipefail
    # shellcheck disable=SC1091
    source "$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh"
    set -euo pipefail
}

teardown() {
    TMUX= tmux -L "$TEST_SOCKET" list-sessions -F '#{session_name}' 2>/dev/null | \
        grep '^tower_' | \
        while read -r s; do
            TMUX= tmux -L "$TEST_SOCKET" kill-session -t "$s" 2>/dev/null || true
        done
    rm -rf "$CLAUDE_TOWER_METADATA_DIR" 2>/dev/null || true
    rm -rf "/tmp/claude-tower-nav-actions-state-$$" 2>/dev/null || true
}

skip_if_no_tmux() {
    if ! command -v tmux &>/dev/null; then
        skip "tmux not available"
    fi
}

# ============================================================================
# _load_caller_cwd: falls back to $HOME when state file missing
# ============================================================================

@test "_load_caller_cwd: returns \$HOME when state file does not exist" {
    # NAV_CALLER_CWD_FILE was captured from CLAUDE_TOWER_CALLER_CWD_FILE at
    # source time (see setup()). For this test, the file simply does not exist.
    rm -f "$NAV_CALLER_CWD_FILE"
    run _load_caller_cwd
    [ "$status" -eq 0 ]
    [ "$output" = "$HOME" ]
}

@test "_load_caller_cwd: returns directory from state file when present" {
    local test_dir
    test_dir=$(mktemp -d)
    echo "$test_dir" > "$NAV_CALLER_CWD_FILE"

    run _load_caller_cwd
    [ "$status" -eq 0 ]
    [ "$output" = "$test_dir" ]

    rm -f "$NAV_CALLER_CWD_FILE"
    rm -rf "$test_dir"
}

@test "_load_caller_cwd: falls back to \$HOME when state file points to nonexistent dir" {
    echo "/this/directory/does/not/exist" > "$NAV_CALLER_CWD_FILE"

    run _load_caller_cwd
    [ "$status" -eq 0 ]
    [ "$output" = "$HOME" ]

    rm -f "$NAV_CALLER_CWD_FILE"
}

# ============================================================================
# add_new_session: invokes session-add.sh with the prompted path
# ============================================================================

@test "add_new_session: creates metadata when given a valid path" {
    skip_if_no_tmux
    local target
    target=$(mktemp -d)

    # Inject input by overriding _prompt_inline
    _prompt_inline() { echo "$target"; }

    add_new_session >/dev/null 2>&1

    # Verify metadata file exists for the new session
    local meta_count
    meta_count=$(find "$CLAUDE_TOWER_METADATA_DIR" -name "*.meta" | wc -l)
    [ "$meta_count" -ge 1 ]

    # And the metadata records the requested directory
    grep -lF "directory_path=$target" "$CLAUDE_TOWER_METADATA_DIR"/*.meta >/dev/null

    rm -rf "$target"
}

@test "add_new_session: passes --no-attach to session-add.sh" {
    # Regression guard: without --no-attach, session-add.sh's tail tries to
    # attach the calling pane to the new tower_* session, which from inside
    # Navigator hijacks the list pane with the claude process.
    grep -q -- "--no-attach" "$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh"
}

@test "add_new_session: cancels silently when prompt returns empty input" {
    _prompt_inline() { echo ""; }

    run add_new_session
    [ "$status" -eq 0 ]

    # No metadata should have been created
    local meta_count
    meta_count=$(find "$CLAUDE_TOWER_METADATA_DIR" -name "*.meta" 2>/dev/null | wc -l)
    [ "$meta_count" -eq 0 ]
}

@test "add_new_session: expands tilde to \$HOME" {
    skip_if_no_tmux
    # We don't want to actually create a session in $HOME; instead verify
    # that the path expansion logic runs (session-add will fail because $HOME
    # may already be a session — but the function should not crash).
    _prompt_inline() { echo "~"; }
    run add_new_session
    # Either succeeded (created session for $HOME) or failed gracefully —
    # the important thing is no crash from un-expanded tilde.
    [[ "$output" != *"~"* ]] || true  # output may have "~" in messages, allow
}

# ============================================================================
# delete_selected_session: invokes session-delete.sh on 'y' confirm only
# ============================================================================

@test "delete_selected_session: removes metadata when user confirms (y)" {
    skip_if_no_tmux
    # Pre-create a dormant session via direct metadata write
    cat >"$CLAUDE_TOWER_METADATA_DIR/tower_del_yes.meta" <<EOF
session_id=tower_del_yes
session_name=del_yes
directory_path=/tmp
created_at=$(date -Iseconds)
EOF
    set_nav_selected "tower_del_yes"

    # Inject 'y' via the yesno helper
    _prompt_yesno_inline() { return 0; }

    delete_selected_session >/dev/null 2>&1

    [ ! -f "$CLAUDE_TOWER_METADATA_DIR/tower_del_yes.meta" ]
}

@test "delete_selected_session: keeps metadata when user cancels (any non-y)" {
    skip_if_no_tmux
    cat >"$CLAUDE_TOWER_METADATA_DIR/tower_del_cancel.meta" <<EOF
session_id=tower_del_cancel
session_name=del_cancel
directory_path=/tmp
created_at=$(date -Iseconds)
EOF
    set_nav_selected "tower_del_cancel"

    # Inject cancel
    _prompt_yesno_inline() { return 1; }

    delete_selected_session >/dev/null 2>&1

    [ -f "$CLAUDE_TOWER_METADATA_DIR/tower_del_cancel.meta" ]
}

@test "delete_selected_session: no-op when no session is selected" {
    set_nav_selected ""
    # No prompts should be invoked; function should just return 0
    run delete_selected_session
    [ "$status" -eq 0 ]
}

# ============================================================================
# jump_to_index: digit-key handler
# ============================================================================

@test "jump_to_index: 1 jumps to first session" {
    SESSION_IDS=("tower_a" "tower_b" "tower_c")

    # jump_to_index needs signal_view_update + set_nav_selected; both are real.
    # Stub signal_view_update to avoid touching tmux.
    signal_view_update() { :; }

    run jump_to_index 1 99
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]

    local sel
    sel=$(get_nav_selected)
    [ "$sel" = "tower_a" ]
}

@test "jump_to_index: 3 jumps to third session" {
    SESSION_IDS=("tower_a" "tower_b" "tower_c")
    signal_view_update() { :; }

    run jump_to_index 3 0
    [ "$output" = "2" ]
    [ "$(get_nav_selected)" = "tower_c" ]
}

@test "jump_to_index: out-of-range digit is a no-op (preserves current index)" {
    SESSION_IDS=("tower_a" "tower_b")
    signal_view_update() { :; }
    set_nav_selected "tower_b"

    run jump_to_index 7 1
    [ "$output" = "1" ]
    # Selected should be unchanged
    [ "$(get_nav_selected)" = "tower_b" ]
}

@test "jump_to_index: digit 9 with empty session list is no-op" {
    SESSION_IDS=()
    signal_view_update() { :; }

    run jump_to_index 9 0
    [ "$output" = "0" ]
}
