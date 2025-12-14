#!/usr/bin/env bash
# Show help

cat << 'EOF'
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  tmux-pilot - Session/Window/Pane Manager
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

KEYBINDINGS (in picker):

  Enter      Select and switch to item
  n          Create new session
  r          Rename session/window
  x          Kill session/window/pane
  D          Show git diff (workspace only)
  ?          Show this help
  Esc        Close picker

NAVIGATION:

  j/↓        Move down
  k/↑        Move up
  /          Search
  Tab        Toggle preview

SESSION MODES:

  [W] Workspace    Git-managed with worktree isolation
                   - Creates separate git worktree
                   - Shows diff stats
                   - Branch: pilot/<session-name>

  [S] Simple       Regular session in any directory
                   - No git integration
                   - Just runs the program

ICONS:

  📁  Session
  🪟  Window
  ▫   Pane
  ●   Currently active
  ⎇   Git branch

CONFIGURATION (in .tmux.conf):

  set -g @pilot-key 'C'           # Key to open picker (default: C)
  set -g @pilot-new-key 'T'       # Key for new session (default: T)

ENVIRONMENT VARIABLES:

  TMUX_PILOT_PROGRAM       Program to run (default: claude)
  TMUX_PILOT_WORKTREE_DIR  Worktree storage (default: ~/.tmux-pilot/worktrees)
  TMUX_PILOT_METADATA_DIR  Metadata storage (default: ~/.tmux-pilot/metadata)

DATA STORAGE:

  ~/.tmux-pilot/metadata/   Session metadata files
  ~/.tmux-pilot/worktrees/  Git worktrees

CLEANUP:

  Run cleanup.sh to remove orphaned worktrees:
    cleanup.sh --list     List orphaned worktrees
    cleanup.sh            Interactive cleanup
    cleanup.sh --force    Remove all orphans

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
