# Claude Tower Principles

The rules the codebase is held to. Written under a spec-kit workflow that the
project no longer runs; the principles outlived it.

## Core Principles

### I. Session-Only Responsibility
Tower manages Claude Code sessions exclusively. It MUST NOT create, modify, or delete user directories or git worktrees. Directories are referenced, never managed.

### II. Zero External Dependencies
All functionality is implemented in Bash 4.0+ with tmux 3.2+ as the only runtime dependency. Git is optional. No Python, Node.js, or other runtimes are required.

### III. Test-First Development
TDD mandatory: Tests written and failing before implementation. Use bats (Bash Automated Testing System). Integration and E2E tests must use tmux socket isolation (CLAUDE_TOWER_SESSION_SOCKET + TMUX_TMPDIR set BEFORE source_common).

### IV. Backward Compatibility
Metadata format changes must preserve the ability to read older files.
`load_metadata` ignores keys it does not recognise, which is what makes an
older `.meta` still load. Removing a key that older versions wrote is a
breaking change and belongs in the README.

### V. Simplicity and Performance
Start simple, YAGNI principles. ShellCheck and shfmt compliance enforced.

Keep files under 500 lines. Four exceed it today — `navigator-list.sh` (1245),
`common.sh` (1164), `claude-sessions.sh` (707), `error-recovery.sh` (507) —
and that is a debt, not a dispensation: each has grown to hold several
concerns. Do not add to them without splitting something out.

Interactive work is measured, not assumed. The session list rebuild is the
expensive path (it reads every transcript), so it runs on a timer in the
background rather than in the key loop; a keystroke must never wait on it.
When touching that path, count processes — `strace -f -e trace=execve` — since
in Bash the cost is almost always fork/exec, not logic.

## Development Constraints

- Target platforms: Linux, macOS
- Shell: Bash 4.0+ (POSIX compatible)
- Testing: bats with tests/ directory structure (unit, integration, e2e, scenarios)
- CI: GitHub Actions (4 jobs: Unit, Integration, Docker, ShellCheck)
- Storage: File-based metadata at ~/.claude-tower/metadata/*.meta
- Linting: ShellCheck (see `.shellcheckrc`), shfmt (4-space indent)

## Quality Gates

- All PRs must pass: `make lint`, `make test`
- ShellCheck violations are blocking (except excluded codes)
- Integration tests must not hang (socket isolation required)
- New CLI behaviour is documented in the README, not in a separate spec

## Governance

These principles take precedence over local convenience. Changing one is a
deliberate act — say why in the commit that changes it.
