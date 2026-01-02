# Claude Tower - Development Makefile
# Usage: make <target>

.PHONY: help lint lint-fix format test test-docker clean

# Default target
help:
	@echo "Claude Tower - Available targets:"
	@echo ""
	@echo "  Linting & Formatting:"
	@echo "    make lint       - Run shellcheck on all scripts"
	@echo "    make lint-fix   - Show shellcheck suggestions with fixes"
	@echo "    make format     - Format scripts with shfmt (dry-run)"
	@echo "    make format-fix - Format scripts with shfmt (in-place)"
	@echo ""
	@echo "  Testing:"
	@echo "    make test       - Run all tests locally"
	@echo "    make test-docker- Run tests in Docker container"
	@echo ""
	@echo "  Docker:"
	@echo "    make docker-lint  - Build lint Docker image"
	@echo "    make docker-test  - Build test Docker image"
	@echo ""
	@echo "  Cleanup:"
	@echo "    make clean      - Remove Docker images"

# Scripts to check
SCRIPTS := $(shell find tmux-plugin -name "*.sh" -type f)

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

# Run tests locally
test:
	@echo "Running tests..."
	@bats tests/

# Run tests in Docker
test-docker: docker-test
	docker run --rm -it claude-tower-test

# ============================================================================
# Docker Build
# ============================================================================

docker-lint:
	docker build -f Dockerfile.lint -t claude-tower-lint .

docker-test:
	docker build -f Dockerfile.test -t claude-tower-test .

# ============================================================================
# Cleanup
# ============================================================================

clean:
	docker rmi claude-tower-lint claude-tower-test 2>/dev/null || true
