# CLI Contract: `tower`

**Feature**: 003-simplify
**Date**: 2026-06-03

This document is the authoritative reference for the `tower` CLI surface after the 003 redesign. It supersedes the surface implied by `tmux-plugin/bin/tower` prior to this feature.

## Final Command Surface

| Command | Behavior | Source script |
|---|---|---|
| `tower` | Launch Navigator (interactive). | `scripts/navigator.sh` |
| `tower navigator` | Same as `tower` (explicit form). | `scripts/navigator.sh` |
| `tower add <path> [-n name]` | Create a new session for the given directory. `-n` overrides the auto-generated name. | `scripts/session-add.sh` |
| `tower rm <name> [-f]` | Remove the named session. `-f` skips confirmation. Aliases: `tower remove`, `tower delete`. | `scripts/session-delete.sh` |
| `tower list [pretty\|json\|raw]` | Print all sessions. Default format: `pretty`. | `scripts/session-list.sh` |
| `tower restore [--all]` | Restore dormant sessions. With no argument and with `--all` behaves the same: all dormant sessions are restored. | `scripts/session-restore.sh` |
| `tower help`, `tower -h`, `tower --help` | Print help. | (built-in) |

## Removed Commands (compared to pre-003)

| Command | Removal reason | Replacement |
|---|---|---|
| `tower tile` | Tile view is no longer a top-level CLI command; it is reachable from Navigator via `Tab` only. (FR-012) | `tower` → press `Tab` |
| `tower restore <session_id>` | Per-session restore is no longer supported from CLI. (FR-013) | Use `tower restore` (all dormant) or restore from Navigator with `r` (single) / `R` (all) |

## Behavior Contract — Exit Codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | User error (missing arg, invalid path, etc.) |
| 2 | Internal error (metadata corrupt, tmux failure) |

## Behavior Contract — Stdout

| Command | Stdout |
|---|---|
| `add` | Confirmation line with session id |
| `rm` | Confirmation line; nothing if `-f` and silent operation |
| `list` | Session table in chosen format |
| `restore` | Per-session restore lines + summary |
| `help` | Multi-line help text |

## Behavior Contract — Help Text Requirements

The help text MUST list exactly the commands above. It MUST NOT list `tile` or document a per-id form of `restore`. The current Session States legend (`▶ Active` / `○ Dormant`) is retained.

## Navigator Key Contract

| Key | Action | New in 003? |
|---|---|---|
| `j` / `↓` | Move selection down | — |
| `k` / `↑` | Move selection up | — |
| `g` | Go to first session | — |
| `G` | Go to last session | — |
| `1`–`9` | Jump to Nth session (1-indexed); no-op if N > session count | **NEW** |
| `Enter` | Full attach to selected session (exit Navigator) | — |
| `i` | Focus right pane (input mode for selected session) | — |
| `n` | New session: inline prompt prefilled with caller CWD | **NEW** |
| `d` | Delete selected session: inline `[y/N]` confirmation | **NEW** |
| `r` | Restore selected dormant session | — |
| `R` | Restore all dormant sessions | — |
| `Tab` | Switch to Tile view | — |
| `?` | Show help | — |
| `q` / `Q` | Quit Navigator | — |

## Tile View Key Contract

| Key | Action | Change in 003? |
|---|---|---|
| `j` / `↓` | Move selection down (wraps) | — |
| `k` / `↑` | Move selection up (wraps) | — |
| `g` | First tile | — |
| `G` | Last tile | — |
| `1`–`9` | Select session AND enter input mode for it | **CHANGED** (was: return to list with selection) |
| `Enter` | Enter input mode for the j/k-selected tile | **CHANGED** (was: return to list with selection) |
| `Tab` | Return to Navigator list view | — |
| `q` / `Esc` | Quit Navigator | — |
| ~~`r`~~ | (removed — auto-refresh now) | **REMOVED** |

## Escape Semantics in Input Mode (right pane)

Pressing Escape inside input mode (whether entered via Navigator list `i`, Tile `1-9`, or Tile `Enter`) MUST return the user to the **Navigator list view**. This is the canonical "home" after input mode exit. To return to Tile, the user presses `Tab` from the list. (FR-009a)
