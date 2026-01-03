#!/usr/bin/env bash
# Show help - Updated to match SPECIFICATION.md v3.2

show_help() {
    clear
    cat <<'EOF'
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Claude Tower Navigator Help
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

NAVIGATION (focus: list):

  j / ↓      Move down
  k / ↑      Move up
  g          Go to first session
  G          Go to last session
  1-9        Select session by number

ACTIONS:

  Enter      Full attach to selected session
  i          Focus view pane (input mode)
  Tab        Switch to Tile view
  n          Create new session
  d          Delete selected session
  r          Restore selected dormant session
  R          Restore all dormant sessions

INPUT MODE (focus: view):

  Escape     Return to list navigation
  (other)    Keys sent to session

OTHER:

  ?          Show this help
  q          Quit Navigator

SESSION STATES:

  ▶  Active   Claude is running
  !  Exited   Claude has exited
  ○  Dormant  Session saved, not running

SESSION TYPES:

  [W] Workspace   Git worktree managed
  [S] Simple      Regular session

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Press any key to return...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
    read -rsn1
}

show_help
