# Claude Tower - Development Makefile
# Usage: make <target>

.PHONY: help lint lint-fix format format-fix \
        test test-unit test-integration test-e2e test-scenarios \
        test-docker test-unit-docker test-integration-docker test-e2e-docker \
        test-scenarios-docker test-file-docker test-shell-docker \
        fuzz fuzz-docker fuzz-random-docker fuzz-smart-docker fuzz-scenarios-docker \
        check ci \
        clean reload reset status

# Default target
help:
	@echo "Claude Tower - Available targets:"
	@echo ""
	@echo "  Development:"
	@echo "    make reload     - Reload tmux plugin"
	@echo "    make reset      - Kill Navigator, clear caches, reload"
	@echo "    make status     - Show servers, sessions, state files"
	@echo ""
	@echo "  Linting & Formatting:"
	@echo "    make lint       - Run shellcheck on all scripts"
	@echo "    make lint-fix   - Show shellcheck suggestions with fixes"
	@echo "    make format     - Format scripts with shfmt (dry-run)"
	@echo "    make format-fix - Format scripts with shfmt (in-place)"
	@echo ""
	@echo "  Testing:"
	@echo "    make test             - Run unit + integration + e2e tests"
	@echo "    make test-unit        - Run unit tests only (bats tests/*.bats)"
	@echo "    make test-integration - Run integration tests (tests/integration/)"
	@echo "    make test-e2e         - Run end-to-end tests (tests/e2e/)"
	@echo "    make test-scenarios   - Run scenario tests (tests/scenarios/)"
	@echo ""
	@echo "  Testing in Docker (isolated from host tmux/state):"
	@echo "    make test-docker              - All suites inside container"
	@echo "    make test-unit-docker         - Unit suite only"
	@echo "    make test-integration-docker  - Integration suite only"
	@echo "    make test-e2e-docker          - E2E suite only"
	@echo "    make test-scenarios-docker    - Scenario suite only"
	@echo "    make test-file-docker FILE=…  - Run a specific .bats file/dir"
	@echo "    make test-shell-docker        - Drop into a shell in the test container"
	@echo ""
	@echo "  Fuzz testing (monkey-style exploratory, Docker-isolated):"
	@echo "    make fuzz-docker              - Run all fuzz modes in container"
	@echo "    make fuzz-random-docker       - Pure-random key fuzz"
	@echo "    make fuzz-smart-docker        - Legal + trash key fuzz"
	@echo "    make fuzz-scenarios-docker    - Hand-picked bad sequences"
	@echo "    make fuzz                     - Same on the host (uses isolated sockets)"
	@echo ""
	@echo "  Aggregate (CI gate):"
	@echo "    make check      - Run lint + format + all tests (local CI gate)"
	@echo "    make ci         - Alias for 'make check'"
	@echo ""
	@echo "  Docker image:"
	@echo "    make docker-lint  - Build lint Docker image"
	@echo "    make docker-test  - Build test Docker image"
	@echo ""
	@echo "  Cleanup:"
	@echo "    make clean      - Remove Docker images"

# Scripts to check
SCRIPTS := $(shell find tmux-plugin -name "*.sh" -type f) $(shell find tmux-plugin/bin -type f 2>/dev/null)

# ============================================================================
# Linting
# ============================================================================

# Run shellcheck locally (if available) or via Docker
lint:
	@if command -v shellcheck >/dev/null 2>&1; then \
		echo "Running shellcheck locally..."; \
		shellcheck -x $(SCRIPTS); \
	else \
		echo "Running shellcheck via Docker..."; \
		docker run --rm -v "$(PWD):/app" -w /app koalaman/shellcheck:stable -x $(SCRIPTS); \
	fi

# Run shellcheck with suggested fixes
lint-fix:
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck -x -f diff $(SCRIPTS) || true; \
	else \
		docker run --rm -v "$(PWD):/app" -w /app koalaman/shellcheck:stable -x -f diff $(SCRIPTS) || true; \
	fi

# ============================================================================
# Formatting
# ============================================================================

# Check formatting (dry-run)
format:
	@if command -v shfmt >/dev/null 2>&1; then \
		echo "Checking format with shfmt..."; \
		shfmt -d -i 4 -ci $(SCRIPTS); \
	else \
		echo "Running shfmt via Docker..."; \
		docker run --rm -v "$(PWD):/app" -w /app mvdan/shfmt:latest -d -i 4 -ci $(SCRIPTS); \
	fi

# Apply formatting (in-place)
format-fix:
	@if command -v shfmt >/dev/null 2>&1; then \
		echo "Formatting with shfmt..."; \
		shfmt -w -i 4 -ci $(SCRIPTS); \
	else \
		echo "Running shfmt via Docker..."; \
		docker run --rm -v "$(PWD):/app" -w /app mvdan/shfmt:latest -w -i 4 -ci $(SCRIPTS); \
	fi

# ============================================================================
# Testing
# ============================================================================

# Bats binary: prefer the project's vendored copy, fall back to PATH.
BATS := $(shell [ -x tests/bats/bin/bats ] && echo tests/bats/bin/bats || echo bats)

# Unit tests live directly under tests/ (top-level *.bats files only).
test-unit:
	@echo "=== Unit tests (tests/*.bats) ==="
	@$(BATS) tests/

# Integration tests use the dedicated runner (sets up tmux fixtures).
test-integration:
	@echo "=== Integration tests (tests/integration/) ==="
	@./tests/run_integration_tests.sh

