#!/usr/bin/env bats
# `tower project new` (value/001-tower-session-cli, UC3): directory + git
# init + first session in one command, and nothing touched when it refuses.

load 'test_helper'

T="$PROJECT_ROOT/tmux-plugin/scripts/tower.sh"

setup() {
    source_common
    setup_test_env
    export TOWER_PROJECTS_DIR="$BATS_TEST_TMPDIR/proj"
    mkdir -p "$TOWER_PROJECTS_DIR"
}

teardown() {
    teardown_test_env
}

_sessions() { session_tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -c '^tower_' || true; }

@test "project new: creates the directory, git init, a session there, and prints the id" {
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" project new bar
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^tower_[0-9a-f-]{36}$ ]]
    [ -d "$TOWER_PROJECTS_DIR/bar/.git" ]
    local id="$output"
    session_tmux has-session -t "$id"
    [ "$(session_tmux display-message -p -t "$id" '#{pane_current_path}')" = "$(cd "$TOWER_PROJECTS_DIR/bar" && pwd -P)" ]
    load_metadata "$id"
    [ "$META_LAUNCH_DIR" = "$(cd "$TOWER_PROJECTS_DIR/bar" && pwd -P)" ]
}

@test "project new: --in picks another parent" {
    mkdir -p "$BATS_TEST_TMPDIR/elsewhere"
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" project new baz --in "$BATS_TEST_TMPDIR/elsewhere"
    [ "$status" -eq 0 ]
    [ -d "$BATS_TEST_TMPDIR/elsewhere/baz/.git" ]
    [ ! -e "$TOWER_PROJECTS_DIR/baz" ]
}

@test "project new: --prompt is handed to the first session" {
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" project new bar --prompt "bar の初期設計を始める"
    [ "$status" -eq 0 ]
    [ "$(cat "$TOWER_METADATA_DIR/$output.prompt")" = "bar の初期設計を始める" ]
}

@test "project new: an existing target exits 1 and touches nothing" {
    mkdir -p "$TOWER_PROJECTS_DIR/bar"
    echo keep >"$TOWER_PROJECTS_DIR/bar/file"
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" project new bar
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"lready exists"* ]]
    [ "$(cat "$TOWER_PROJECTS_DIR/bar/file")" = "keep" ]
    [ ! -e "$TOWER_PROJECTS_DIR/bar/.git" ]
    [ "$(_sessions)" -eq 0 ]
}

@test "project new: names with a slash or a leading - or . exit 2 and create nothing" {
    local n
    for n in "../evil" "a/b" "-x" ".hidden"; do
        run --separate-stderr env -u TMUX -u TMUX_PANE "$T" project new "$n"
        [ "$status" -eq 2 ] || { echo "name '$n' gave $status"; false; }
    done
    [ -z "$(ls -A "$TOWER_PROJECTS_DIR")" ]
    [ "$(_sessions)" -eq 0 ]
}

@test "project new: a missing parent exits 1" {
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" project new bar --in "$BATS_TEST_TMPDIR/nowhere"
    [ "$status" -eq 1 ]
}

@test "project new: when git init fails no session is started and the directory is left for inspection" {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    printf '#!/usr/bin/env bash\nexit 1\n' >"$BATS_TEST_TMPDIR/bin/git"
    chmod +x "$BATS_TEST_TMPDIR/bin/git"
    run --separate-stderr env -u TMUX -u TMUX_PANE PATH="$BATS_TEST_TMPDIR/bin:$PATH" "$T" project new bar
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"git init failed"* ]]
    [ -d "$TOWER_PROJECTS_DIR/bar" ]
    [ "$(_sessions)" -eq 0 ]
}

@test "project new: no name exits 2; unknown project subcommand exits 2" {
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" project new
    [ "$status" -eq 2 ]
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" project bogus
    [ "$status" -eq 2 ]
}

@test "project new: completes with stdin closed" {
    run --separate-stderr timeout 20 env -u TMUX -u TMUX_PANE "$T" project new bar </dev/null
    [ "$status" -eq 0 ]
}
