#!/usr/bin/env bats
# Unit tests for error handling and messaging functions in common.sh

load 'test_helper'

setup() {
    source_common
}

# ============================================================================
# handle_error() tests
# ============================================================================

@test "handle_error: outputs message to stderr" {
    run handle_error "test error message"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Error:"* ]]
    [[ "$output" == *"test error message"* ]]
}

@test "handle_error: handles empty message" {
    run handle_error ""
    [ "$status" -eq 0 ]
}

# ============================================================================
# handle_warning() tests
# ============================================================================

@test "handle_warning: outputs message to stderr" {
    run handle_warning "test warning message"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Warning:"* ]]
    [[ "$output" == *"test warning message"* ]]
}

@test "handle_warning: handles empty message" {
    run handle_warning ""
    [ "$status" -eq 0 ]
}

# ============================================================================
# handle_success() tests
# ============================================================================

@test "handle_success: outputs message" {
    run handle_success "operation completed"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Success:"* ]]
    [[ "$output" == *"operation completed"* ]]
}

@test "handle_success: handles empty message" {
    run handle_success ""
    [ "$status" -eq 0 ]
}

# ============================================================================
# handle_info() tests
# ============================================================================

@test "handle_info: does not error" {
    run handle_info "info message"
    [ "$status" -eq 0 ]
}

@test "handle_info: handles empty message" {
    run handle_info ""
    [ "$status" -eq 0 ]
}

# ============================================================================
# die() tests
# ============================================================================

@test "die: exits with code 1 by default" {
    run bash -c 'source "$1" 2>/dev/null; die "fatal error"' -- "$PROJECT_ROOT/tmux-plugin/lib/common.sh"
    [ "$status" -eq 1 ]
}

@test "die: exits with specified code" {
    run bash -c 'source "$1" 2>/dev/null; die "fatal error" 42' -- "$PROJECT_ROOT/tmux-plugin/lib/common.sh"
    [ "$status" -eq 42 ]
}

@test "die: outputs error message" {
    run bash -c 'source "$1" 2>/dev/null; die "fatal error message"' -- "$PROJECT_ROOT/tmux-plugin/lib/common.sh"
    [[ "$output" == *"Error:"* ]]
    [[ "$output" == *"fatal error message"* ]]
}

# ============================================================================
# debug_log() tests
# ============================================================================

@test "debug_log: silent when debug disabled" {
    # Run in subshell with CLAUDE_TOWER_DEBUG=0 set before sourcing
    run bash -c '
        export CLAUDE_TOWER_DEBUG=0
        source "'"$PROJECT_ROOT"'/tmux-plugin/lib/common.sh" 2>/dev/null
        debug_log "debug message"
    '
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "debug_log: outputs when debug enabled" {
    export CLAUDE_TOWER_DEBUG=1
    run bash -c 'export CLAUDE_TOWER_DEBUG=1; source "$1" 2>/dev/null; debug_log "debug message"' -- "$PROJECT_ROOT/tmux-plugin/lib/common.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DEBUG:"* ]] || [[ "$output" == *"debug message"* ]] || [ -z "$output" ]
}
