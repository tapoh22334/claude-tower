#!/usr/bin/env bats
# Full UI E2E tests for Navigator/Tile.
#
# Drives the Navigator's list and view panes via real tmux `send-keys`
# and asserts on the pane content captured by `capture-pane`. Covers the
# Phase B scenarios in specs/003-simplify (US1 + US2 + restore + help).
#
# Architecture: each test spawns isolated tmux servers (nav + session) so
# tests don't see each other and don't leak into the user's real tmux.

PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

NAV_SOCKET="ct-uie2e-nav-$$"
SESSION_SOCKET="ct-uie2e-sess-$$"

NAV_LIST_SCRIPT="$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh"
NAV_VIEW_SCRIPT="$PROJECT_ROOT/tmux-plugin/scripts/navigator-view.sh"
TILE_PANE_CONF="$PROJECT_ROOT/tmux-plugin/conf/tile-pane.conf"
SESSION_ADD_SCRIPT="$PROJECT_ROOT/tmux-plugin/scripts/session-add.sh"

# A no-op stand-in for the `claude` binary so session-add/restore don't try
# to launch the real CLI.
STUB_CLAUDE="/bin/true"

setup_file() {
    export TMUX_TMPDIR="/tmp/ct-uie2e-$$"
    mkdir -p "$TMUX_TMPDIR"
    chmod 700 "$TMUX_TMPDIR"
}

teardown_file() {
    TMUX= tmux -L "$NAV_SOCKET" kill-server 2>/dev/null || true
    TMUX= tmux -L "$SESSION_SOCKET" kill-server 2>/dev/null || true
    rm -rf "/tmp/ct-uie2e-$$" 2>/dev/null || true
}

setup() {
    # Fresh isolated state for every test
    export TMUX_TMPDIR="/tmp/ct-uie2e-$$"
    export CLAUDE_TOWER_NAV_SOCKET="$NAV_SOCKET"
    export CLAUDE_TOWER_SESSION_SOCKET="$SESSION_SOCKET"
    export CLAUDE_TOWER_PROGRAM="$STUB_CLAUDE"

    export CLAUDE_TOWER_METADATA_DIR
    CLAUDE_TOWER_METADATA_DIR=$(mktemp -d)

    # Isolated caller CWD state file so `n` prefill is deterministic
    local nav_state_dir="/tmp/ct-uie2e-state-$$"
    rm -rf "$nav_state_dir"
    mkdir -p "$nav_state_dir"
    export CLAUDE_TOWER_CALLER_CWD_FILE="$nav_state_dir/caller-cwd"

    # Point Claude Code's data dir at an empty location so the new-session
    # picker stays empty and `n` falls back to the manual path prompt that
    # these tests were originally written against.
    export CLAUDE_TOWER_CLAUDE_DIR="$nav_state_dir/claude-empty"
    mkdir -p "$CLAUDE_TOWER_CLAUDE_DIR/projects"

    # Ensure no stale sessions on the test sockets
    TMUX= tmux -L "$NAV_SOCKET" kill-server 2>/dev/null || true
    TMUX= tmux -L "$SESSION_SOCKET" kill-server 2>/dev/null || true

    # Force /tmp/claude-tower (the default Navigator state dir) to a known state
    rm -rf /tmp/claude-tower 2>/dev/null || true
    mkdir -p /tmp/claude-tower
}

teardown() {
    TMUX= tmux -L "$NAV_SOCKET" kill-server 2>/dev/null || true
    TMUX= tmux -L "$SESSION_SOCKET" kill-server 2>/dev/null || true
    rm -rf "$CLAUDE_TOWER_METADATA_DIR" 2>/dev/null || true
    rm -rf "/tmp/ct-uie2e-state-$$" 2>/dev/null || true
}

skip_if_no_tmux() {
    if ! command -v tmux &>/dev/null; then
        skip "tmux not available"
    fi
}

# ============================================================================
# Helpers
# ============================================================================

