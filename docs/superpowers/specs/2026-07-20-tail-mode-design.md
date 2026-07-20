# Tail mode — live multi-session output follow

2026-07-20. Status: approved provisionally under full-auto (user veto welcome).

## Background

The user remembers a "tail mode" that no longer exists. Repository history
(all 164 commits) contains no such mode — it most likely only existed as a
design inside a June fork session whose transcript is gone. This spec
recreates it as a new feature.

## Purpose

Watch what every session is printing, live, without touching the keyboard.
Complements the existing views:

| view | question it answers | refresh |
|---|---|---|
| List | which sessions exist, in what state? | 2s (list only) |
| Tile | what is each session showing? (grid snapshot) | on keypress |
| **Tail** | **what is happening right now, everywhere?** | **auto, every 2s** |

## UX

- Entered from the Navigator list view with `t`. Footer/help updated.
- Full screen (alt screen), sessions stacked vertically, newest-activity
  order as returned by `list_all_sessions`.
- Each block: one header line `⠋ name  (state)` (selected block's header
  reverse-video) followed by the last N lines of live pane output
  (`capture-pane`), dimmed. Dormant/dead/lost sessions show a one-line
  placeholder instead of output.
- Output lines per block adapt to terminal height: blocks share the space
  equally (min 2 output lines each); blocks that do not fit are summarized
  as a `+N more` line. The frame never exceeds the terminal height and the
  last line has no trailing newline (regression class: the list-view
  endless-scroll bug).
- Keys, consistent with Tile: `j/k` move selection, `g/G` first/last,
  `1-9` select + return to list, `Enter`/`Tab` return to list keeping the
  selection, `q` quit Navigator. No `r`: the whole point is auto-refresh
  (`read -rsn1 -t 2` drives the loop).

## Architecture

New script `tmux-plugin/scripts/tail-view.sh`, modeled on `tile.sh`
(load via `list_all_sessions`, quit/return handoff identical), with two
deliberate differences:

1. **Auto-refresh loop** — `read -rsn1 -t $REFRESH_INTERVAL` instead of a
   blocking read; on timeout, reload sessions and redraw.
2. **Atomic frame rendering** — one `printf '\033[H%b%s'` frame with
   per-line `\033[K` and a final `ED`, exactly like `render_list`, instead
   of `tput clear` + cursor jumping (avoids flicker at 2s cadence).
3. **Sourcing guard** — `[[ ${BASH_SOURCE[0]} == "$0" ]]` around `main`,
   so bats can source the script and unit-test the pure functions
   (the repo has wanted this guard elsewhere; this script starts with it).

`navigator-list.sh` gains `switch_to_tail()` (copy of `switch_to_tile`
pointing at tail-view.sh) and a `t` key binding.

Frame composition is split into a pure function `build_tail_frame` that
takes terminal dimensions as arguments and reads session data from arrays,
with `capture-pane` isolated behind `capture_tail_lines` so tests can stub
it.

## Testing

bats, sourcing tail-view.sh directly (guard makes this safe):

- frame line count never exceeds `term_height` (30 sessions, small height)
- last line has no trailing newline (SENTINEL technique)
- `+N more` appears when blocks don't fit
- dormant session renders placeholder, no capture-pane call
- key dispatch: `t` wired in navigator-list.sh (grep-level)

Full suite runs in Docker only (`make test-docker`).
