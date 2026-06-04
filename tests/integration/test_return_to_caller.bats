#!/usr/bin/env bats
# Tests for the tmux-side "return to caller" feature:
#   - install_return_binding registers prefix+<TOWER_PREFIX> on the target
#     tmux server with the right command (detach-client -E …return-script).
#   - return-to-caller.sh dispatches correctly based on the caller file.

PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
NAV_SOCKET="ct-ret-nav-$$"
SESS_SOCKET="ct-ret-sess-$$"
DEFAULT_SOCKET="ct-ret-def-$$"

setup_file() {
    export TMUX_TMPDIR="/tmp/claude-tower-ret-test-$$"
    mkdir -p "$TMUX_TMPDIR"
    chmod 700 "$TMUX_TMPDIR"
}

teardown_file() {
    for sock in "$NAV_SOCKET" "$SESS_SOCKET" "$DEFAULT_SOCKET"; do
        TMUX= tmux -L "$sock" kill-server 2>/dev/null || true
    done
    rm -rf "$TMUX_TMPDIR" 2>/dev/null || true
}

setup() {
    export TMUX_TMPDIR="/tmp/claude-tower-ret-test-$$"
    export CLAUDE_TOWER_NAV_SOCKET="$NAV_SOCKET"
    export CLAUDE_TOWER_SESSION_SOCKET="$SESS_SOCKET"
    export CLAUDE_TOWER_PREFIX="t"

    # Isolated caller-file location so each test runs against a fresh state.
    CALLER_DIR=$(mktemp -d)
    export CLAUDE_TOWER_CALLER_FILE="$CALLER_DIR/caller"

    # Need an empty Navigator server before binding
    TMUX= tmux -L "$NAV_SOCKET" new-session -d -s scratch 2>/dev/null || true

    # Source common.sh to get install_return_binding
    set +euo pipefail
    # shellcheck disable=SC1091
    source "$PROJECT_ROOT/tmux-plugin/lib/common.sh"
    set -euo pipefail

    # common.sh installs an ERR trap that calls _log_to_file. Under bats,
    # a failing assertion (grep -q returning 1) would trip it and the trap
    # then recurses through ensure_log_dir → trap fires again → infinite
    # spiral that looks like a hang. Bats needs clean ERR handling.
    trap - ERR
}

teardown() {
    for sock in "$NAV_SOCKET" "$SESS_SOCKET" "$DEFAULT_SOCKET"; do
        TMUX= tmux -L "$sock" kill-server 2>/dev/null || true
    done
    rm -rf "$CALLER_DIR" 2>/dev/null || true
}

skip_if_no_tmux() {
    command -v tmux &>/dev/null || skip "tmux not available"
}

# ============================================================================
# install_return_binding
# ============================================================================

@test "install_return_binding: registers prefix+t on the given server" {
    skip_if_no_tmux
    install_return_binding "$NAV_SOCKET"

    local keys
    keys=$(TMUX= tmux -L "$NAV_SOCKET" list-keys -T prefix)
    # The binding row contains both the key (t) and the command
    # (detach-client + return-to-caller.sh path).
    echo "$keys" | grep -E "^bind-key +-T prefix +t " | grep -q "detach-client"
    echo "$keys" | grep -E "^bind-key +-T prefix +t " | grep -q "return-to-caller.sh"
}

@test "install_return_binding: respects CLAUDE_TOWER_PREFIX override" {
    skip_if_no_tmux
    CLAUDE_TOWER_PREFIX="Z" install_return_binding "$NAV_SOCKET"

    local keys
    keys=$(TMUX= tmux -L "$NAV_SOCKET" list-keys -T prefix)
    echo "$keys" | grep -E "^bind-key +-T prefix +Z " | grep -q "return-to-caller.sh"
}

@test "install_return_binding: works on the Session server too" {
    skip_if_no_tmux
    TMUX= tmux -L "$SESS_SOCKET" new-session -d -s scratch
    install_return_binding "$SESS_SOCKET"

    local keys
    keys=$(TMUX= tmux -L "$SESS_SOCKET" list-keys -T prefix)
    echo "$keys" | grep -E "^bind-key +-T prefix +t " | grep -q "return-to-caller.sh"
}

@test "install_return_binding: silently tolerates a missing server" {
    skip_if_no_tmux
    local dead_socket="ct-ret-dead-$$"
    # Server does not exist — bind-key should fail, but the helper swallows it.
    run install_return_binding "$dead_socket"
    [ "$status" -eq 0 ]
}

# ============================================================================
# return-to-caller.sh
# ============================================================================

# NB: end-to-end attach behaviour is not unit-tested here because
# `tmux attach-session` requires a controlling terminal and would hang
# in a non-interactive test runner. The actual recovery path is exercised
# manually via quickstart.md. Below we verify the script's source-level
# logic instead.

@test "return-to-caller.sh: prefers the recorded caller session over fallbacks" {
    # Read the script and assert it tries the caller before listing sessions.
    local script="$PROJECT_ROOT/tmux-plugin/scripts/return-to-caller.sh"
    [ -x "$script" ]
    # The caller check (`has-session -t "$caller"`) must appear earlier than
    # the fallback (`list-sessions`).
    local caller_line list_line
    caller_line=$(grep -n "has-session -t" "$script" | head -1 | cut -d: -f1)
    list_line=$(grep -n "list-sessions" "$script" | head -1 | cut -d: -f1)
    [ -n "$caller_line" ]
    [ -n "$list_line" ]
    [ "$caller_line" -lt "$list_line" ]
}

@test "return-to-caller.sh: respects CLAUDE_TOWER_CALLER_FILE override" {
    local script="$PROJECT_ROOT/tmux-plugin/scripts/return-to-caller.sh"
    grep -q 'CLAUDE_TOWER_CALLER_FILE:-' "$script"
}

@test "return-to-caller.sh: drops to the shell when no caller and no fallback" {
    skip_if_no_tmux
    # No caller file, no default-server sessions.
    rm -f "$CLAUDE_TOWER_CALLER_FILE"

    local stub_dir
    stub_dir=$(mktemp -d)
    cat >"$stub_dir/tmux" <<EOF
#!/usr/bin/env bash
echo "tmux \$*" >>"$stub_dir/calls.log"
# Pretend there are no sessions anywhere.
if [[ "\$1" == "has-session" ]]; then exit 1; fi
if [[ "\$1" == "list-sessions" ]]; then exit 0; fi
exit 0
EOF
    chmod +x "$stub_dir/tmux"

    cat >"$stub_dir/shell-marker" <<EOF
#!/usr/bin/env bash
echo "SHELL_INVOKED" >"$stub_dir/shell.out"
EOF
    chmod +x "$stub_dir/shell-marker"

    PATH="$stub_dir:$PATH" \
        CLAUDE_TOWER_CALLER_FILE="$CLAUDE_TOWER_CALLER_FILE" \
        SHELL="$stub_dir/shell-marker" \
        "$PROJECT_ROOT/tmux-plugin/scripts/return-to-caller.sh" </dev/null >/dev/null 2>&1 || true

    [ -f "$stub_dir/shell.out" ]
    grep -q "SHELL_INVOKED" "$stub_dir/shell.out"

    rm -rf "$stub_dir"
}
