#!/usr/bin/env bash
# Show help

cat <<'EOF'
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  claude-tower - Session/Window/Pane Manager
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

KEYBINDINGS (in picker):

  Enter      Select and switch to item
  n          Create new session
  r          Rename session/window
  x          Kill session/window/pane
  D          Show git diff (workspace session type only)
  ?          Show this help
  Esc        Close picker

NAVIGATION:

  j/↓        Move down
  k/↑        Move up
  /          Search
  Tab        Toggle preview

SESSION TYPES:

  [W] Workspace    Git-managed with worktree isolation
                   - Creates separate git worktree
                   - Shows diff stats from source commit
                   - Branch: tower/<session-name>

  [S] Simple       Regular session in any directory
                   - No git integration
                   - Just runs the program

ICONS:

  📁  Session
  🪟  Window
  ▫   Pane
  ●   Active (currently selected)
  ⎇   Git branch

CONFIGURATION (in .tmux.conf):

  set -g @tower-key 'C'           # Key to open picker (default: C)
  set -g @tower-new-key 'T'       # Key for new session (default: T)

ENVIRONMENT VARIABLES:

  CLAUDE_TOWER_PROGRAM       Program to run (default: claude)
  CLAUDE_TOWER_WORKTREE_DIR  Worktree storage (default: ~/.claude-tower/worktrees)
  CLAUDE_TOWER_METADATA_DIR  Metadata storage (default: ~/.claude-tower/metadata)

DATA STORAGE:

  ~/.claude-tower/metadata/   Session metadata files
  ~/.claude-tower/worktrees/  Git worktrees

CLEANUP:

  Run cleanup.sh to remove orphaned worktrees:
    cleanup.sh --list     List orphaned worktrees
    cleanup.sh            Interactive cleanup
    cleanup.sh --force    Remove all orphaned worktrees

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
