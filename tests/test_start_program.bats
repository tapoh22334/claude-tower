#!/usr/bin/env bats
# The pane Tower creates inherits the PATH of whoever ran new-session. From an
# ssh login shell without ~/.local/bin, `claude` typed into that pane is
# "command not found" — only when opened through Tower (#50). Tower must not
# leave the lookup to the pane's shell.

load 'test_helper'

setup() {
    setup_test_env
    export FAKE_HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$FAKE_HOME/.local/bin" "$BATS_TEST_TMPDIR/work"
    printf '#!/usr/bin/env bash\n' >"$FAKE_HOME/.local/bin/claude"
    chmod +x "$FAKE_HOME/.local/bin/claude"
}

teardown() {
    teardown_test_env
}

# Run start_claude_session with tmux stubbed; print every session_tmux call.
_run_start() {
    local path="$1" home="$2"
    run env PATH="$path" HOME="$home" CLAUDE_TOWER_PROGRAM=claude bash -c '
        source "'"$PROJECT_ROOT"'/tmux-plugin/lib/common.sh"
        set +e
        session_tmux() { case "$1" in has-session) return 1 ;; *) echo "tmux $*" ;; esac; }
        _wait_for_shell_ready() { :; }
        handle_error() { echo "ERROR: $*"; }
        handle_success() { :; }
        start_claude_session tower_11111111-1111-4111-8111-111111111111 "'"$BATS_TEST_TMPDIR"'/work" new
        echo "rc=$?"
    '
}

@test "start: with claude absent from PATH, the pane is told the absolute ~/.local/bin path" {
    _run_start "/usr/bin:/bin" "$FAKE_HOME"
    [[ "$output" == *"send-keys -t tower_11111111-1111-4111-8111-111111111111 $FAKE_HOME/.local/bin/claude --session-id"* ]]
    [[ "$output" == *"rc=0"* ]]
}

@test "start: with claude on PATH, the resolved absolute path is used" {
    local onpath="$BATS_TEST_TMPDIR/onpath"
    mkdir -p "$onpath"; printf '#!/usr/bin/env bash\n' >"$onpath/claude"; chmod +x "$onpath/claude"
    _run_start "$onpath:/usr/bin:/bin" "$BATS_TEST_TMPDIR/nohome"
    [[ "$output" == *"send-keys -t tower_11111111-1111-4111-8111-111111111111 $onpath/claude --session-id"* ]]
}

@test "start: when claude is nowhere, fail before creating the session" {
    _run_start "/usr/bin:/bin" "$BATS_TEST_TMPDIR/nohome"
    [[ "$output" == *"ERROR:"* ]]
    [[ "$output" != *"new-session"* ]]
    [[ "$output" == *"rc=1"* ]]
}

@test "start: the pane's PATH gets ~/.local/bin so a hand-typed claude works too" {
    _run_start "/usr/bin:/bin" "$FAKE_HOME"
    [[ "$output" == *"new-session"*"-e PATH=$FAKE_HOME/.local/bin:/usr/bin:/bin"* ]]
}

@test "start: an already-absolute CLAUDE_TOWER_PROGRAM is passed through unchanged" {
    run env PATH="/usr/bin:/bin" HOME="$FAKE_HOME" CLAUDE_TOWER_PROGRAM="/opt/x/claude --verbose" bash -c '
        source "'"$PROJECT_ROOT"'/tmux-plugin/lib/common.sh"
        set +e
        session_tmux() { case "$1" in has-session) return 1 ;; *) echo "tmux $*" ;; esac; }
        _wait_for_shell_ready() { :; }
        handle_error() { echo "ERROR: $*"; }
        handle_success() { :; }
        start_claude_session tower_11111111-1111-4111-8111-111111111111 "'"$BATS_TEST_TMPDIR"'/work" resume
    '
    [[ "$output" == *"send-keys -t tower_11111111-1111-4111-8111-111111111111 /opt/x/claude --verbose --resume"* ]]
}
