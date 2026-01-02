#!/usr/bin/env bash
# Show diff for workspace session

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common library
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

INPUT="$1"
IFS=':' read -r type selected_session _ <<<"$INPUT"

# Get session metadata
session_type=$(tmux show-option -t "$selected_session" -qv @tower_session_type 2>/dev/null || echo "")
repository_path=$(tmux show-option -t "$selected_session" -qv @tower_repository 2>/dev/null || echo "")
source_commit=$(tmux show-option -t "$selected_session" -qv @tower_source 2>/dev/null || echo "")

if [[ "$session_type" != "workspace" ]]; then
    printf "%b%s%b\n" "$C_INFO" "Not a workspace session - no diff available" "$C_RESET"
    exit 0
fi

# Get worktree path
name="${selected_session#tower_}"
worktree_path="${TOWER_WORKTREE_DIR}/${name}"

if [[ ! -d "$worktree_path" ]]; then
    printf "%b%s%b\n" "$C_INFO" "Worktree not found" "$C_RESET"
    exit 0
fi

# Show header
printf "%b━━━ Diff: %s ━━━%b\n" "$C_HEADER" "$selected_session" "$C_RESET"
echo ""

# Get current branch
branch=$(git -C "$worktree_path" branch --show-current 2>/dev/null || echo "unknown")
printf "%bBranch:%b %s\n" "$C_INFO" "$C_RESET" "$branch"
printf "%bSource:%b %s\n" "$C_INFO" "$C_RESET" "${source_commit:0:8}"
echo ""

# Get diff stats
diff_stats=$(git -C "$worktree_path" diff "$source_commit" --stat 2>/dev/null || echo "")
if [[ -n "$diff_stats" ]]; then
    printf "%b━━━ Stats ━━━%b\n" "$C_HEADER" "$C_RESET"
    echo "$diff_stats"
    echo ""
fi

# Show diff with colors
printf "%b━━━ Changes ━━━%b\n" "$C_HEADER" "$C_RESET"
git -C "$worktree_path" diff "$source_commit" --color=always 2>/dev/null || echo "(no changes)"
