#!/usr/bin/env bash
# Docker entrypoint for claude-tower tests.
#
# Usage:
#   docker run claude-tower-test                                 # all suites
#   docker run claude-tower-test all                             # explicit all
#   docker run claude-tower-test unit                            # one suite
#   docker run claude-tower-test integration
#   docker run claude-tower-test e2e
#   docker run claude-tower-test scenarios
#   docker run claude-tower-test tests/path/to/test.bats         # one file
#   docker run claude-tower-test tests/integration/              # a dir
#   docker run claude-tower-test -f "restore" tests/             # bats flags
#
# The first argument acts as a sub-command if it matches a known suite name;
# otherwise it is forwarded as-is to bats.

set -euo pipefail
cd /app

# Prefer the vendored bats so the test runner matches what
# `make test` uses on a developer's host.
if [[ -x /app/tests/bats/bin/bats ]]; then
    BATS=/app/tests/bats/bin/bats
else
    BATS=bats
fi

run_unit()        { "$BATS" tests/; }
run_integration() { ./tests/run_integration_tests.sh; }
run_e2e()         { ./tests/run_e2e_tests.sh; }
run_scenarios()   { "$BATS" tests/scenarios/; }

run_all() {
    local fail=0
    echo "=== Unit ==="          && run_unit        || fail=1
    echo "=== Integration ===" && run_integration || fail=1
    echo "=== E2E ==="          && run_e2e        || fail=1
    echo "=== Scenarios ==="    && run_scenarios  || fail=1
    return "$fail"
}

case "${1:-all}" in
    all)         run_all ;;
    unit)        run_unit ;;
    integration) run_integration ;;
    e2e)         run_e2e ;;
    scenarios)   run_scenarios ;;
    help|-h|--help)
        sed -n '1,18p' "$0"
        ;;
    *)
        # Pass through to bats as a file/dir path or bats flag.
        "$BATS" "$@"
        ;;
esac