# Make a dormant session: just a metadata file, no tmux session.
make_dormant() {
    local name="$1"
    local dir="${2:-/tmp}"
    cat >"$CLAUDE_TOWER_METADATA_DIR/tower_${name}.meta" <<EOF
session_id=tower_${name}
session_name=${name}
directory_path=${dir}
created_at=$(date -Iseconds)
EOF
}

# Make an active session: tmux session on SESSION_SOCKET + metadata.
make_active() {
    local name="$1"
    local dir="${2:-/tmp}"
    make_dormant "$name" "$dir"
    TMUX= tmux -L "$SESSION_SOCKET" new-session -d -s "tower_${name}" -c "$dir"
}

# Start a Navigator with split panes (list + view) and return when the
# Sessions header is on screen.
#
# Layout: 200x40 outer window. We use a WIDE list pane (140 cols) so prompts
# and confirmation lines don't wrap and break naive grep assertions; the
# view pane gets the remaining 60. Real users see a narrower list but for
# end-to-end content assertions a wide pane is much more reliable.
launch_navigator() {
    TMUX= tmux -L "$NAV_SOCKET" new-session -d -s navigator -x 200 -y 40
    TMUX= tmux -L "$NAV_SOCKET" split-window -h -l "60" -t navigator:0
    TMUX= tmux -L "$NAV_SOCKET" send-keys -t navigator:0.0 \
        "exec $NAV_LIST_SCRIPT" Enter
    TMUX= tmux -L "$NAV_SOCKET" send-keys -t navigator:0.1 \
        "exec $NAV_VIEW_SCRIPT" Enter
    TMUX= tmux -L "$NAV_SOCKET" select-pane -t navigator:0.0
    wait_for_text "navigator:0.0" "Sessions"
}

# Wait until `capture-pane` of $1 contains pattern $2. Returns 0 on hit,
# 1 on timeout. Default timeout = 50 attempts × 0.1s = 5s.
#
# Uses `capture-pane -J` to join wrapped lines so patterns that span the
# pane's right edge are still matchable.
wait_for_text() {
    local target="$1"
    local pattern="$2"
    local max_attempts="${3:-50}"
    local attempt=0
    while ((attempt < max_attempts)); do
        if TMUX= tmux -L "$NAV_SOCKET" capture-pane -t "$target" -J -p 2>/dev/null | \
            grep -qF -- "$pattern"; then
            return 0
        fi
        sleep 0.1
        ((attempt++)) || true
    done
    echo "Timeout waiting for: $pattern"
    echo "--- final pane content ---"
    TMUX= tmux -L "$NAV_SOCKET" capture-pane -t "$target" -J -p 2>/dev/null || true
    return 1
}

# Wait for a file to exist (used to assert session-add side effect).
wait_for_file() {
    local f="$1"
    local max_attempts="${2:-50}"
    local attempt=0
    while ((attempt < max_attempts)); do
        [[ -e "$f" ]] && return 0
        sleep 0.1
        ((attempt++)) || true
    done
    return 1
}

# Wait for a file to be deleted.
wait_for_no_file() {
    local f="$1"
    local max_attempts="${2:-50}"
    local attempt=0
    while ((attempt < max_attempts)); do
        [[ ! -e "$f" ]] && return 0
        sleep 0.1
        ((attempt++)) || true
    done
    return 1
}

# Send keys to the list pane.
nav_send() {
    TMUX= tmux -L "$NAV_SOCKET" send-keys -t navigator:0.0 "$@"
}

# Capture the list pane (joins wrapped lines for stable grep matching).
nav_capture() {
    TMUX= tmux -L "$NAV_SOCKET" capture-pane -t navigator:0.0 -J -p 2>/dev/null
}

# Get the current selected session from Navigator's state file.
nav_selected() {
    cat /tmp/claude-tower/selected 2>/dev/null || echo ""
}

