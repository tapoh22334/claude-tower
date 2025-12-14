#!/usr/bin/env bash
# Test helper for bats tests

# Get the directory of the test file
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$TEST_DIR")"

# Set up test environment
export CLAUDE_TOWER_METADATA_DIR="${TEST_DIR}/tmp/metadata"
export CLAUDE_TOWER_WORKTREE_DIR="${TEST_DIR}/tmp/worktrees"

# Source the common library (without strict mode for testing)
source_common() {
    # Temporarily disable strict mode for sourcing
    set +euo pipefail
    source "$PROJECT_ROOT/tmux-plugin/lib/common.sh"
    set -euo pipefail
}

# Set up test fixtures
setup_test_env() {
    mkdir -p "$CLAUDE_TOWER_METADATA_DIR"
    mkdir -p "$CLAUDE_TOWER_WORKTREE_DIR"
}

# Clean up test fixtures
teardown_test_env() {
    rm -rf "${TEST_DIR}/tmp"
}

# Create a mock metadata file
create_mock_metadata() {
    local session_id="$1"
    local session_type="${2:-workspace}"
    local repository_path="${3:-/mock/repo}"
    local source_commit="${4:-abc123}"

    cat > "${CLAUDE_TOWER_METADATA_DIR}/${session_id}.meta" << EOF
session_id=${session_id}
session_type=${session_type}
created_at=$(date -Iseconds)
repository_path=${repository_path}
source_commit=${source_commit}
worktree_path=${CLAUDE_TOWER_WORKTREE_DIR}/${session_id#tower_}
EOF
}

# Mock tmux command for testing
mock_tmux() {
    # Create a mock tmux function that can be customized per test
    :
}
