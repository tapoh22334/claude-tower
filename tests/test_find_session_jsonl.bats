#!/usr/bin/env bats
# test_find_session_jsonl.bats
#
# find_session_jsonl must resolve to the CANONICAL transcript when the same
# sessionId exists under more than one project-slug dir. Picking by raw glob
# order grouped a session under the wrong directory header (the reported
# "shown under claude-aquarium but really c5017f" bug). The canonical
# transcript is the one whose slug matches its own recorded launch cwd.

load 'test_helper'

setup() {
    source_common
    setup_test_env
    export CLAUDE_PROJECTS_DIR="$BATS_TEST_TMPDIR/projects"
    mkdir -p "$CLAUDE_PROJECTS_DIR"
    # shellcheck disable=SC1090
    source "$PROJECT_ROOT/tmux-plugin/lib/claude-sessions.sh"
}

teardown() {
    teardown_test_env
}

_make_transcript() {
    # $1 slug dir, $2 sessionId, $3 recorded cwd
    local d="$CLAUDE_PROJECTS_DIR/$1"
    mkdir -p "$d"
    printf '{"cwd":"%s","type":"user"}\n' "$3" >"$d/$2.jsonl"
}

@test "find_session_jsonl: single transcript returns as-is" {
    _make_transcript "-home-dev-working-c5017f" "aaaaaaaa-0000-0000-0000-000000000000" "/home/dev/working/c5017f"
    run find_session_jsonl "aaaaaaaa-0000-0000-0000-000000000000"
    [ "$status" -eq 0 ]
    [[ "$output" == *"-home-dev-working-c5017f/"* ]]
}

@test "find_session_jsonl: multi-slug picks the slug matching its own cwd" {
    local sid="bbbbbbbb-0000-0000-0000-000000000000"
    # A stray copy under the aquarium slug whose recorded cwd is actually c5017f...
    _make_transcript "-home-dev-working-claude-aquarium" "$sid" "/home/dev/working/c5017f"
    # ...and the canonical transcript under the c5017f slug (slug == cwd).
    _make_transcript "-home-dev-working-c5017f" "$sid" "/home/dev/working/c5017f"
    run find_session_jsonl "$sid"
    [ "$status" -eq 0 ]
    [[ "$output" == *"-home-dev-working-c5017f/"* ]]
    [[ "$output" != *"-claude-aquarium/"* ]]
}

@test "find_session_jsonl: falls back to newest when no slug matches its cwd" {
    local sid="cccccccc-0000-0000-0000-000000000000"
    # Neither slug matches the recorded cwd (both worktree-style); newest wins.
    # stat mtime is whole-second granularity, so set the times explicitly
    # rather than racing a sub-second sleep.
    _make_transcript "-home-dev-slugA" "$sid" "/home/dev/working/real"
    _make_transcript "-home-dev-slugB" "$sid" "/home/dev/working/real"
    touch -d '2020-01-01 00:00:00' "$CLAUDE_PROJECTS_DIR/-home-dev-slugA/$sid.jsonl"
    touch -d '2020-01-01 00:01:00' "$CLAUDE_PROJECTS_DIR/-home-dev-slugB/$sid.jsonl"
    run find_session_jsonl "$sid"
    [ "$status" -eq 0 ]
    [[ "$output" == *"-home-dev-slugB/"* ]]   # slugB is newer
}

@test "find_session_jsonl: returns nonzero when no transcript exists" {
    run find_session_jsonl "dddddddd-0000-0000-0000-000000000000"
    [ "$status" -ne 0 ]
}
