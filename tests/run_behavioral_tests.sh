#!/usr/bin/env bash
# Behavioral Test Runner
# Runs all behavioral tests: contract-based, snapshot, server-switch, and scenarios
# Usage: ./run_behavioral_tests.sh [--quick|--full|--verbose]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
C_GREEN='\033[0;32m'
C_RED='\033[0;31m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_BOLD='\033[1m'
C_RESET='\033[0m'

# Default options
VERBOSE=false
QUICK=false
PARALLEL=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --quick)
            QUICK=true
            shift
            ;;
        --full)
            QUICK=false
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --parallel|-p)
            PARALLEL=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --quick      Run quick tests only (skip slow integration tests)"
            echo "  --full       Run all tests including slow ones (default)"
            echo "  --verbose    Show detailed test output"
            echo "  --parallel   Run test files in parallel"
            echo "  --help       Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Header
echo ""
echo -e "${C_BOLD}╔════════════════════════════════════════════════════════════╗${C_RESET}"
echo -e "${C_BOLD}║            Claude Tower Behavioral Tests                    ║${C_RESET}"
echo -e "${C_BOLD}╚════════════════════════════════════════════════════════════╝${C_RESET}"
echo ""

# Check for bats
if ! command -v bats &>/dev/null; then
    echo -e "${C_RED}Error: bats not found${C_RESET}"
    echo "Install with: npm install -g bats"
    echo "Or: brew install bats-core"
    exit 1
fi

# Test categories
declare -a QUICK_TESTS=(
    # Contract-based tests (fast, no real tmux needed)
    "integration/test_navigation_contract.bats"
)

declare -a DISPLAY_TESTS=(
    # Display/snapshot tests
    "integration/test_display_snapshot.bats"
)

declare -a SERVER_TESTS=(
    # Server switch tests (need real tmux)
    "integration/test_server_switch.bats"
)

declare -a SCENARIO_TESTS=(
    # Scenario-based tests
    "scenarios/test_scenarios.bats"
)

# Results tracking
TOTAL_PASSED=0
TOTAL_FAILED=0
TOTAL_SKIPPED=0

# Run a test file
run_test_file() {
    local test_file="$1"
    local category="$2"

    if [[ ! -f "$SCRIPT_DIR/$test_file" ]]; then
        echo -e "${C_YELLOW}[SKIP]${C_RESET} $test_file (file not found)"
        return 0
    fi

    echo -e "${C_BLUE}[RUN]${C_RESET} $category: $test_file"

    local bats_args=()
    if $VERBOSE; then
        bats_args+=("--verbose-run")
    fi

    local output
    local exit_code=0

    if output=$(bats "${bats_args[@]}" "$SCRIPT_DIR/$test_file" 2>&1); then
        exit_code=0
    else
        exit_code=$?
    fi

    # Parse results
    local passed failed skipped
    passed=$(echo "$output" | grep -oE '[0-9]+ tests?, [0-9]+ failures?' | grep -oE '^[0-9]+' || echo 0)
    failed=$(echo "$output" | grep -oE '[0-9]+ failures?' | grep -oE '[0-9]+' || echo 0)
    skipped=$(echo "$output" | grep -oE '[0-9]+ skipped' | grep -oE '[0-9]+' || echo 0)

    TOTAL_PASSED=$((TOTAL_PASSED + passed - failed))
    TOTAL_FAILED=$((TOTAL_FAILED + failed))
    TOTAL_SKIPPED=$((TOTAL_SKIPPED + skipped))

    if [[ $exit_code -eq 0 ]]; then
        echo -e "${C_GREEN}[PASS]${C_RESET} $test_file (${passed} tests)"
    else
        echo -e "${C_RED}[FAIL]${C_RESET} $test_file (${failed} failures)"
        if $VERBOSE; then
            echo "$output"
        fi
    fi

    return $exit_code
}

# Run test category
run_category() {
    local category="$1"
    shift
    local tests=("$@")

    echo ""
    echo -e "${C_BOLD}▶ $category${C_RESET}"
    echo "────────────────────────────────────────"

    local category_failed=0

    for test_file in "${tests[@]}"; do
        if ! run_test_file "$test_file" "$category"; then
            ((category_failed++)) || true
        fi
    done

    return $category_failed
}

# Main execution
main() {
    local total_failed=0

    # Always run quick tests
    if ! run_category "Contract Tests (Fast)" "${QUICK_TESTS[@]}"; then
        ((total_failed++)) || true
    fi

    if ! $QUICK; then
        # Run display tests
        if ! run_category "Display Tests" "${DISPLAY_TESTS[@]}"; then
            ((total_failed++)) || true
        fi

        # Run server switch tests
        if ! run_category "Server Switch Tests" "${SERVER_TESTS[@]}"; then
            ((total_failed++)) || true
        fi

        # Run scenario tests
        if ! run_category "Scenario Tests" "${SCENARIO_TESTS[@]}"; then
            ((total_failed++)) || true
        fi
    fi

    # Summary
    echo ""
    echo -e "${C_BOLD}════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_BOLD}                         Summary${C_RESET}"
    echo -e "${C_BOLD}════════════════════════════════════════════════════════════${C_RESET}"
    echo ""
    echo -e "  ${C_GREEN}Passed:${C_RESET}  $TOTAL_PASSED"
    echo -e "  ${C_RED}Failed:${C_RESET}  $TOTAL_FAILED"
    echo -e "  ${C_YELLOW}Skipped:${C_RESET} $TOTAL_SKIPPED"
    echo ""

    if [[ $TOTAL_FAILED -eq 0 ]]; then
        echo -e "${C_GREEN}${C_BOLD}✓ All behavioral tests passed!${C_RESET}"
        return 0
    else
        echo -e "${C_RED}${C_BOLD}✗ Some tests failed${C_RESET}"
        return 1
    fi
}

main
