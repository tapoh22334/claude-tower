#!/usr/bin/env bash
# Test helper for bats tests

# Get the directory of the test file
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$TEST_DIR")"

# Set up test environment
export CLAUDE_TOWER_METADATA_DIR="${TEST_DIR}/tmp/metadata"

# Source the common library (without strict mode for testing)
#
# common.sh installs its own `trap ... EXIT` (spinner cleanup) and
# `trap ... ERR` (error logging) handlers, meant for interactive script
# usage. Bats relies on its own EXIT trap (bats_teardown_trap) to detect
# test completion; if common.sh's sourcing clobbers it, bats silently loses
# track of the test (it never emits `ok`/`not ok` — see BW01). Save and
# restore both traps around the source so bats' machinery survives.
source_common() {
    local saved_exit_trap saved_err_trap
    saved_exit_trap="$(trap -p EXIT)"
    saved_err_trap="$(trap -p ERR)"

    # Temporarily disable strict mode for sourcing
    set +euo pipefail
    source "$PROJECT_ROOT/tmux-plugin/lib/common.sh"
    set -euo pipefail

    if [[ -n "$saved_exit_trap" ]]; then
        eval "$saved_exit_trap"
    else
        trap - EXIT
    fi
    if [[ -n "$saved_err_trap" ]]; then
        eval "$saved_err_trap"
    else
        trap - ERR
    fi
}

# Set up test fixtures
setup_test_env() {
    mkdir -p "$CLAUDE_TOWER_METADATA_DIR"
    mkdir -p "$CLAUDE_PROJECTS_DIR"
}

# Clean up test fixtures
teardown_test_env() {
    rm -rf "${TEST_DIR}/tmp"
}

# Create a mock metadata file (new minimal format)
create_mock_metadata() {
    local session_id="$1"
    local session_name="${2:-}"
    {
        [[ -n "$session_name" ]] && echo "session_name=${session_name}"
        echo "created_at=$(date -Iseconds)"
    } > "${CLAUDE_TOWER_METADATA_DIR}/${session_id}.meta"
}

# Mock tmux command for testing
mock_tmux() {
    # Create a mock tmux function that can be customized per test
    :
}

# --- claude-sessions fixtures ---
export CLAUDE_PROJECTS_DIR="${TEST_DIR}/tmp/claude-projects"

# Create a fixture transcript.
# $1 slug dir name, $2 session uuid, $3 cwd value ("" to omit cwd lines entirely)
create_mock_jsonl() {
    local slug="$1" uuid="$2" cwd="${3:-}"
    local dir="${CLAUDE_PROJECTS_DIR}/${slug}"
    mkdir -p "$dir"
    local f="${dir}/${uuid}.jsonl"
    # First line mimics real data: no cwd (queue-operation)
    echo '{"type":"queue-operation","op":"enqueue"}' > "$f"
    if [[ -n "$cwd" ]]; then
        printf '{"type":"user","cwd":"%s","message":{"role":"user"}}\n' "$cwd" >> "$f"
        printf '{"type":"assistant","cwd":"%s","message":{"role":"assistant"}}\n' "$cwd" >> "$f"
    fi
    echo "$f"
}

# Create an empty-shell transcript (no user/assistant lines)
create_empty_jsonl() {
    local slug="$1" uuid="$2"
    local dir="${CLAUDE_PROJECTS_DIR}/${slug}"
    mkdir -p "$dir"
    local f="${dir}/${uuid}.jsonl"
    echo '{"type":"queue-operation","op":"enqueue"}' > "$f"
    echo "$f"
}

# Create a parent transcript and a fork transcript that copies the parent's
# first messages by uuid (sessionId rewritten to the fork's id) — the real
# on-disk fork signature. $1 slug, $2 parent uuid, $3 fork uuid, $4 cwd.
# The fork file is touched newer than the parent.
create_fork_pair_jsonl() {
    local slug="$1" parent="$2" fork="$3" cwd="$4"
    local dir="${CLAUDE_PROJECTS_DIR}/${slug}"
    mkdir -p "$dir"
    local pf="${dir}/${parent}.jsonl" ff="${dir}/${fork}.jsonl"
    local u1="aaaaaaaa-0000-4000-8000-000000000001"
    local u2="aaaaaaaa-0000-4000-8000-000000000002"
    # Parent: two messages with uuids u1,u2 under the parent sessionId.
    printf '{"type":"user","cwd":"%s","sessionId":"%s","uuid":"%s"}\n' "$cwd" "$parent" "$u1" >"$pf"
    printf '{"type":"assistant","cwd":"%s","sessionId":"%s","uuid":"%s"}\n' "$cwd" "$parent" "$u2" >>"$pf"
    # Fork: same uuids u1,u2 but sessionId rewritten to the fork id, plus a
    # new fork-only message.
    printf '{"type":"user","cwd":"%s","sessionId":"%s","uuid":"%s"}\n' "$cwd" "$fork" "$u1" >"$ff"
    printf '{"type":"assistant","cwd":"%s","sessionId":"%s","uuid":"%s"}\n' "$cwd" "$fork" "$u2" >>"$ff"
    printf '{"type":"user","cwd":"%s","sessionId":"%s","uuid":"%s"}\n' "$cwd" "$fork" "bbbbbbbb-0000-4000-8000-000000000003" >>"$ff"
    # Ensure fork is newer than parent.
    touch -d '2020-01-01 00:00:00' "$pf"
    touch -d '2020-01-01 00:00:10' "$ff"
    printf '%s\t%s\n' "$pf" "$ff"
}
