# Design notes

User documentation lives in the [top-level README](../README.md). What is here
is background: why the code is shaped the way it is.

| | |
|---|---|
| [PRINCIPLES.md](./PRINCIPLES.md) | The rules the codebase is held to — Bash-only, TDD, file size limits |
| [architecture/DESIGN_PHILOSOPHY.md](./architecture/DESIGN_PHILOSOPHY.md) | The reasoning behind the UI and session model |
| [architecture/socket-separation.md](./architecture/socket-separation.md) | Why Tower runs its own tmux servers instead of yours |
| [architecture/error-handling.md](./architecture/error-handling.md) | How the Navigator survives a failing session |

Everything else that used to be here described the pre-v4 worktree model and
was removed; `git log` has it if you need it.
