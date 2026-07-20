# Claude Tower Development Guidelines

Auto-generated from feature plans. **Last updated**: 2026-02-11

## Active Technologies

- Bash 4.0+ (POSIX compatible shell scripts) + tmux 3.2+, git (optional) (001-tower-v2-simplify)
- File-based storage (`~/.claude-tower/metadata/*.meta`) (001-tower-v2-simplify)

## Project Structure

```text
tmux-plugin/
  scripts/     # CLI and UI scripts (tower, session-add.sh, navigator-list.sh, etc.)
  lib/         # Core libraries (common.sh, error-recovery.sh)
  conf/        # tmux configuration
tests/
  integration/ # Integration tests (bats)
  e2e/         # End-to-end tests (bats)
  scenarios/   # Test scenario data
specs/         # Feature specifications (spec-kit)
.specify/      # spec-kit config, templates, scripts
.github/       # CI/CD (GitHub Actions)
```

## Commands

```bash
make test          # Run all bats tests
make lint          # Run shellcheck on all scripts
make lint-fix      # Show shellcheck suggestions with fixes
make format        # Check formatting with shfmt (dry-run)
make format-fix    # Format scripts with shfmt (in-place)
make reload        # Reload tmux plugin (run inside tmux)
make reset         # Kill servers, clear caches, reload
make status        # Show servers, sessions, state files
```

## Code Style

- ShellCheck compliant (exclude SC2034, SC1091, SC2317)
- 4-space indentation (shfmt -i 4 -ci)
- Internal functions prefixed with underscore: `_internal_func()`
- Error handling via `handle_error` / `error_log` from lib/error-recovery.sh
- Input validation via `sanitize_name` / `validate_*` from lib/common.sh
- Files under 500 lines

## Testing

- Framework: bats (Bash Automated Testing System), submodule at tests/bats/
- Run single test: `./tests/bats/bin/bats tests/test_metadata.bats`
- Integration/E2E tests MUST set `CLAUDE_TOWER_SESSION_SOCKET` and `TMUX_TMPDIR` BEFORE `source_common`
- CI: GitHub Actions with 5 jobs (Unit, Integration, E2E, Docker, ShellCheck)

## Key API (v2)

- `create_session(name, dir)` -- 2 args
- `save_metadata(session_id, directory_path)` -- 2 args
- `load_metadata()` sets `META_DIRECTORY_PATH`
- v1 compat: `load_metadata` resolves priority: directory_path > worktree_path > repository_path

## Recent Changes

- 001-tower-v2-simplify: Simplified session management, removed worktree logic, added tower CLI (add/rm)

<!-- MANUAL ADDITIONS START -->
# important-instruction-reminders
Do what has been asked; nothing more, nothing less.
NEVER create files unless they're absolutely necessary for achieving your goal.
ALWAYS prefer editing an existing file to creating a new one.
NEVER proactively create documentation files (*.md) or README files. Only create documentation files if explicitly requested by the User.
Never save working files, text/mds and tests to the root folder.
<!-- MANUAL ADDITIONS END -->
