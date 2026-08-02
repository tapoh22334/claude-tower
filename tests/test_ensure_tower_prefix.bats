#!/usr/bin/env bats
# Unit tests for ensure_tower_prefix() in common.sh
# Security: this function is the final gate before a session_id is trusted
# by callers (session creation, worktree naming, tmux target strings).

load 'test_helper'

setup() {
    source_common
}

# ============================================================================
# ensure_tower_prefix() tests
# ============================================================================

@test "ensure_tower_prefix: adds prefix to plain name" {
    result=$(ensure_tower_prefix "myproject")
    [ "$result" = "tower_myproject" ]
}

@test "ensure_tower_prefix: does not double-prefix an already-prefixed name" {
    result=$(ensure_tower_prefix "tower_myproject")
    [ "$result" = "tower_myproject" ]
}

@test "ensure_tower_prefix: strips shell injection characters before prefixing" {
    result=$(ensure_tower_prefix 'my; rm -rf /')
    [[ "$result" != *";"* ]]
    [[ "$result" != *" "* ]]
}

@test "ensure_tower_prefix: strips path traversal sequences" {
    result=$(ensure_tower_prefix "../../etc/passwd")
    [[ "$result" != *".."* ]]
    [[ "$result" != *"/"* ]]
}

@test "ensure_tower_prefix: fails on empty input" {
    run ensure_tower_prefix ""
    [ "$status" -eq 1 ]
}

@test "ensure_tower_prefix: fails when input sanitizes to empty" {
    run ensure_tower_prefix "!!!@@@###"
    [ "$status" -eq 1 ]
}

@test "ensure_tower_prefix: fails when result exceeds max session id length" {
    local long_name
    long_name=$(printf 'a%.0s' {1..100})
    run ensure_tower_prefix "$long_name"
    [ "$status" -eq 1 ]
}

@test "ensure_tower_prefix: output always matches validate_tower_session_id" {
    result=$(ensure_tower_prefix "Some Mixed_Name-123")
    validate_tower_session_id "$result"
    [ "$?" -eq 0 ]
}

@test "ensure_tower_prefix: rejects command substitution payloads" {
    result=$(ensure_tower_prefix '$(whoami)')
    [[ "$result" != *'$('* ]]
}

@test "ensure_tower_prefix: rejects backtick payloads" {
    result=$(ensure_tower_prefix '`id`')
    [[ "$result" != *'`'* ]]
}