# E2E tests use the dedicated runner.
test-e2e:
	@echo "=== E2E tests (tests/e2e/) ==="
	@./tests/run_e2e_tests.sh

# Scenario tests live under tests/scenarios/.
test-scenarios:
	@echo "=== Scenario tests (tests/scenarios/) ==="
	@$(BATS) tests/scenarios/

# Run the full test suite (unit + integration + e2e + scenarios).
test: test-unit test-integration test-e2e test-scenarios
	@echo ""
	@echo "✓ All test suites passed"

# Local CI gate: lint + format check + full test suite.
# Mirrors what CI runs so a clean local 'make check' should mean a green PR.
check: lint format test
	@echo ""
	@echo "✓ check passed (lint + format + test)"

ci: check

# ============================================================================
# Containerized tests
# ============================================================================
# Common docker-compose invocation. `run --rm` ensures the container is
# removed after each run so /tmp state from one suite never carries over.
DOCKER_TEST := docker compose -f docker-compose.test.yml run --rm tests

# Run the entire test suite in a container.
test-docker:
	@$(DOCKER_TEST) all

# Run a single suite in a container.
test-unit-docker:
	@$(DOCKER_TEST) unit

test-integration-docker:
	@$(DOCKER_TEST) integration

test-e2e-docker:
	@$(DOCKER_TEST) e2e

test-scenarios-docker:
	@$(DOCKER_TEST) scenarios

# Run a single test file or directory in a container.
# Usage: make test-file-docker FILE=tests/integration/test_session_restore.bats
test-file-docker:
	@if [ -z "$(FILE)" ]; then \
		echo "Usage: make test-file-docker FILE=<path-to-.bats-file-or-dir>"; \
		exit 1; \
	fi
	@$(DOCKER_TEST) $(FILE)

# Drop into an interactive shell inside the test container for debugging.
test-shell-docker:
	@docker compose -f docker-compose.test.yml run --rm --entrypoint /bin/bash tests

# ============================================================================
# Fuzz / monkey testing
# ============================================================================
# All fuzz runs use isolated per-PID tmux sockets so they never touch the
# host's real tmux. The Docker variants add an extra layer of isolation —
# the entire fuzz run lives in a throwaway container.

fuzz:
	@./tests/fuzz/run-fuzz.sh

fuzz-docker:
	@$(DOCKER_TEST) fuzz all

fuzz-random-docker:
	@$(DOCKER_TEST) fuzz random

fuzz-smart-docker:
	@$(DOCKER_TEST) fuzz smart

fuzz-scenarios-docker:
	@$(DOCKER_TEST) fuzz scenarios

# ============================================================================
# Docker Build
# ============================================================================

docker-lint:
	docker build -f Dockerfile.lint -t claude-tower-lint .

docker-test:
	docker build -f Dockerfile.test -t claude-tower-test .

# ============================================================================
# Development
# ============================================================================

# Reload tmux plugin (run inside tmux)
reload:
	@if [ -n "$$TMUX" ]; then \
		tmux run-shell "$(PWD)/tmux-plugin/claude-tower.tmux" && \
		echo "✓ Plugin reloaded"; \
	else \
		echo "Error: Run inside tmux session"; \
		exit 1; \
	fi

# Reset: kill Navigator and Session servers, clear caches, reload plugin
reset:
	@echo "=== Killing Navigator server ==="
	@tmux -L claude-tower kill-server 2>/dev/null && echo "✓ Navigator killed" || echo "  (not running)"
	@echo "=== Killing Session server ==="
	@tmux -L claude-tower-sessions kill-server 2>/dev/null && echo "✓ Session server killed" || echo "  (not running)"
	@echo "=== Clearing state files ==="
	@rm -rf /tmp/claude-tower && mkdir -p /tmp/claude-tower && echo "✓ State cleared"
	@echo "=== Reloading plugin ==="
	@if [ -n "$$TMUX" ]; then \
		tmux run-shell "$(PWD)/tmux-plugin/claude-tower.tmux" && \
		echo "✓ Plugin reloaded"; \
	else \
		echo "  (not in tmux, skipping reload)"; \
	fi
	@echo "=== Done ==="

# Show status of servers, sessions, and state files
status:
	@echo "=== Navigator Server (claude-tower) ==="
	@tmux -L claude-tower list-sessions 2>/dev/null || echo "  (not running)"
	@echo ""
	@echo "=== Session Server (claude-tower-sessions) ==="
	@tmux -L claude-tower-sessions list-sessions 2>/dev/null || echo "  (not running)"
	@echo ""
	@echo "=== State Files (/tmp/claude-tower/) ==="
	@if [ -d /tmp/claude-tower ]; then \
		ls -la /tmp/claude-tower/ 2>/dev/null || echo "  (empty)"; \
		echo ""; \
		echo "--- Contents ---"; \
		for f in /tmp/claude-tower/*; do \
			if [ -f "$$f" ]; then \
				echo "$$f:"; \
				cat "$$f" 2>/dev/null | head -3; \
				echo ""; \
			fi; \
		done; \
	else \
		echo "  (directory not found)"; \
	fi
	@echo ""
	@echo "=== Metadata Files (~/.claude-tower/sessions/) ==="
	@if [ -d ~/.claude-tower/sessions ]; then \
		ls ~/.claude-tower/sessions/*.meta 2>/dev/null | head -10 || echo "  (no metadata)"; \
	else \
		echo "  (directory not found)"; \
	fi

# ============================================================================
# Cleanup
# ============================================================================

clean:
	docker rmi claude-tower-lint claude-tower-test 2>/dev/null || true
