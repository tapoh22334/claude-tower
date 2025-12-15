#!/usr/bin/env bash
# Integration test runner for claude-tower
# Requires tmux to be installed and working
#
# Usage:
#   ./tests/run_integration_tests.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check prerequisites
check_prerequisites() {
    local missing=()

    if ! command -v tmux &>/dev/null; then
        missing+=("tmux")
    fi

    if ! command -v bats &>/dev/null; then
        if [[ -x "${PROJECT_ROOT}/tests/bats/bin/bats" ]]; then
            export PATH="${PROJECT_ROOT}/tests/bats/bin:$PATH"
        else
            missing+=("bats")
        fi
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${RED}Missing prerequisites: ${missing[*]}${NC}"
        echo "Please install them to run integration tests."
        exit 1
    fi
}

# Main
main() {
    echo -e "${BLUE}Running claude-tower integration tests...${NC}"
    echo ""

    check_prerequisites

    # Check if integration tests directory exists
    if [[ ! -d "${SCRIPT_DIR}/integration" ]]; then
        echo -e "${YELLOW}No integration tests found in ${SCRIPT_DIR}/integration${NC}"
        exit 0
    fi

    # Run integration tests
    local bats_args=(--pretty)

    if [[ "${CLAUDE_TOWER_DEBUG:-0}" == "1" ]]; then
        bats_args+=(--verbose-run)
    fi

    bats_args+=("${SCRIPT_DIR}/integration/"*.bats)

    cd "$SCRIPT_DIR"
    if bats "${bats_args[@]}"; then
        echo ""
        echo -e "${GREEN}All integration tests passed!${NC}"
        exit 0
    else
        echo ""
        echo -e "${RED}Some integration tests failed.${NC}"
        exit 1
    fi
}

main "$@"
