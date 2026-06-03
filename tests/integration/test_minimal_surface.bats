#!/usr/bin/env bats
# Surface assertion: verify deleted scripts are absent and only the
# 003-simplify keeper set remains. See specs/003-simplify/contracts/tower-cli.md.

PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
SCRIPTS_DIR="$PROJECT_ROOT/tmux-plugin/scripts"

@test "Sidebar feature removed: sidebar.sh absent" {
    [ ! -e "$SCRIPTS_DIR/sidebar.sh" ]
}

@test "Sidebar helper removed: new-session.sh absent" {
    [ ! -e "$SCRIPTS_DIR/new-session.sh" ]
}

@test "Dead script removed: tree-view.sh" {
    [ ! -e "$SCRIPTS_DIR/tree-view.sh" ]
}

@test "Dead script removed: help.sh" {
    [ ! -e "$SCRIPTS_DIR/help.sh" ]
}

@test "Dead script removed: diff.sh" {
    [ ! -e "$SCRIPTS_DIR/diff.sh" ]
}

@test "Dead script removed: kill.sh" {
    [ ! -e "$SCRIPTS_DIR/kill.sh" ]
}

@test "Dead script removed: rename.sh" {
    [ ! -e "$SCRIPTS_DIR/rename.sh" ]
}

@test "Dead script removed: input.sh" {
    [ ! -e "$SCRIPTS_DIR/input.sh" ]
}

@test "Dead script removed: preview.sh" {
    [ ! -e "$SCRIPTS_DIR/preview.sh" ]
}

@test "Deprecated entry removed: session-new.sh" {
    [ ! -e "$SCRIPTS_DIR/session-new.sh" ]
}

@test "Orphan removed: cleanup.sh" {
    [ ! -e "$SCRIPTS_DIR/cleanup.sh" ]
}

@test "Keeper set present: 9 expected scripts" {
    local expected=(
        navigator.sh
        navigator-list.sh
        navigator-view.sh
        tile.sh
        statusline.sh
        session-add.sh
        session-delete.sh
        session-list.sh
        session-restore.sh
    )
    for f in "${expected[@]}"; do
        [ -e "$SCRIPTS_DIR/$f" ] || { echo "missing: $f"; return 1; }
    done
}

@test "Worktree directory creation removed from claude-tower.tmux" {
    ! grep -q "CLAUDE_TOWER_WORKTREE_DIR" "$PROJECT_ROOT/tmux-plugin/claude-tower.tmux"
    ! grep -q "mkdir.*worktrees" "$PROJECT_ROOT/tmux-plugin/claude-tower.tmux"
}

@test "TOWER_WORKTREE_DIR readonly removed from common.sh" {
    ! grep -q "readonly TOWER_WORKTREE_DIR" "$PROJECT_ROOT/tmux-plugin/lib/common.sh"
}