# Check if the navigator tmux session still exists (= Navigator not quit).
nav_alive() {
    TMUX= tmux -L "$NAV_SOCKET" has-session -t navigator 2>/dev/null
}

# Read the focus state file (list or view).
nav_focus() {
    cat /tmp/claude-tower/focus 2>/dev/null || echo ""
}

# ============================================================================
# Startup
# ============================================================================

@test "uie2e: Navigator launches and renders Sessions header" {
    skip_if_no_tmux
    launch_navigator
    nav_capture | grep -q "Sessions"
}

@test "uie2e: Navigator shows (no sessions) when metadata directory is empty" {
    skip_if_no_tmux
    launch_navigator
    wait_for_text "navigator:0.0" "(no sessions)"
}

@test "uie2e: Navigator footer documents the new keybindings (n d 1-9)" {
    skip_if_no_tmux
    launch_navigator
    wait_for_text "navigator:0.0" "n:new"
    nav_capture | grep -q "d:del"
    nav_capture | grep -q "1-9:jump"
}

# ============================================================================
# Navigation: j/k/g/G/1-9
# ============================================================================

@test "uie2e: j moves selection down" {
    skip_if_no_tmux
    make_dormant "uie2e_a"
    make_dormant "uie2e_b"
    make_dormant "uie2e_c"
    launch_navigator
    wait_for_text "navigator:0.0" "uie2e_a"

    # Selection starts unset; first 'j' lands on the first session.
    nav_send "j"
    sleep 0.3
    [[ "$(nav_selected)" == "tower_uie2e_a" || "$(nav_selected)" == "tower_uie2e_b" ]]

    # Second 'j' advances by one
    local before; before="$(nav_selected)"
    nav_send "j"
    sleep 0.3
    [[ "$(nav_selected)" != "$before" ]]
}

@test "uie2e: k moves selection up after going down" {
    skip_if_no_tmux
    make_dormant "uie2e_a"
    make_dormant "uie2e_b"
    launch_navigator
    wait_for_text "navigator:0.0" "uie2e_a"

    nav_send "j" "j"
    sleep 0.3
    local after_down="$(nav_selected)"
    nav_send "k"
    sleep 0.3
    [[ "$(nav_selected)" != "$after_down" ]]
}

@test "uie2e: g jumps to first session" {
    skip_if_no_tmux
    make_dormant "uie2e_a"
    make_dormant "uie2e_b"
    make_dormant "uie2e_c"
    launch_navigator
    wait_for_text "navigator:0.0" "uie2e_a"

    nav_send "G"
    sleep 0.3
    nav_send "g"
    sleep 0.3
    [ "$(nav_selected)" = "tower_uie2e_a" ]
}

@test "uie2e: G jumps to last session" {
    skip_if_no_tmux
    make_dormant "uie2e_a"
    make_dormant "uie2e_b"
    make_dormant "uie2e_c"
    launch_navigator
    wait_for_text "navigator:0.0" "uie2e_a"

    nav_send "G"
    sleep 0.3
    [ "$(nav_selected)" = "tower_uie2e_c" ]
}

@test "uie2e: digit 1 jumps to first session" {
    skip_if_no_tmux
    make_dormant "uie2e_a"
    make_dormant "uie2e_b"
    make_dormant "uie2e_c"
    launch_navigator
    wait_for_text "navigator:0.0" "uie2e_a"

    # Move away first
    nav_send "G"
    sleep 0.3
    nav_send "1"
    sleep 0.3
    [ "$(nav_selected)" = "tower_uie2e_a" ]
}

@test "uie2e: digit 3 jumps to third session" {
    skip_if_no_tmux
    make_dormant "uie2e_a"
    make_dormant "uie2e_b"
    make_dormant "uie2e_c"
    make_dormant "uie2e_d"
    launch_navigator
    wait_for_text "navigator:0.0" "uie2e_a"

    nav_send "3"
    sleep 0.3
    [ "$(nav_selected)" = "tower_uie2e_c" ]
}

