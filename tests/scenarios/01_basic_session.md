# Scenario: Basic Session Creation

## Description
Test that a simple (non-git) session can be created and managed correctly.

## Preconditions
- tmux is installed and running
- claude-tower plugin is loaded
- Current directory is NOT a git repository

## Steps

### Step 1: Create a temporary test directory
```bash
TEST_DIR=$(mktemp -d)
cd "$TEST_DIR"
```

### Step 2: Source the common library
```bash
source /path/to/tmux-plugin/lib/common.sh
```

### Step 3: Create a simple session manually
```bash
SESSION_NAME="scenario-test-simple"
SESSION_ID="tower_${SESSION_NAME}"

# Create tmux session
tmux new-session -d -s "$SESSION_ID" -c "$TEST_DIR"

# Set session type
tmux set-option -t "$SESSION_ID" @tower_session_type "simple"

# Save metadata
save_metadata "$SESSION_ID" "simple"
```

### Step 4: Verify session exists
```bash
tmux has-session -t "$SESSION_ID"
# Expected: exit code 0
```

### Step 5: Verify metadata was saved
```bash
cat "$HOME/.claude-tower/metadata/${SESSION_ID}.meta"
# Expected: file contains session_type=simple
```

### Step 6: Verify session type option
```bash
tmux show-option -t "$SESSION_ID" -v @tower_session_type
# Expected: "simple"
```

## Expected Outcomes
- Session `tower_scenario-test-simple` exists in tmux
- Metadata file exists at `~/.claude-tower/metadata/tower_scenario-test-simple.meta`
- Session type is recorded as "simple"

## Cleanup
```bash
tmux kill-session -t "$SESSION_ID"
rm -f "$HOME/.claude-tower/metadata/${SESSION_ID}.meta"
rm -rf "$TEST_DIR"
```

## Verification Commands for LLM
The LLM can verify success by running:
```bash
# All should succeed (exit 0)
tmux has-session -t "tower_scenario-test-simple" && echo "PASS: session exists"
[ -f "$HOME/.claude-tower/metadata/tower_scenario-test-simple.meta" ] && echo "PASS: metadata exists"
grep -q "session_type=simple" "$HOME/.claude-tower/metadata/tower_scenario-test-simple.meta" && echo "PASS: correct type"
```
