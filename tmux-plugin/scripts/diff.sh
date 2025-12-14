#!/usr/bin/env bash
# Show diff for workspace session

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common library
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

INPUT="$1"
IFS=':' read -r type session _ <<< "$INPUT"

# Get session info
mode=$(tmux show-option -t "$session" -qv @tower_mode 2>/dev/null || echo "")
repo=$(tmux show-option -t "$session" -qv @tower_repo 2>/dev/null || echo "")
base=$(tmux show-option -t "$session" -qv @tower_base 2>/dev/null || echo "")

if [[ "$mode" != "workspace" ]]; then
    printf "%b%s%b\n" "$C_INFO" "Not a workspace session - no diff available" "$C_RESET"
    exit 0
fi

# Get worktree path
name="${session#tower_}"
worktree_path="${TOWER_WORKTREE_DIR}/${name}"

if [[ ! -d "$worktree_path" ]]; then
    printf "%b%s%b\n" "$C_INFO" "Worktree not found" "$C_RESET"
    exit 0
fi

# Show header
printf "%b━━━ Diff: %s ━━━%b\n" "$C_HEADER" "$session" "$C_RESET"
echo ""

# Get current branch
branch=$(git -C "$worktree_path" branch --show-current 2>/dev/null || echo "unknown")
printf "%bBranch:%b %s\n" "$C_INFO" "$C_RESET" "$branch"
printf "%bBase:%b %s\n" "$C_INFO" "$C_RESET" "${base:0:8}"
echo ""

# Get stats
stats=$(git -C "$worktree_path" diff "$base" --stat 2>/dev/null || echo "")
if [[ -n "$stats" ]]; then
    printf "%b━━━ Stats ━━━%b\n" "$C_HEADER" "$C_RESET"
    echo "$stats"
    echo ""
fi

# Show diff with colors
printf "%b━━━ Changes ━━━%b\n" "$C_HEADER" "$C_RESET"
git -C "$worktree_path" diff "$base" --color=always 2>/dev/null || echo "(no changes)"
