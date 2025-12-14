#!/usr/bin/env bash
# Test runner for claude-tower unit tests
#
# Usage:
#   ./tests/run_tests.sh           # Run all tests
#   ./tests/run_tests.sh sanitize  # Run specific test file
#   ./tests/run_tests.sh --tap     # Output in TAP format

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if bats is installed
check_bats() {
    if command -v bats &>/dev/null; then
        return 0
    fi

    # Check for bats in common locations
    if [[ -x "/usr/local/bin/bats" ]]; then
        return 0
    fi

    # Check for bats-core installed via git
    if [[ -d "${PROJECT_ROOT}/tests/bats" ]]; then
        export PATH="${PROJECT_ROOT}/tests/bats/bin:$PATH"
        return 0
    fi

    return 1
}

# Install bats if not available
install_bats() {
    echo -e "${YELLOW}bats not found. Installing bats-core...${NC}"

    if command -v apt-get &>/dev/null; then
        echo "Installing via apt..."
        sudo apt-get update && sudo apt-get install -y bats
    elif command -v brew &>/dev/null; then
        echo "Installing via brew..."
        brew install bats-core
    else
        echo "Installing bats-core from git..."
        git clone https://github.com/bats-core/bats-core.git "${PROJECT_ROOT}/tests/bats"
        export PATH="${PROJECT_ROOT}/tests/bats/bin:$PATH"
    fi
}

# Print usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS] [TEST_FILE]

Run claude-tower unit tests using bats.

Options:
    -h, --help      Show this help message
    --tap           Output in TAP format
    --verbose       Show all test output
    --filter REGEX  Only run tests matching REGEX

Test files:
    sanitize        Run sanitization function tests
    metadata        Run metadata function tests
    orphan          Run orphan detection tests

Examples:
    $0                      # Run all tests
    $0 sanitize             # Run only sanitize tests
    $0 --tap                # Run all tests with TAP output
    $0 --filter "path"      # Run tests with "path" in the name
EOF
}

# Main
main() {
    local tap_format=false
    local verbose=false
    local filter=""
    local test_file=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            --tap)
                tap_format=true
                shift
                ;;
            --verbose)
                verbose=true
                shift
                ;;
            --filter)
                filter="$2"
                shift 2
                ;;
            sanitize|metadata|orphan)
                test_file="test_${1}.bats"
                shift
                ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}"
                usage
                exit 1
                ;;
        esac
    done

    # Check/install bats
    if ! check_bats; then
        install_bats
        if ! check_bats; then
            echo -e "${RED}Failed to install bats. Please install it manually.${NC}"
            exit 1
        fi
    fi

    echo -e "${BLUE}Running claude-tower unit tests...${NC}"
    echo ""

    # Build bats arguments
    local bats_args=()

    if $tap_format; then
        bats_args+=(--tap)
    else
        bats_args+=(--pretty)
    fi

    if $verbose; then
        bats_args+=(--verbose-run)
    fi

    if [[ -n "$filter" ]]; then
        bats_args+=(--filter "$filter")
    fi

    # Determine which tests to run
    if [[ -n "$test_file" ]]; then
        bats_args+=("${SCRIPT_DIR}/${test_file}")
    else
        bats_args+=("${SCRIPT_DIR}"/test_*.bats)
    fi

    # Run tests
    cd "$SCRIPT_DIR"
    if bats "${bats_args[@]}"; then
        echo ""
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo ""
        echo -e "${RED}Some tests failed.${NC}"
        exit 1
    fi
}

main "$@"
