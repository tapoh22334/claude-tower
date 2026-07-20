# Claude Tower Test Suite

This directory contains the comprehensive test suite for Claude Tower.

## Test Structure

```
tests/
├── Unit Tests (top-level *.bats)
│   ├── test_validation.bats        # Input validation functions
│   ├── test_sanitize.bats          # Sanitization and XSS prevention
│   ├── test_error_handling.bats    # Error handlers
│   ├── test_error_recovery.bats    # TUI error recovery
│   ├── test_metadata.bats          # Metadata (.meta registry) operations
│   ├── test_safe_wrappers.bats     # Safe command wrappers
│   ├── test_navigator.bats         # Navigator state management
│   ├── test_dependencies.bats      # Dependency checking
│   ├── test_server_separation.bats # TMUX= prefix validation
│   ├── test_ensure_tower_prefix.bats # tower_ id prefixing/validation
│   ├── test_claude_sessions.bats   # jsonl transcript parsing, busy detection
│   ├── test_display_state.bats     # 5-state (busy/active/dormant/dead/lost)
│   ├── test_session_add.bats       # session-add.sh add/new flow
│   └── test_coverage_gaps*.bats    # Incremental coverage additions
│
├── Integration Tests (requires tmux)
│   └── integration/
│       ├── test_tmux_integration.bats    # Real tmux interactions
│       ├── test_idempotent.bats          # Idempotent operations
│       ├── test_navigation_contract.bats # State contracts
│       ├── test_display_snapshot.bats    # Display verification
│       └── test_server_switch.bats       # Server switching
│
├── Scenario Tests
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

### Scenario Tests
```bash
bats tests/scenarios/
```

## Writing Tests

Tests use the [Bats](https://github.com/bats-core/bats-core) testing framework.

### Test Naming Convention
```bash
@test "category: description" {
    # test body
}
```

Categories: `integration:`, `idempotent:`, `contract:`, `scenario-*:`

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

Scripts without dedicated unit test files (exercised indirectly via
`common.sh`/`claude-sessions.sh` function tests and the scenario tests):
- `tile.sh`
- `session-delete.sh`, `session-restore.sh`, `session-list.sh`
- `navigator.sh`, `navigator-view.sh`

See `/docs/development/GAP_ANALYSIS.md` for further coverage analysis
(may not fully reflect the current session-registry model).
