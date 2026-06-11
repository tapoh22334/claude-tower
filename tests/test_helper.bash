#!/usr/bin/env bash
# Test helper for bats tests

# Get the directory of the test file
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$TEST_DIR")"

# NOTE on scratch directory:
#
# common.sh defines TOWER_METADATA_DIR as readonly the first time it is
# sourced, so we can't legitimately change the metadata path between tests
# inside the same bats file. The scratch path is therefore fixed for the
# whole file's lifetime, but `setup_test_env` always rebuilds an empty
# directory at it so individual tests start from a known clean slate.
#
# Tests that pre-set CLAUDE_TOWER_METADATA_DIR before loading this helper
# keep their override; otherwise we use a stable /tmp path.
: "${CLAUDE_TOWER_TEST_SCRATCH:=/tmp/claude-tower-tests-$$}"
export CLAUDE_TOWER_TEST_SCRATCH
export CLAUDE_TOWER_METADATA_DIR="${CLAUDE_TOWER_METADATA_DIR:-${CLAUDE_TOWER_TEST_SCRATCH}/metadata}"
export CLAUDE_TOWER_WORKTREE_DIR="${CLAUDE_TOWER_WORKTREE_DIR:-${CLAUDE_TOWER_TEST_SCRATCH}/worktrees}"

# Source the common library (without strict mode for testing).
# Idempotent: if common.sh has already been sourced in this shell, the
# readonly redeclarations would error under strict mode — we relax it.
source_common() {
    set +euo pipefail
    # shellcheck disable=SC1091
    source "$PROJECT_ROOT/tmux-plugin/lib/common.sh"
    set -euo pipefail
}

# Rebuild a clean fixture directory for the upcoming test.
# Wipes the actual metadata/worktree dirs (not just the scratch parent) so
# tests don't see leftover files from a previous test, even when those dirs
# live outside CLAUDE_TOWER_TEST_SCRATCH (e.g. when the Docker image sets
# CLAUDE_TOWER_METADATA_DIR to a fixed path).
setup_test_env() {
    rm -rf "$CLAUDE_TOWER_METADATA_DIR" "$CLAUDE_TOWER_WORKTREE_DIR" \
        "$CLAUDE_TOWER_TEST_SCRATCH"
    mkdir -p "$CLAUDE_TOWER_METADATA_DIR"
    mkdir -p "$CLAUDE_TOWER_WORKTREE_DIR"
}

# Clean up test fixtures at end of test.
teardown_test_env() {
    rm -rf "$CLAUDE_TOWER_METADATA_DIR" "$CLAUDE_TOWER_WORKTREE_DIR" \
        "$CLAUDE_TOWER_TEST_SCRATCH"
}

# Create a mock metadata file (v2 format)
create_mock_metadata() {
    local session_id="$1"
    local directory_path="${2:-/mock/workdir}"
    local session_name="${session_id#tower_}"

    cat > "${CLAUDE_TOWER_METADATA_DIR}/${session_id}.meta" << EOF
session_id=${session_id}
session_name=${session_name}
directory_path=${directory_path}
created_at=$(date -Iseconds)
EOF
}

# Create a mock v1 metadata file (for backward compatibility tests)
create_mock_metadata_v1() {
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
