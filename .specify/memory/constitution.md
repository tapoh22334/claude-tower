# Claude Tower Constitution

## Core Principles

### I. Session-Only Responsibility
Tower manages Claude Code sessions exclusively. It MUST NOT create, modify, or delete user directories or git worktrees. Directories are referenced, never managed.

### II. Zero External Dependencies
All functionality is implemented in Bash 4.0+ with tmux 3.2+ as the only runtime dependency. Git is optional. No Python, Node.js, or other runtimes are required.

### III. Test-First Development
TDD mandatory: Tests written and failing before implementation. Use bats (Bash Automated Testing System). Integration and E2E tests must use tmux socket isolation (CLAUDE_TOWER_SESSION_SOCKET + TMUX_TMPDIR set BEFORE source_common).

### IV. Backward Compatibility
Metadata format changes must preserve ability to read older formats. load_metadata() must handle v1 fields (worktree_path, repository_path) gracefully. Breaking changes require migration documentation in README.

### V. Simplicity and Performance
Start simple, YAGNI principles. CLI responses under 100ms. Files under 500 lines. ShellCheck and shfmt compliance enforced.

## Development Constraints

- Target platforms: Linux, macOS
- Shell: Bash 4.0+ (POSIX compatible)
- Testing: bats with tests/ directory structure (unit, integration, e2e, scenarios)
- CI: GitHub Actions (5 jobs: Unit, Integration, E2E, Docker, ShellCheck)
- Storage: File-based metadata at ~/.claude-tower/metadata/*.meta
- Linting: ShellCheck (exclude SC2034, SC1091, SC2317), shfmt (4-space indent)

## Quality Gates

- All PRs must pass: `make lint`, `make test`
- ShellCheck violations are blocking (except excluded codes)
- Integration tests must not hang (socket isolation required)
- New CLI commands require contract documentation in specs/NNN-feature/contracts/

## Governance

Constitution supersedes all other practices. Amendments require documentation and review. All specs must include a "Constitution Check" gate that verifies compliance with these principles.

**Version**: 1.0.0 | **Ratified**: 2026-02-11 | **Last Amended**: 2026-02-11
