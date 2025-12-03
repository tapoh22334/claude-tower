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
  d          Kill session/window/pane
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

  set -g @pilot-key 'p'           # Key to open picker (default: p)
  set -g @pilot-new-key 'P'       # Key for new session (default: P)

ENVIRONMENT VARIABLES:

  TMUX_PILOT_PROGRAM      Program to run (default: claude)
  TMUX_PILOT_WORKTREE_DIR Worktree storage (default: ~/.tmux-pilot/worktrees)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
