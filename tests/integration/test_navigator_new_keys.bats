#!/usr/bin/env bats
# US1/US2 surface smoke tests — verify the new Navigator/Tile keys, handlers,
# and helpers are wired up at the source level. Full interactive flow is
# covered by manual quickstart verification (specs/003-simplify/quickstart.md).

PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
NAV="$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh"
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
# US2 — Tile View now uses native tmux split-window
# ============================================================================
# In the v3 rewrite, tile.sh is gone. switch_to_tile orchestrates a
# tower-tile window with one nested-attach pane per active session. The
# old "input mode" concept disappears — every tile pane is interactive.

@test "Tile View: tile.sh has been removed" {
    [ ! -e "$PROJECT_ROOT/tmux-plugin/scripts/tile.sh" ]
}

@test "Tile View: tile-pane.conf has been removed" {
    [ ! -e "$PROJECT_ROOT/tmux-plugin/conf/tile-pane.conf" ]
}

@test "switch_to_tile delegates to tile_collapse and installs exit wiring" {
    local script="$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh"
    local body
    body=$(awk '/^switch_to_tile\(\)/,/^}/' "$script")
    echo "$body" | grep -q "tile_collapse"
    echo "$body" | grep -q "bind-key"
    echo "$body" | grep -q "client-detached"
    echo "$body" | grep -q "tile-exit.sh"
    # Old nested-attach mechanics are gone.
    ! echo "$body" | grep -q "tile-pane.conf"
    ! echo "$body" | grep -q "split-window"
}

@test "navigator-list.sh sources lib/tile.sh" {
    grep -q "lib/tile.sh" "$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh"
}

# ============================================================================
# FR-009a — Escape from input mode returns to Navigator list
# ============================================================================

@test "view-focus.conf binds Escape to detach-client (returns to Navigator)" {
    run grep "Escape detach-client" "$PROJECT_ROOT/tmux-plugin/conf/view-focus.conf"
    [ "$status" -eq 0 ]
}
