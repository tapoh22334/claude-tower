#!/usr/bin/env bash
# Run all tests (unit, integration, e2e)
#
# Usage:
#   ./tests/run_all_tests.sh           # Run all tests
#   ./tests/run_all_tests.sh --docker  # Run in Docker

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

run_docker() {
    echo -e "${BLUE}Running all tests in Docker...${NC}"
    cd "$PROJECT_ROOT"
    docker build -f Dockerfile.test -t claude-tower-test .
    docker run --rm claude-tower-test bash -c "
        ./tests/run_tests.sh && \
        ./tests/run_integration_tests.sh && \
        ./tests/run_e2e_tests.sh
    "
}

run_local() {
    local failed=0

    echo -e "${BLUE}=== Unit Tests ===${NC}"
    if "$SCRIPT_DIR/run_tests.sh"; then
        echo -e "${GREEN}Unit tests passed${NC}"
    else
        echo -e "${RED}Unit tests failed${NC}"
        failed=1
    fi

    echo ""
    echo -e "${BLUE}=== Integration Tests ===${NC}"
    if "$SCRIPT_DIR/run_integration_tests.sh"; then
        echo -e "${GREEN}Integration tests passed${NC}"
    else
        echo -e "${RED}Integration tests failed${NC}"
        failed=1
    fi

    echo ""
    echo -e "${BLUE}=== E2E Tests ===${NC}"
    if "$SCRIPT_DIR/run_e2e_tests.sh"; then
        echo -e "${GREEN}E2E tests passed${NC}"
    else
        echo -e "${RED}E2E tests failed${NC}"
        failed=1
    fi

    echo ""
    if [[ $failed -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
    else
        echo -e "${RED}Some tests failed.${NC}"
        exit 1
    fi
}

main() {
    if [[ "${1:-}" == "--docker" ]]; then
        run_docker
    else
        run_local
    fi
}

main "$@"
