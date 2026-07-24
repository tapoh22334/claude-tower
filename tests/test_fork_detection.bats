#!/usr/bin/env bats
# Unit tests for fork detection (claude-sessions.sh)

load 'test_helper'

PARENT="cccccccc-1111-4111-8111-111111111111"
FORK="dddddddd-2222-4222-8222-222222222222"
SOLO="eeeeeeee-3333-4333-8333-333333333333"

setup() {
    source_common
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "find_fork_parent: returns parent sessionId for a fork" {
    create_fork_pair_jsonl "-home-user-proj" "$PARENT" "$FORK" "/home/user/proj" >/dev/null
    run find_fork_parent "$FORK"
    [ "$status" -eq 0 ]
    [ "$output" = "$PARENT" ]
}
