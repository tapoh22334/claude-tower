# Contributing to Claude Tower

Thanks for taking an interest. Tower is a tmux plugin written entirely in
Bash, so the barrier to hacking on it is low: if you can read a shell script,
you can change one here.

## Getting set up

You need tmux 3.2+, bash 4.0+, the Claude Code CLI, and `bats` for the tests.
`fzf` is optional but makes the session picker much nicer.

```bash
git clone https://github.com/tapoh22334/claude-tower
cd claude-tower
bats --version   # any recent 1.x
```

Point your `~/.tmux.conf` at the clone to run your working copy:

```bash
run-shell /path/to/claude-tower/tmux-plugin/claude-tower.tmux
```

`make reload` re-reads the plugin without restarting tmux. `make reset` is the
bigger hammer — it kills Tower's servers and clears cached state.

## Before you open a pull request

```bash
make lint     # shellcheck
make format   # shfmt, dry-run — use format-fix to apply
make test     # the bats suites
```

CI runs unit, integration, and Docker test jobs plus shellcheck. Note that a
number of tests currently fail on a clean checkout; before you conclude your
change broke something, run the suite on `main` first and compare. If a
failure exists there too, it is not yours.

## How the code is arranged

```
tmux-plugin/scripts/   CLI entry points and UI (navigator, tile, tail views)
tmux-plugin/lib/       shared libraries — common.sh, claude-sessions.sh
tmux-plugin/conf/      tmux configuration fragments
tests/                 bats suites
```

`lib/common.sh` holds the shared helpers; `lib/claude-sessions.sh` is what
reads Claude's own transcripts under `~/.claude/projects/`. Most features
touch one script in `scripts/` and one helper in `lib/`.

## House style

- ShellCheck-clean (`SC2034`, `SC1091`, and `SC2317` are excluded project-wide)
- 4-space indent, formatted with `shfmt -i 4 -ci`
- Internal helpers get a leading underscore: `_do_the_thing()`
- Validate input through `sanitize_name` / `validate_*` from `lib/common.sh`
- Report failures through `handle_error` / `error_log` from `lib/error-recovery.sh`
- Keep files under 500 lines — when one grows past that, it is usually doing
  two jobs

Comments should explain *why*, especially where the code looks odd. Tower has
several places where the obvious implementation is wrong for a subtle reason
(terminal redraw ordering, nested tmux clients, transcript parsing), and those
comments are load-bearing. Please preserve and extend them rather than
tidying them away.

## Commits and pull requests

Write commit messages that say what changed and why it needed to change.
Conventional-commit prefixes (`fix:`, `feat:`, `docs:`, `chore:`) are used
throughout the history; following them keeps the log readable.

Keep a pull request to one concern. If you find an unrelated bug on the way,
that is a separate PR — or an issue, if you would rather leave it for someone
else.

## Reporting bugs

Tower coordinates three tmux servers and reads Claude's transcripts, so
reproduction details matter more than usual. Please include:

- tmux version (`tmux -V`) and OS
- what you pressed and what happened instead
- anything relevant from `~/.claude-tower/metadata/tower.log`
- output of `make status`

## Security

If you find something exploitable, please open a regular issue unless it lets
an attacker reach beyond the machine already running Tower — Tower runs
locally under your own user, so most of its attack surface is already inside
your trust boundary. For anything broader, contact the maintainer directly
rather than filing publicly.
