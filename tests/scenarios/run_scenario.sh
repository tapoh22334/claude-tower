#!/usr/bin/env bash
# Scenario Test Runner
# Parses markdown scenario files and executes them as automated tests
# Usage: ./run_scenario.sh <scenario_file.md>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Colors
C_GREEN='\033[0;32m'
C_RED='\033[0;31m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_RESET='\033[0m'

# Test state
SCENARIO_NAME=""
PASSED=0
FAILED=0
SKIPPED=0

# Logging
log_info() { echo -e "${C_BLUE}[INFO]${C_RESET} $*"; }
log_pass() { echo -e "${C_GREEN}[PASS]${C_RESET} $*"; ((PASSED++)); }
log_fail() { echo -e "${C_RED}[FAIL]${C_RESET} $*"; ((FAILED++)); }
log_skip() { echo -e "${C_YELLOW}[SKIP]${C_RESET} $*"; ((SKIPPED++)); }

# Cleanup handler
cleanup() {
    local exit_code=$?
    if [[ -n "${TEST_SESSION_ID:-}" ]]; then
        tmux kill-session -t "$TEST_SESSION_ID" 2>/dev/null || true
    fi
    if [[ -n "${TEST_DIR:-}" ]] && [[ -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
    fi
    if [[ -n "${TEST_METADATA_DIR:-}" ]] && [[ -d "$TEST_METADATA_DIR" ]]; then
        rm -rf "$TEST_METADATA_DIR"
    fi
    return $exit_code
}
trap cleanup EXIT

# Parse scenario file
parse_scenario() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        log_fail "Scenario file not found: $file"
        exit 1
    fi

    SCENARIO_NAME=$(grep -m1 "^# " "$file" | sed 's/^# //' || echo "Unknown")
    log_info "Running scenario: $SCENARIO_NAME"
    log_info "File: $file"
    echo ""
}

# Extract and execute code blocks
execute_code_blocks() {
    local file="$1"
    local in_code_block=false
    local code_type=""
    local code=""
    local step_name=""
    local block_num=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Track step headers
        if [[ "$line" =~ ^###[[:space:]]+(.*) ]]; then
            step_name="${BASH_REMATCH[1]}"
            continue
        fi

        # Start of code block
        if [[ "$line" =~ ^\`\`\`([a-z]*) ]]; then
            code_type="${BASH_REMATCH[1]}"
            in_code_block=true
            code=""
            ((block_num++))
            continue
        fi

        # End of code block
        if [[ "$line" == '```' ]] && $in_code_block; then
            in_code_block=false

            if [[ "$code_type" == "bash" ]]; then
                execute_bash_block "$step_name" "$block_num" "$code"
            fi
            continue
        fi

        # Inside code block
        if $in_code_block; then
            code+="$line"$'\n'
        fi
    done < "$file"
}

# Execute a bash code block
execute_bash_block() {
    local step_name="$1"
    local block_num="$2"
    local code="$3"

    # Skip empty blocks
    if [[ -z "${code// /}" ]]; then
        return
    fi

    log_info "Step $block_num: $step_name"

    # Prepare environment
    export PROJECT_ROOT
    export TEST_DIR="${TEST_DIR:-$(mktemp -d)}"
    export TEST_METADATA_DIR="${TEST_METADATA_DIR:-$(mktemp -d)}"
    export CLAUDE_TOWER_METADATA_DIR="$TEST_METADATA_DIR"
    export CLAUDE_TOWER_WORKTREE_DIR="${TEST_DIR}/worktrees"
    mkdir -p "$CLAUDE_TOWER_WORKTREE_DIR"

    # Source common library if not already
    if ! declare -f save_metadata &>/dev/null; then
        # shellcheck source=/dev/null
        source "$PROJECT_ROOT/tmux-plugin/lib/common.sh" 2>/dev/null || true
    fi

    # Execute the code
    local output
    local exit_code=0

    # Replace placeholder paths
    code="${code//\/path\/to\/tmux-plugin/$PROJECT_ROOT/tmux-plugin}"
    code="${code//\$HOME\/\.claude-tower\/metadata/$TEST_METADATA_DIR}"

    output=$(eval "$code" 2>&1) || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_pass "Block $block_num executed successfully"
    else
        log_fail "Block $block_num failed with exit code $exit_code"
        echo "  Output: $output"
    fi
}

# Run verification commands from scenario
run_verification() {
    local file="$1"
    local in_verification=false
    local verification_code=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ "Verification Commands" ]]; then
            in_verification=true
            continue
        fi

        if $in_verification && [[ "$line" =~ ^\`\`\`bash ]]; then
            verification_code=""
            continue
        fi

        if $in_verification && [[ "$line" == '```' ]] && [[ -n "$verification_code" ]]; then
            log_info "Running verification..."
            eval "$verification_code" 2>&1 || true
            in_verification=false
            continue
        fi

        if $in_verification && [[ "$line" != '```'* ]]; then
            verification_code+="$line"$'\n'
        fi
    done < "$file"
}

# Print summary
print_summary() {
    echo ""
    echo "=========================================="
    echo -e "Scenario: ${C_BLUE}$SCENARIO_NAME${C_RESET}"
    echo "=========================================="
    echo -e "  ${C_GREEN}Passed:${C_RESET}  $PASSED"
    echo -e "  ${C_RED}Failed:${C_RESET}  $FAILED"
    echo -e "  ${C_YELLOW}Skipped:${C_RESET} $SKIPPED"
    echo ""

    if [[ $FAILED -eq 0 ]]; then
        echo -e "${C_GREEN}✓ All checks passed${C_RESET}"
        return 0
    else
        echo -e "${C_RED}✗ Some checks failed${C_RESET}"
        return 1
    fi
}

# Main
main() {
    local scenario_file="${1:-}"

    if [[ -z "$scenario_file" ]]; then
        echo "Usage: $0 <scenario_file.md>"
        echo ""
        echo "Available scenarios:"
        for f in "$SCRIPT_DIR"/*.md; do
            [[ -f "$f" ]] && echo "  - $(basename "$f")"
        done
        exit 1
    fi

    # If not absolute path, look in scenarios directory
    if [[ ! -f "$scenario_file" ]]; then
        scenario_file="$SCRIPT_DIR/$scenario_file"
    fi

    parse_scenario "$scenario_file"
    execute_code_blocks "$scenario_file"
    run_verification "$scenario_file"
    print_summary
}

main "$@"
