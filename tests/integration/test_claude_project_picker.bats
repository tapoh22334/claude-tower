#!/usr/bin/env bats
# Tests for the Claude-project picker that feeds the `n` (new session)
# flow in Navigator.
#
# The picker reads from ~/.claude/projects/*/sessions-index.json and
# ~/.claude/history.jsonl — both internal Claude Code formats that we
# treat defensively. The tests cover happy paths plus the failure modes:
# missing files, bad versions, no jq, mixed sources.

PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
NAV_LIST_SCRIPT="$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh"

setup() {
    # Each test gets its own fake ~/.claude tree so we can shape the input.
    export CLAUDE_TOWER_CLAUDE_DIR
    CLAUDE_TOWER_CLAUDE_DIR=$(mktemp -d)
    mkdir -p "$CLAUDE_TOWER_CLAUDE_DIR/projects"

    # Override caller CWD file path too so sourcing doesn't poke real state.
    export CLAUDE_TOWER_CALLER_CWD_FILE
    CLAUDE_TOWER_CALLER_CWD_FILE=$(mktemp)

    # Isolated metadata dir so existing-tower-session check has no leftovers.
    export CLAUDE_TOWER_METADATA_DIR
    CLAUDE_TOWER_METADATA_DIR=$(mktemp -d)

    set +euo pipefail
    # shellcheck disable=SC1090
    source "$NAV_LIST_SCRIPT"
    set -euo pipefail
    trap - ERR  # bats and common.sh's ERR trap don't mix

    # Picker needs SESSION_IDS to be defined so the registered-filter loop
    # iterates over an empty set by default.
    SESSION_IDS=()
}

teardown() {
    rm -rf "$CLAUDE_TOWER_CLAUDE_DIR" "$CLAUDE_TOWER_METADATA_DIR" 2>/dev/null
    rm -f "$CLAUDE_TOWER_CALLER_CWD_FILE" 2>/dev/null
}

# Build a sessions-index.json with a given version and a list of project
# paths. Args: <encoded-dir-name> <version> <path1> [<path2> ...]
make_sessions_index() {
    local enc="$1" ver="$2"
    shift 2
    local dir="$CLAUDE_TOWER_CLAUDE_DIR/projects/$enc"
    mkdir -p "$dir"
    local entries=""
    local first=1
    for p in "$@"; do
        if [[ $first -eq 1 ]]; then first=0; else entries+=","; fi
        entries+=$(printf '{"sessionId":"id-%s","projectPath":"%s"}' "$enc" "$p")
    done
    printf '{"version":%s,"entries":[%s]}' "$ver" "$entries" \
        >"$dir/sessions-index.json"
}

# Build a history.jsonl with one project path per line.
make_history() {
    local f="$CLAUDE_TOWER_CLAUDE_DIR/history.jsonl"
    : >"$f"
    local p
    for p in "$@"; do
        printf '{"prompt":"hi","projectPath":"%s","timestamp":"x"}\n' "$p" >>"$f"
    done
}

# ============================================================================
# Empty / missing inputs
# ============================================================================

