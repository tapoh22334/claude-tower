# Scenario: Workspace Session with Git Worktree

## Description
Test that a workspace session creates an isolated git worktree correctly.

## Preconditions
- tmux is installed
- git is installed
- Current directory IS a git repository with at least one commit

## Steps

### Step 1: Set up test repository
```bash
TEST_REPO=$(mktemp -d)
cd "$TEST_REPO"
git init
git config user.email "test@test.com"
git config user.name "Test"
echo "Hello" > README.md
git add .
git commit -m "Initial commit"
```

### Step 2: Source common library and set environment
```bash
export CLAUDE_TOWER_WORKTREE_DIR="$TEST_REPO/.worktrees"
export CLAUDE_TOWER_METADATA_DIR="$TEST_REPO/.metadata"
source /path/to/tmux-plugin/lib/common.sh
```

### Step 3: Create workspace session
```bash
SESSION_NAME="feature-test"
SESSION_ID="tower_${SESSION_NAME}"
BRANCH_NAME="tower/${SESSION_NAME}"
WORKTREE_PATH="${CLAUDE_TOWER_WORKTREE_DIR}/${SESSION_NAME}"
SOURCE_COMMIT=$(git rev-parse HEAD)

# Create worktree with new branch
mkdir -p "$(dirname "$WORKTREE_PATH")"
git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH" "$SOURCE_COMMIT"

# Create tmux session
tmux new-session -d -s "$SESSION_ID" -c "$WORKTREE_PATH"

# Set metadata
tmux set-option -t "$SESSION_ID" @tower_session_type "workspace"
tmux set-option -t "$SESSION_ID" @tower_repository "$TEST_REPO"
tmux set-option -t "$SESSION_ID" @tower_source "$SOURCE_COMMIT"

save_metadata "$SESSION_ID" "workspace" "$TEST_REPO" "$SOURCE_COMMIT"
```

### Step 4: Verify worktree isolation
```bash
# Make change in worktree
echo "Worktree change" >> "$WORKTREE_PATH/README.md"

# Verify main repo unchanged
cat "$TEST_REPO/README.md"
# Expected: "Hello" (no change)

cat "$WORKTREE_PATH/README.md"
# Expected: "Hello\nWorktree change"
```

### Step 5: Verify git branch
```bash
git -C "$WORKTREE_PATH" branch --show-current
# Expected: "tower/feature-test"
```

## Expected Outcomes
- Worktree exists at `$WORKTREE_PATH`
- Branch `tower/feature-test` is created
- Changes in worktree don't affect main repo
- Session metadata correctly stores repository path and source commit

## Cleanup
```bash
tmux kill-session -t "$SESSION_ID"
git -C "$TEST_REPO" worktree remove --force "$WORKTREE_PATH"
git -C "$TEST_REPO" branch -D "$BRANCH_NAME"
rm -rf "$TEST_REPO"
```
