#!/usr/bin/env bash
# Show diff for workspace session

set -e

INPUT="$1"
IFS=':' read -r type session _ <<< "$INPUT"

# Colors
C_RESET="\033[0m"
C_HEADER="\033[1;36m"
C_ADD="\033[0;32m"
C_DEL="\033[0;31m"
C_HUNK="\033[0;36m"
C_INFO="\033[0;33m"

# Get session info
mode=$(tmux show-option -t "$session" -qv @pilot_mode 2>/dev/null || echo "")
repo=$(tmux show-option -t "$session" -qv @pilot_repo 2>/dev/null || echo "")
base=$(tmux show-option -t "$session" -qv @pilot_base 2>/dev/null || echo "")

if [[ "$mode" != "workspace" ]]; then
    echo -e "${C_INFO}Not a workspace session - no diff available${C_RESET}"
    exit 0
fi

# Get worktree path
PILOT_WORKTREE_DIR="${TMUX_PILOT_WORKTREE_DIR:-$HOME/.tmux-pilot/worktrees}"
name="${session#pilot_}"
worktree_path="${PILOT_WORKTREE_DIR}/${name}"

if [[ ! -d "$worktree_path" ]]; then
    echo -e "${C_INFO}Worktree not found${C_RESET}"
    exit 0
fi

# Show header
echo -e "${C_HEADER}━━━ Diff: $session ━━━${C_RESET}"
echo ""

# Get current branch
branch=$(git -C "$worktree_path" branch --show-current 2>/dev/null || echo "unknown")
echo -e "${C_INFO}Branch:${C_RESET} $branch"
echo -e "${C_INFO}Base:${C_RESET} ${base:0:8}"
echo ""

# Get stats
stats=$(git -C "$worktree_path" diff "$base" --stat 2>/dev/null || echo "")
if [[ -n "$stats" ]]; then
    echo -e "${C_HEADER}━━━ Stats ━━━${C_RESET}"
    echo "$stats"
    echo ""
fi

# Show diff with colors
echo -e "${C_HEADER}━━━ Changes ━━━${C_RESET}"
git -C "$worktree_path" diff "$base" --color=always 2>/dev/null || echo "(no changes)"