@test "uie2e: digit larger than session count is a no-op" {
    skip_if_no_tmux
    make_dormant "uie2e_a"
    make_dormant "uie2e_b"
    launch_navigator
    wait_for_text "navigator:0.0" "uie2e_a"

    nav_send "1"
    sleep 0.3
    [ "$(nav_selected)" = "tower_uie2e_a" ]

    nav_send "7"   # only 2 sessions; should not change selection
    sleep 0.3
    [ "$(nav_selected)" = "tower_uie2e_a" ]
}

# ============================================================================
# Session management: n (new)
# ============================================================================

@test "uie2e: n shows inline prompt prefilled with caller CWD" {
    skip_if_no_tmux
    local caller_dir
    caller_dir=$(mktemp -d)
    echo "$caller_dir" >"$CLAUDE_TOWER_CALLER_CWD_FILE"

    launch_navigator
    wait_for_text "navigator:0.0" "(no sessions)"

    nav_send "n"
    wait_for_text "navigator:0.0" "New session path:"
    # The prompt should also show the caller's CWD as default
    wait_for_text "navigator:0.0" "$caller_dir"

    # Cancel out to avoid creating a session in this test
    nav_send "C-c"
    rm -rf "$caller_dir"
}

@test "uie2e: n + Enter (accept prefill) creates a new session with metadata" {
    skip_if_no_tmux
    local target
    target=$(mktemp -d)
    # Stage the prefilled path AS the target — then the user just confirms
    # with Enter. This is the most common interactive case anyway.
    echo "$target" >"$CLAUDE_TOWER_CALLER_CWD_FILE"

    launch_navigator
    wait_for_text "navigator:0.0" "(no sessions)"

    nav_send "n"
    wait_for_text "navigator:0.0" "New session path:"
    wait_for_text "navigator:0.0" "$target"
    nav_send "Enter"

    # session-add creates a metadata file under our metadata dir
    local meta_glob
    local attempt=0
    while ((attempt < 60)); do
        meta_glob=$(find "$CLAUDE_TOWER_METADATA_DIR" -maxdepth 1 -name "*.meta" 2>/dev/null | head -1)
        [[ -n "$meta_glob" ]] && break
        sleep 0.1
        ((attempt++)) || true
    done
    [ -n "$meta_glob" ]
    grep -qF "directory_path=$target" "$meta_glob"

    rm -rf "$target"
}

@test "uie2e: n with empty input cancels without creating anything" {
    skip_if_no_tmux
    launch_navigator
    wait_for_text "navigator:0.0" "(no sessions)"

    nav_send "n"
    wait_for_text "navigator:0.0" "New session path:"

    # Erase the prefill and submit an empty line
    nav_send "C-u"
    nav_send "Enter"

    # Give it a moment to NOT create anything
    sleep 0.5
    local count
    count=$(find "$CLAUDE_TOWER_METADATA_DIR" -maxdepth 1 -name "*.meta" 2>/dev/null | wc -l)
    [ "$count" -eq 0 ]
}

# ============================================================================
# Session management: d (delete)
# ============================================================================

@test "uie2e: d shows confirmation prompt for selected session" {
    skip_if_no_tmux
    make_dormant "uie2e_del_target"
    launch_navigator
    wait_for_text "navigator:0.0" "uie2e_del_target"

    nav_send "j"   # select the (only) session
    sleep 0.3
    nav_send "d"
    wait_for_text "navigator:0.0" "Delete 'uie2e_del_target'"
    wait_for_text "navigator:0.0" "[y/N]"

    # Cancel
    nav_send "n"
    sleep 0.3
}

@test "uie2e: d + y removes the selected session's metadata" {
    skip_if_no_tmux
    make_dormant "uie2e_del_yes"
    launch_navigator
    wait_for_text "navigator:0.0" "uie2e_del_yes"

    nav_send "j"
    sleep 0.3
    nav_send "d"
    wait_for_text "navigator:0.0" "Delete 'uie2e_del_yes'"
    nav_send "y"

    wait_for_no_file "$CLAUDE_TOWER_METADATA_DIR/tower_uie2e_del_yes.meta"
}

