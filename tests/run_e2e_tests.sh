#!/usr/bin/env bash
# E2E test runner for claude-tower
#
# Usage:
#   ./tests/run_e2e_tests.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

check_prerequisites() {
    local missing=()
    for cmd in tmux git; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done

    if ! command -v bats &>/dev/null; then
        [[ -x "${PROJECT_ROOT}/tests/bats/bin/bats" ]] && \
            export PATH="${PROJECT_ROOT}/tests/bats/bin:$PATH" || missing+=("bats")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${RED}Missing: ${missing[*]}${NC}"
        exit 1
    fi
}

main() {
    echo -e "${BLUE}Running claude-tower E2E tests...${NC}"
    check_prerequisites

    [[ ! -d "${SCRIPT_DIR}/e2e" ]] && { echo "No E2E tests found"; exit 0; }

    local bats_args=()

    # Use TAP format in CI (no terminal), pretty format locally
    if [[ -t 1 ]] && [[ -z "${CI:-}" ]]; then
        bats_args+=(--pretty)
    else
        bats_args+=(--tap)
    fi

    [[ "${CLAUDE_TOWER_DEBUG:-0}" == "1" ]] && bats_args+=(--verbose-run)
    bats_args+=("${SCRIPT_DIR}/e2e/"*.bats)

    cd "$SCRIPT_DIR"
    if bats "${bats_args[@]}"; then
        echo -e "${GREEN}All E2E tests passed!${NC}"
    else
        echo -e "${RED}Some E2E tests failed.${NC}"
        exit 1
    fi
}

main "$@"
