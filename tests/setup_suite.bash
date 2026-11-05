#!/usr/bin/env bash
# Suite-level hooks. bats picks this file up from the directory of the test
# files it runs; tests/integration and tests/e2e source it from theirs.
#
# teardown_test_env removes the run's fixture root after each test, but any
# test that writes a fixture without calling it (or a later test that
# recreates the root) leaves tests/tmp/run-<id> behind. Those piled up by the
# dozen, and a fixture symlink to /tmp once made `bats -r tests` recurse into
# /tmp and never finish (#119). Removing the root once more after the last
# file has run catches every such path.

setup_suite() {
    :
}

teardown_suite() {
    [[ -n "${BATS_RUN_TMPDIR:-}" ]] || return 0
    local tests_dir
    tests_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    rm -rf "${tests_dir}/tmp/run-${BATS_RUN_TMPDIR##*/}"
}