@test "uie2e: d + n cancels the deletion (metadata intact)" {
    skip_if_no_tmux
    make_dormant "uie2e_del_keep"
    launch_navigator
    wait_for_text "navigator:0.0" "uie2e_del_keep"

    nav_send "j"
    sleep 0.3
    nav_send "d"
    wait_for_text "navigator:0.0" "Delete 'uie2e_del_keep'"
    nav_send "n"
    sleep 0.5

    [ -e "$CLAUDE_TOWER_METADATA_DIR/tower_uie2e_del_keep.meta" ]
}

@test "uie2e: d confirmation requires lowercase y (uppercase Y cancels)" {
    skip_if_no_tmux
    make_dormant "uie2e_del_upper"
    launch_navigator
    wait_for_text "navigator:0.0" "uie2e_del_upper"

    nav_send "j"
    sleep 0.3
    nav_send "d"
    wait_for_text "navigator:0.0" "Delete 'uie2e_del_upper'"
    nav_send "Y"   # capital — should NOT delete
    sleep 0.5

    [ -e "$CLAUDE_TOWER_METADATA_DIR/tower_uie2e_del_upper.meta" ]
}

# ============================================================================
# Tile (US2)
# ============================================================================

@test "uie2e: Tab from Navigator switches to Tile view" {
    skip_if_no_tmux
    make_active "uie2e_tile_a"
    launch_navigator
    wait_for_text "navigator:0.0" "uie2e_tile_a"

    nav_send "Tab"
    # switch_to_tile spawns tile.sh in a window on the SESSION server.
    local attempt=0
    while ((attempt < 50)); do
        if TMUX= tmux -L "$SESSION_SOCKET" list-windows 2>/dev/null | grep -q "tower-tile"; then
            return 0
        fi
        sleep 0.1
        ((attempt++)) || true
    done
    return 1
}

# ============================================================================
# Tile View — native tmux split implementation (v3)
# ============================================================================
# Tile View is no longer a self-rendered UI. switch_to_tile orchestrates
# a `tower-tile` window on the session server with one nested-attach
# pane per active tower_* session. The tests below verify the structure
# (the right number of panes, on the right session, with the tile-pane
# config) — visual behaviour (live mirror, scroll, etc.) is tmux's job.

active_window_for() {
    TMUX= tmux -L "$SESSION_SOCKET" display-message -p \
        -t "$1" '#{window_name}' 2>/dev/null
}

@test "uie2e: tile-pane.conf disables prefix in nested-attach panes" {
    [ -f "$TILE_PANE_CONF" ]
    grep -q "set -g prefix None" "$TILE_PANE_CONF"
    grep -q "unbind-key -a" "$TILE_PANE_CONF"
}

@test "uie2e: Tab from Navigator creates a tower-tile window with one pane per active session" {
    skip_if_no_tmux
    make_active "uie2e_tile_a"
    make_active "uie2e_tile_b"
    make_active "uie2e_tile_c"

    launch_navigator
    wait_for_text "navigator:0.0" "uie2e_tile_a"

    nav_send "Tab"

    # Wait for tower-tile window to exist on the alphabetically-first session.
    local attempt=0
    while ((attempt < 50)); do
        if TMUX= tmux -L "$SESSION_SOCKET" has-session \
            -t "tower_uie2e_tile_a:tower-tile" 2>/dev/null; then
            break
        fi
        sleep 0.1
        ((attempt++)) || true
    done

    # One pane per active session (3 in this test).
    local pane_count
    pane_count=$(TMUX= tmux -L "$SESSION_SOCKET" list-panes \
        -t "tower_uie2e_tile_a:tower-tile" 2>/dev/null | wc -l)
    [ "$pane_count" -eq 3 ]

    # Window is not duplicated onto the other sessions.
    ! TMUX= tmux -L "$SESSION_SOCKET" has-session -t "tower_uie2e_tile_b:tower-tile" 2>/dev/null
    ! TMUX= tmux -L "$SESSION_SOCKET" has-session -t "tower_uie2e_tile_c:tower-tile" 2>/dev/null
}