@test "_load_claude_projects: returns nothing when no Claude data exists" {
    run _load_claude_projects
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "_load_claude_projects: tolerates missing history.jsonl" {
    # Only sessions-index.json present, no history.jsonl.
    local tmpdir
    tmpdir=$(mktemp -d)
    make_sessions_index test 1 "$tmpdir"
    run _load_claude_projects
    [ "$status" -eq 0 ]
    [[ "$output" == *"$tmpdir"* ]]
    rm -rf "$tmpdir"
}

@test "_load_claude_projects: tolerates missing projects dir" {
    rm -rf "$CLAUDE_TOWER_CLAUDE_DIR/projects"
    local tmpdir
    tmpdir=$(mktemp -d)
    make_history "$tmpdir"
    run _load_claude_projects
    [ "$status" -eq 0 ]
    [[ "$output" == *"$tmpdir"* ]]
    rm -rf "$tmpdir"
}

# ============================================================================
# Version gating
# ============================================================================

@test "_load_claude_projects: skips sessions-index with unsupported version" {
    local tmpdir1 tmpdir2
    tmpdir1=$(mktemp -d)
    tmpdir2=$(mktemp -d)
    # version 1 is supported, version 99 is future/unknown
    make_sessions_index ok 1 "$tmpdir1"
    make_sessions_index future 99 "$tmpdir2"

    run _load_claude_projects
    [ "$status" -eq 0 ]
    [[ "$output" == *"$tmpdir1"* ]]
    ! [[ "$output" == *"$tmpdir2"* ]]

    rm -rf "$tmpdir1" "$tmpdir2"
}

@test "_load_claude_projects: skips a malformed JSON file silently" {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$CLAUDE_TOWER_CLAUDE_DIR/projects/broken"
    echo "this is not json {{{" >"$CLAUDE_TOWER_CLAUDE_DIR/projects/broken/sessions-index.json"
    make_sessions_index ok 1 "$tmpdir"

    run _load_claude_projects
    [ "$status" -eq 0 ]
    [[ "$output" == *"$tmpdir"* ]]
    rm -rf "$tmpdir"
}

# ============================================================================
# Filtering: non-existent dirs and already-registered tower sessions
# ============================================================================

@test "_load_claude_projects: filters out non-existent directories" {
    local real
    real=$(mktemp -d)
    make_sessions_index ok 1 "$real" "/does/not/exist/anywhere"
    run _load_claude_projects
    [ "$status" -eq 0 ]
    [[ "$output" == *"$real"* ]]
    ! [[ "$output" == *"/does/not/exist"* ]]
    rm -rf "$real"
}

@test "_load_claude_projects: filters out paths already registered as tower sessions" {
    local registered free
    registered=$(mktemp -d)
    free=$(mktemp -d)
    make_sessions_index ok 1 "$registered" "$free"

    # Pre-create a tower session metadata file pointing at $registered.
    cat >"$CLAUDE_TOWER_METADATA_DIR/tower_already.meta" <<EOF
session_id=tower_already
session_name=already
directory_path=$registered
EOF
    SESSION_IDS=("tower_already")

    run _load_claude_projects
    [ "$status" -eq 0 ]
    [[ "$output" == *"$free"* ]]
    ! [[ "$output" == *"$registered"* ]]

    rm -rf "$registered" "$free"
}

# ============================================================================
# Deduplication and source mixing
# ============================================================================

@test "_load_claude_projects: dedups when same path comes from both sources" {
    local d
    d=$(mktemp -d)
    make_sessions_index ok 1 "$d"
    make_history "$d"

    run _load_claude_projects
    [ "$status" -eq 0 ]
    # Should appear exactly once
    local count
    count=$(grep -cF "$d" <<<"$output")
    [ "$count" -eq 1 ]
    rm -rf "$d"
}

# ============================================================================
# add_new_session fallback contract
# ============================================================================

@test "add_new_session: documents fallback to manual entry on empty picker" {
    # When _load_claude_projects returns nothing, add_new_session must
    # delegate to _add_session_manual_entry. Regression-guard at source
    # level: extract the add_new_session function body and verify both the
    # empty-check and the manual call are present in it.
    local body
    body=$(awk '/^add_new_session\(\)/,/^}/' "$NAV_LIST_SCRIPT")
    echo "$body" | grep -q '_load_claude_projects'
    echo "$body" | grep -q '_add_session_manual_entry'
    echo "$body" | grep -q '\[\[ -z "\$projects" \]\]'
}

@test "_render_project_picker: exposes a manual-entry escape hatch" {
    # The picker footer must advertise the m key for manual entry, so a
    # blank-state user is never stranded.
    grep -q "m:manual path" "$NAV_LIST_SCRIPT"
}

@test "_run_project_picker: maps the MANUAL sentinel back to manual entry" {
    grep -q 'MANUAL)' "$NAV_LIST_SCRIPT"
    grep -A1 'MANUAL)' "$NAV_LIST_SCRIPT" | grep -q "_add_session_manual_entry"
}
