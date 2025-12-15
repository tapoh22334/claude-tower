# LLM Automated Test Scenarios

This directory contains test scenarios designed to be executed by LLM agents (like Claude Code).

## How to Use

An LLM agent can read these scenario files and execute the described steps, verifying the expected outcomes.

## Scenario Format

Each scenario file follows this structure:

```yaml
name: Scenario Name
description: What this scenario tests
preconditions:
  - List of required conditions
steps:
  - Step 1 description
  - Step 2 description
expected:
  - Expected outcome 1
  - Expected outcome 2
cleanup:
  - Cleanup step 1
```

## Running Scenarios

### Manual (via LLM)
Ask an LLM agent: "Run the test scenario in tests/scenarios/01_basic_session.md"

### Automated
```bash
./tests/run_scenario_tests.sh
```
