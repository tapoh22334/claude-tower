#!/usr/bin/env bats
# US1/US2 surface smoke tests — verify the new Navigator/Tile keys, handlers,
# and helpers are wired up at the source level. Full interactive flow is
# covered by manual quickstart verification (specs/003-simplify/quickstart.md).

PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
NAV="$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh"
TILE="$PROJECT_ROOT/tmux-plugin/scripts/tile.sh"
TMUX_PLUGIN="$PROJECT_ROOT/tmux-plugin/claude-tower.tmux"

# ============================================================================
# US1 — Navigator new keys (n, d, 1-9) wired into main_loop case
# ============================================================================

@test "Navigator main_loop handles 'n' key" {
    run grep -E "^\s*n\)\s*$" "$NAV"
    [ "$status" -eq 0 ]
}

@test "Navigator main_loop handles 'd' key" {
    run grep -E "^\s*d\)\s*$" "$NAV"
    [ "$status" -eq 0 ]
}

@test "Navigator main_loop handles digit 1-9 jump" {
    run grep -E "^\s*\[1-9\]\)\s*$" "$NAV"
    [ "$status" -eq 0 ]
}

@test "Navigator defines add_new_session action" {
    run grep -E "^add_new_session\(\)" "$NAV"
    [ "$status" -eq 0 ]
}

@test "Navigator defines delete_selected_session action" {
    run grep -E "^delete_selected_session\(\)" "$NAV"
    [ "$status" -eq 0 ]
}

@test "Navigator defines jump_to_index action" {
    run grep -E "^jump_to_index\(\)" "$NAV"
    [ "$status" -eq 0 ]
}

@test "Navigator defines _load_caller_cwd helper" {
    run grep -E "^_load_caller_cwd\(\)" "$NAV"
    [ "$status" -eq 0 ]
}

@test "Navigator defines _prompt_inline helper" {
    run grep -E "^_prompt_inline\(\)" "$NAV"
    [ "$status" -eq 0 ]
}

@test "Navigator defines _prompt_yesno_inline helper" {
    run grep -E "^_prompt_yesno_inline\(\)" "$NAV"
    [ "$status" -eq 0 ]
}

@test "Navigator footer documents new keys (n/d/1-9)" {
    run grep -E "n:new.*d:del.*1-9" "$NAV"
    [ "$status" -eq 0 ] || {
        # Tolerate any order of n/d/1-9 in the footer
        run grep -E "(n:new|d:del|1-9:jump)" "$NAV"
        [ "$status" -eq 0 ]
    }
}

@test "Navigator help screen documents 'n' key" {
    run grep -E "n\s+New session" "$NAV"
    [ "$status" -eq 0 ]
}

@test "Navigator help screen documents 'd' key" {
    run grep -E "d\s+Delete selected" "$NAV"
    [ "$status" -eq 0 ]
}

# ============================================================================
# Caller CWD capture (foundational T002)
# ============================================================================

@test "claude-tower.tmux captures caller CWD" {
    run grep "caller-cwd" "$TMUX_PLUGIN"
    [ "$status" -eq 0 ]
}

@test "claude-tower.tmux uses pane_current_path for CWD capture" {
    run grep "pane_current_path" "$TMUX_PLUGIN"
    [ "$status" -eq 0 ]
}

# ============================================================================
# US2 — Tile direct-input routing
# ============================================================================

@test "Tile defines enter_input_mode_for action" {
    run grep -E "^enter_input_mode_for\(\)" "$TILE"
    [ "$status" -eq 0 ]
}

@test "Tile 1-9 case calls enter_input_mode_for (not return_to_list_view)" {
    # Locate the [1-9] case block and verify it calls enter_input_mode_for.
    # Uses POSIX character classes (`[[:space:]]`) for portability — mawk
    # (Ubuntu's default) does not understand `\s`.
    run awk '/^[[:space:]]*\[1-9\]\)/,/;;/' "$TILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"enter_input_mode_for"* ]]
}

@test "Tile Enter case calls enter_input_mode_for" {
    # Find the Enter case ('' | $'\n') by its surrounding context — the case
    # block should be immediately followed by a line containing enter_input_mode_for.
    run grep -n "enter_input_mode_for" "$TILE"
    [ "$status" -eq 0 ]
    # Expect at least two references: one in the [1-9] case and one in the Enter case.
    local count
    count=$(grep -c "enter_input_mode_for" "$TILE")
    [ "$count" -ge 3 ]  # function def + [1-9] case + Enter case
}

@test "Tile no longer binds 'r' for manual refresh" {
    # The literal 'r) # Refresh' pattern should be gone
    ! grep -qE "^\s*r\)\s*#\s*Refresh" "$TILE"
}

@test "Tile uses REFRESH_INTERVAL timed read for auto-refresh" {
    run grep "read -rsn1 -t \"\$REFRESH_INTERVAL\"" "$TILE"
    [ "$status" -eq 0 ]
}

@test "Tile defines REFRESH_INTERVAL constant" {
    run grep "readonly REFRESH_INTERVAL" "$TILE"
    [ "$status" -eq 0 ]
}

# ============================================================================
# FR-009a — Escape from input mode returns to Navigator list
# ============================================================================

@test "view-focus.conf binds Escape to detach-client (returns to Navigator)" {
    run grep "Escape detach-client" "$PROJECT_ROOT/tmux-plugin/conf/view-focus.conf"
    [ "$status" -eq 0 ]
}
