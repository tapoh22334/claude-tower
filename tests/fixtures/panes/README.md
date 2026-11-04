Pane captures of real Claude Code sessions (2.1.310, 2026-11-04), taken with
`tmux capture-pane -p`, blank lines dropped. Runs of 3+ spaces (right-aligned
timers) were squeezed to 3 and box rules cut to 40 columns; nothing else edited.

- main-idle-agent-running.txt   main waits at the prompt, one background agent runs
- main-working-with-agent.txt   main mid-turn, one background agent runs
- main-working-no-agent.txt     main mid-turn, no agents
- background-shell-only.txt     idle; only a background shell is still running (#85)
