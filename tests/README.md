# Claude Tower Test Suite

This directory contains the comprehensive test suite for Claude Tower.

## Test Structure

```
tests/
├── Unit Tests (8 files, ~174 tests)
│   ├── test_validation.bats      # Input validation functions
│   ├── test_sanitize.bats        # Sanitization and XSS prevention
│   ├── test_error_handling.bats  # Error handlers
│   ├── test_metadata.bats        # Metadata operations
│   ├── test_orphan.bats          # Orphan worktree detection
│   ├── test_safe_wrappers.bats   # Safe command wrappers
│   ├── test_navigator.bats       # Navigator state management
│   ├── test_dependencies.bats    # Dependency checking
│   └── test_server_separation.bats # TMUX= prefix validation
│
├── Integration Tests (4 files, ~58 tests)
│   └── integration/
│       ├── test_tmux_integration.bats    # Real tmux interactions
│       ├── test_idempotent.bats          # Idempotent operations
│       ├── test_navigation_contract.bats # State contracts
│       ├── test_display_snapshot.bats    # Display verification
│       └── test_server_switch.bats       # Server switching
│
├── E2E Tests (1 file, ~5 tests)
│   └── e2e/
│       └── test_workspace_workflow.bats  # Full workspace lifecycle
│
├── Scenario Tests (1 file + 2 scenarios, ~13 tests)
│   └── scenarios/
│       ├── 01_basic_session.md           # Basic session scenario
│       ├── 02_workspace_session.md       # Workspace scenario
│       ├── test_scenarios.bats           # Scenario validation
│       └── run_scenario.sh               # Scenario runner
│
├── test_helper.bash              # Shared test utilities
└── run_*.sh                      # Test runners
```

## Running Tests

### All Unit Tests
```bash
make test
# or
./tests/run_behavioral_tests.sh
```

### Specific Test File
```bash
bats tests/test_navigator.bats
```

### Integration Tests (requires tmux)
```bash
bats tests/integration/
```

### E2E Tests (requires full tmux environment)
```bash
bats tests/e2e/
```

## Test Coverage Summary

| Layer | Estimated Coverage |
|-------|-------------------|
| Unit (common.sh functions) | ~75% |
| Integration (tmux interaction) | ~60% |
| E2E (full workflows) | ~40% |
| Scenario (user flows) | ~50% |
| **Overall Estimate** | **~55-60%** |

## Writing Tests

Tests use the [Bats](https://github.com/bats-core/bats-core) testing framework.

### Test Naming Convention
```bash
@test "category: description" {
    # test body
}
```

Categories: `integration:`, `idempotent:`, `contract:`, `e2e:`, `scenario-*:`

### Using test_helper.bash
```bash
load test_helper

setup() {
    setup_test_environment
}

teardown() {
    cleanup_test_environment
}
```

## Known Gaps

Scripts without dedicated tests:
- `tile.sh`, `cleanup.sh`, `diff.sh`, `help.sh`
- `session-delete.sh`, `session-restore.sh`
- `sidebar.sh`, `statusline.sh`, `tree-view.sh`

See `/docs/development/GAP_ANALYSIS.md` for full coverage analysis.