@test "uie2e: Tile panes use tile-pane.conf for nested attach" {
    skip_if_no_tmux
    make_active "uie2e_tileconf_a"
    launch_navigator
    wait_for_text "navigator:0.0" "uie2e_tileconf_a"

    nav_send "Tab"
    local attempt=0
    while ((attempt < 50)); do
        if TMUX= tmux -L "$SESSION_SOCKET" has-session \
            -t "tower_uie2e_tileconf_a:tower-tile" 2>/dev/null; then
            break
        fi
        sleep 0.1
        ((attempt++)) || true
    done

    # The first pane's start command should include `tile-pane.conf`.
    local cmd
    cmd=$(TMUX= tmux -L "$SESSION_SOCKET" list-panes \
        -t "tower_uie2e_tileconf_a:tower-tile" \
        -F '#{pane_start_command}' 2>/dev/null | head -1)
    [[ "$cmd" == *"tile-pane.conf"* ]]
}

@test "uie2e: Tab with no active sessions stays in Navigator (no tile window created)" {
    skip_if_no_tmux
    launch_navigator
    wait_for_text "navigator:0.0" "(no sessions)"

    nav_send "Tab"
    sleep 0.5

    # No tower_* sessions → switch_to_tile bails out, no tower-tile anywhere.
    ! TMUX= tmux -L "$SESSION_SOCKET" list-windows -a 2>/dev/null | grep -q "tower-tile"
}

@test "uie2e: switch_to_tile kills any prior tower-tile before rebuilding" {
    # Regression guard at source level: re-entry into Tile must rebuild
    # the window so the session list is current. The actual rebuild
    # behaviour needs a full client cycle which the harness can't drive,
    # so we assert the kill-window invocation is present in the function.
    local body
    body=$(awk '/^switch_to_tile\(\)/,/^}/' \
        "$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh")
    echo "$body" | grep -q "kill-window"
    echo "$body" | grep -q "tower-tile"
}

# ============================================================================
# Help
# ============================================================================

@test "uie2e: ? shows the help screen with new keys documented" {
    skip_if_no_tmux
    launch_navigator
    wait_for_text "navigator:0.0" "Sessions"
    nav_send "?"
    wait_for_text "navigator:0.0" "Navigator Help"
    wait_for_text "navigator:0.0" "New session"
    wait_for_text "navigator:0.0" "Delete selected"
    wait_for_text "navigator:0.0" "Jump to Nth"
    # Dismiss
    nav_send "Space"
}

@test "uie2e: help screen dismissed by any key returns to list" {
    skip_if_no_tmux
    make_dormant "uie2e_help_back"
    launch_navigator
    wait_for_text "navigator:0.0" "uie2e_help_back"

    nav_send "?"
    wait_for_text "navigator:0.0" "Navigator Help"
    nav_send "x"   # any key dismisses
    wait_for_text "navigator:0.0" "uie2e_help_back"
}

# ============================================================================
# Restore (P1)
# ============================================================================

@test "uie2e: r restores the selected dormant session" {
    skip_if_no_tmux
    make_dormant "uie2e_restore_one" "/tmp"
    launch_navigator
    wait_for_text "navigator:0.0" "uie2e_restore_one"

    nav_send "j"   # select the only session
    sleep 0.3
    nav_send "r"

    # session-restore.sh creates the tmux session on SESSION server.
    local attempt=0
    while ((attempt < 50)); do
        if TMUX= tmux -L "$SESSION_SOCKET" has-session -t "tower_uie2e_restore_one" 2>/dev/null; then
            return 0
        fi
        sleep 0.1
        ((attempt++)) || true
    done
    return 1
}

@test "uie2e: R restores all dormant sessions" {
    skip_if_no_tmux
    make_dormant "uie2e_rall_a" "/tmp"
    make_dormant "uie2e_rall_b" "/tmp"
    launch_navigator
    wait_for_text "navigator:0.0" "uie2e_rall_a"

    nav_send "R"

    local attempt=0
    while ((attempt < 80)); do
        local a b
        TMUX= tmux -L "$SESSION_SOCKET" has-session -t "tower_uie2e_rall_a" 2>/dev/null && a=1 || a=0
        TMUX= tmux -L "$SESSION_SOCKET" has-session -t "tower_uie2e_rall_b" 2>/dev/null && b=1 || b=0
        if [[ "$a" = "1" && "$b" = "1" ]]; then
            return 0
        fi
        sleep 0.1
        ((attempt++)) || true
    done
    return 1
}

@test "uie2e: R with no dormant sessions completes without error" {
    skip_if_no_tmux
    launch_navigator
    wait_for_text "navigator:0.0" "(no sessions)"
    nav_send "R"
    # Just wait a beat and check Navigator still alive
    sleep 0.5
    nav_alive
}

# ============================================================================
# Caller CWD
# ============================================================================

@test "uie2e: caller CWD prefill follows the state file" {
    skip_if_no_tmux
    local caller_dir
    caller_dir=$(mktemp -d)
    echo "$caller_dir" >"$CLAUDE_TOWER_CALLER_CWD_FILE"

    launch_navigator
    wait_for_text "navigator:0.0" "(no sessions)"

    nav_send "n"
    wait_for_text "navigator:0.0" "$caller_dir"

    nav_send "C-c"
    rm -rf "$caller_dir"
}

# ============================================================================
# Quit
# ============================================================================

# ============================================================================
# Additional Phase B scenarios
# ============================================================================

@test "uie2e: Navigator picks up newly-created metadata on next auto-refresh" {
    skip_if_no_tmux
    launch_navigator
    wait_for_text "navigator:0.0" "(no sessions)"

    # Externally create a dormant session: Navigator should discover it on
    # the next REFRESH_INTERVAL tick (~2s).
    make_dormant "uie2e_autorefresh"
    wait_for_text "navigator:0.0" "uie2e_autorefresh" 40
}

@test "uie2e: i shifts focus state to view" {
    skip_if_no_tmux
    make_dormant "uie2e_focus_target"
    launch_navigator
    wait_for_text "navigator:0.0" "uie2e_focus_target"
    nav_send "j"   # select something
    sleep 0.3

    nav_send "i"
    # focus state should flip from "list" to "view"
    local attempt=0
    while ((attempt < 30)); do
        if [[ "$(nav_focus)" == "view" ]]; then
            return 0
        fi
        sleep 0.1
        ((attempt++)) || true
    done
    return 1
}

@test "uie2e: q quits the Navigator (list process exits)" {
    skip_if_no_tmux
    launch_navigator
    wait_for_text "navigator:0.0" "Sessions"

    # `quit_navigator` calls nav_tmux detach-client; in our test harness
    # there is no real client, so the list pane just exits when the script
    # returns. Check that the pane process is gone (the window collapses
    # or the pane shows a non-Navigator marker).
    nav_send "q"

    # After quit, the navigator-list process exits → either the pane dies
    # (window auto-closes) or remains showing a shell. Either way "Sessions"
    # is no longer redrawn. Wait for "Sessions" to NOT be present.
    local attempt=0
    while ((attempt < 30)); do
        if ! TMUX= tmux -L "$NAV_SOCKET" capture-pane -t navigator:0.0 -p 2>/dev/null | grep -q "Sessions"; then
            return 0
        fi
        sleep 0.1
        ((attempt++)) || true
    done
    return 1
}
