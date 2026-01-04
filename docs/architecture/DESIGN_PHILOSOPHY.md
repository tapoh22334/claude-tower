# Claude Tower Design Philosophy

> **Version**: 1.0
> **Date**: 2026-01-03
> **Status**: Active

---

## Overview

This document establishes the design philosophy guiding Claude Tower development. It synthesizes insights from comprehensive research into popular tmux plugins, Unix design principles, and modern software design practices to create a cohesive framework for decision-making.

---

## 1. Core Vision

### 1.1 Mission Statement

**Claude Tower exists to provide seamless orchestration of multiple Claude Code sessions within the terminal, respecting both the Unix philosophy and the user's existing tmux workflow.**

We believe that:
- The terminal is a first-class development environment
- AI-assisted coding should integrate naturally into existing workflows
- Tools should be composable, predictable, and transparent

### 1.2 Target Users

Claude Tower is designed for developers who:
- Work with multiple Claude Code sessions simultaneously
- Prefer keyboard-driven terminal workflows
- Value tmux's multiplexing capabilities
- Need session persistence across system restarts

### 1.3 What We Are NOT

We explicitly choose NOT to be:

| Anti-Goal | Rationale |
|-----------|-----------|
| A replacement for tmux | We extend tmux, not replace it |
| A general-purpose TUI framework | We use tmux's native capabilities |
| A tmux wrapper library | We provide end-user functionality, not APIs |
| A session manager for arbitrary programs | We focus on Claude Code integration |

---

## 2. Guiding Principles

Inspired by the Zen of Python, Unix Philosophy, and successful tmux plugins.

### 2.1 Primary Principles

#### Principle 1: tmux Native

> **"Use platform features, not abstractions over them."**

**Rationale**: Users already know tmux. Leverage their existing knowledge rather than introducing new paradigms.

**In Practice**:
- Navigator uses tmux panes, not a custom TUI framework
- Key bindings follow tmux conventions (prefix + key)
- State display uses tmux's format strings and status capabilities

**Inspiration**: Unix Rule of Least Surprise

---

#### Principle 2: Socket Separation

> **"Navigator lives in its own server, user sessions stay in theirs."**

**Rationale**: Control plane operations should never interfere with data plane activities.

**In Practice**:
- Navigator uses dedicated socket (`-L claude-tower`)
- User Claude sessions remain on default tmux server
- State files enable cross-server communication
- `TMUX=` prefix ensures correct server targeting

**Inspiration**: Microservices isolation principle

---

#### Principle 3: Visible State

> **"The user should always know where they are and what they can do."**

**Rationale**: Modal interfaces confuse when state is invisible. Transparency builds trust.

**In Practice**:
- Session states indicated by icons (▶ active, ! exited, ○ dormant)
- Session types shown ([W] worktree, [S] simple)
- Current focus position clearly highlighted
- Help available via `?` key in all modes

**Inspiration**: React's "Debugging Breadcrumbs" principle

---

#### Principle 4: Graceful Exits

> **"Every action should have a clear way back."**

**Rationale**: Users should feel safe to explore. Fear of getting stuck inhibits adoption.

**In Practice**:
- Escape always returns to a known state
- `q` always quits to caller session
- No operation without confirmation for destructive actions
- Error recovery shows context, not raw terminals

**Inspiration**: Apple HIG "Give users control"

---

#### Principle 5: Composition over Complexity

> **"Small focused scripts connected by clear interfaces."**

**Rationale**: Maintainability, testability, and Unix tradition.

**In Practice**:
- Entry point (`claude-tower.tmux`) only sets up bindings
- Feature scripts in `scripts/` directory
- Shared utilities in `lib/common.sh`
- State passed via files, not complex function arguments

**Inspiration**: Unix Rule of Modularity

---

### 2.2 Secondary Principles

#### Sensible Defaults, Full Configurability

> **"It should work out of the box, but every choice should be overridable."**

**Pattern from**: tmux-sensible, catppuccin/tmux

**In Practice**:
```bash
# Default works
TOWER_PREFIX=$(get_tmux_option "@tower-prefix" "${CLAUDE_TOWER_PREFIX:-t}")

# User can override via .tmux.conf
set -g @tower-prefix 's'

# Or via environment
export CLAUDE_TOWER_PREFIX='s'
```

---

#### Persistent Availability

> **"Navigator session is always alive for instant access."**

**Rationale**: Zero startup latency for session switching improves flow state.

**In Practice**:
- Navigator detaches rather than exits
- Session restored on next invocation
- Background server stays running

---

#### Defensive Scripting

> **"Assume the worst, prepare for recovery."**

**In Practice**:
- Input sanitization for all user-provided values
- Path validation before file operations
- Error traps with logging
- Include guards for library files

---

### 2.3 Anti-Principles (What We Explicitly Reject)

| Anti-Principle | Alternative Approach |
|----------------|---------------------|
| Magic behavior | Explicit, documented actions |
| Hidden state | Visible indicators for all states |
| Hard dependencies | Graceful degradation without optional tools |
| Blocking operations without feedback | Spinners or progress indicators |
| Silent failures | Logged errors with user notification |

---

## 3. Design Decisions

### 3.1 Key Trade-offs

| Decision | We Chose | Over | Because |
|----------|----------|------|---------|
| Rendering | tmux native panes | TUI libraries (blessed, etc.) | No dependencies, tmux consistency |
| State Storage | File-based metadata | tmux session options | Persistence across crashes |
| Server Model | Separate socket | Shared server | Isolation, won't affect user sessions |
| UI Model | Two-pane (list + view) | Single complex view | Each pane optimized for purpose |
| Navigation | vim-style (hjkl) | Arrow keys only | Terminal efficiency tradition |
| Session Preview | Nested tmux attach | capture-pane snapshot | Real-time streaming logs, interactive input |

### 3.2 Decision Records

#### DR-001: Socket Separation Architecture

- **Context**: Navigator needs to display all Claude sessions while users work within them
- **Options Considered**:
  1. Run Navigator in same tmux server (popup/window)
  2. Run Navigator as separate tmux server
  3. Run Navigator outside tmux entirely
- **Decision**: Option 2 - Separate tmux server with socket bridge
- **Consequences**:
  - Pro: Complete isolation from user sessions
  - Pro: Can control default server from Navigator
  - Con: Requires state file communication
  - Con: More complex attach/detach logic

#### DR-002: File-Based Session Metadata

- **Context**: Need to track session information across restarts
- **Options Considered**:
  1. tmux session options (@tower-* variables)
  2. SQLite database
  3. Plain text files
- **Decision**: Option 3 - Plain text files in `~/.claude-tower/metadata/`
- **Consequences**:
  - Pro: Survives session crashes
  - Pro: Human-readable and debuggable
  - Pro: No additional dependencies
  - Con: Manual serialization/parsing required

#### DR-003: Session States (Active/Exited/Dormant)

- **Context**: Users need to understand session status at a glance
- **Options Considered**:
  1. Binary (running/not running)
  2. Three states (active/exited/dormant)
  3. Fine-grained states (idle/typing/streaming/etc.)
- **Decision**: Option 2 - Three states
- **Consequences**:
  - Pro: Captures meaningful distinctions
  - Pro: Simple mental model
  - Con: Cannot distinguish Claude idle vs. working

#### DR-004: Nested Tmux for Session Preview

- **Context**: View pane needs to display selected session content in real-time
- **Options Considered**:
  1. `capture-pane` with periodic refresh (static snapshot)
  2. Nested tmux attach (live connection)
  3. Custom PTY forwarding
- **Decision**: Option 2 - Nested tmux attach with dedicated config
- **Rationale**: Claude Code frequently outputs streaming logs and real-time responses. Users need to see this live output, not periodic snapshots. The view pane must feel like "looking into" the session, not "looking at a photo of" it.
- **Implementation**:
  - Inner tmux uses `view-focus.conf` with Escape bound to detach
  - `TMUX=` prefix ensures connection to default server
  - Escape returns control to Navigator without killing the session
- **Consequences**:
  - Pro: Real-time streaming output visibility
  - Pro: Seamless input when focused (`i` key)
  - Pro: Full terminal capability (colors, cursor, etc.)
  - Con: Slightly more complex attach/detach coordination
  - Con: Requires signal mechanism for session switching

---

## 4. Implementation Guidelines

### 4.1 Architectural Patterns

| Pattern | Usage | Example |
|---------|-------|---------|
| Entry Point | Plugin initialization | `claude-tower.tmux` |
| Script Delegation | Feature execution | `scripts/navigator.sh` |
| Shared Library | Common utilities | `lib/common.sh` |
| Include Guard | Prevent double-sourcing | `[[ -n "${_LOADED:-}" ]] && return 0` |
| State File IPC | Cross-process communication | `/tmp/claude-tower/selected` |

### 4.2 Code Conventions

#### Shell Style

```bash
#!/usr/bin/env bash
# Strict mode (in libraries)
set -euo pipefail

# Constants are readonly and UPPER_SNAKE_CASE
readonly TOWER_PREFIX="${CLAUDE_TOWER_PREFIX:-t}"

# Functions are lower_snake_case
get_session_state() {
    local session_id="$1"  # Always declare local
    # ...
}

# Always quote variables
tmux send-keys -t "$session_id" "$input"
```

#### Error Handling

```bash
# Log before displaying
_log_to_file "ERROR" "$msg"
tmux display-message "Error: $msg" 2>/dev/null || true

# Always allow tmux commands to fail silently where appropriate
tmux kill-session -t "$session" 2>/dev/null || true
```

#### Security

```bash
# Sanitize user input
sanitize_name() {
    echo "$1" | tr -cd '[:alnum:]_-' | head -c 64
}

# Validate paths
validate_path_within() {
    local path="$1"
    local base="$2"
    [[ "$path" != *".."* ]] && [[ "$path" == "$base"* ]]
}
```

### 4.3 Quality Standards

| Aspect | Standard |
|--------|----------|
| Testing | Behavioral tests for all user-facing features |
| Error Handling | Every error case documented and handled |
| Documentation | README covers installation, usage, configuration |
| Compatibility | macOS and Linux; tmux 3.2+ |
| Security | Input sanitization, path validation, secure permissions |

---

## 5. Inspiration Sources

### 5.1 Unix Philosophy

| Principle | Application in Claude Tower |
|-----------|----------------------------|
| Do one thing well | Navigator navigates; session scripts manage sessions |
| Expect composition | Scripts can be called independently |
| Design for simplicity | Two-pane UI, three session states |
| Use text streams | Metadata as text files |
| Choose portability | Bash scripts, no exotic dependencies |

### 5.2 Popular Tmux Plugins

| Plugin | What We Learned |
|--------|-----------------|
| [TPM](https://github.com/tmux-plugins/tpm) | Entry point pattern, option conventions |
| [tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect) | File-based persistence, idempotent restore |
| [tmux-continuum](https://github.com/tmux-plugins/tmux-continuum) | Auto-save/restore philosophy |
| [tmux-sensible](https://github.com/tmux-plugins/tmux-sensible) | Sensible defaults that never override user settings |
| [vim-tmux-navigator](https://github.com/christoomey/vim-tmux-navigator) | Seamless cross-application navigation |
| [tmux-thumbs](https://github.com/fcsonline/tmux-thumbs) | Hint-based selection UX |
| [catppuccin/tmux](https://github.com/catppuccin/tmux) | Modular configuration, visual consistency |

### 5.3 Design Systems

| Source | Influence |
|--------|-----------|
| [Zen of Python](https://peps.python.org/pep-0020/) | Aphorism-style principles |
| [React Design Principles](https://legacy.reactjs.org/docs/design-principles.html) | Debugging breadcrumbs, gradual adoption |
| [Apple HIG](https://developer.apple.com/design/human-interface-guidelines) | User control, clear feedback |
| [Go Proverbs](https://go-proverbs.github.io/) | Clear is better than clever |

---

## 6. Living Document

### 6.1 How to Propose Changes

1. Open an issue describing the principle change
2. Provide rationale and affected code areas
3. Discuss with maintainers
4. Update this document via pull request

### 6.2 Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-01-03 | Initial philosophy document |

### 6.3 Related Documents

- [SPECIFICATION.md](../SPECIFICATION.md) - Detailed behavioral specification
- [error-handling-design.md](./error-handling-design.md) - Error handling patterns
- [GAP_ANALYSIS.md](../GAP_ANALYSIS.md) - Implementation status

---

## Appendix A: Popular Tmux Plugin Landscape

### Top Plugins by GitHub Stars (2024-2025)

| Rank | Plugin | Stars | Category |
|------|--------|-------|----------|
| 1 | Oh My Tmux! | ~24k | Configuration |
| 2 | Powerline | ~15k | Status bar |
| 3 | TPM | ~14k | Plugin manager |
| 4 | tmux-resurrect | ~12k | Persistence |
| 5 | vim-tmux-navigator | ~6k | Navigation |
| 6 | tmux-continuum | ~4k | Auto-persistence |
| 7 | tmux-powerline | ~4k | Status bar |
| 8 | catppuccin/tmux | ~2.4k | Theme |
| 9 | sesh | ~1.5k | Session manager |
| 10 | sessionx | ~1.1k | Fuzzy finder |

### Plugin Architecture Patterns

```
standard-plugin/
├── plugin-name.tmux     # Entry point (required by TPM)
├── lib/                 # Shared libraries
│   └── common.sh
├── scripts/             # Feature scripts
│   ├── main.sh
│   └── helpers/
├── docs/                # Extended documentation
└── tests/               # Test suite
```

---

## Appendix B: The Claude Tower Way

A condensed set of aphorisms for quick reference:

1. **tmux native, always** — Use platform features, not abstractions
2. **Separate sockets, separate concerns** — Navigator and sessions don't share servers
3. **State should be visible** — Icons tell the story at a glance
4. **Escape is the way out** — Every mode has a clear exit
5. **Scripts compose** — Small pieces, loosely joined
6. **Defaults that just work** — But every choice is overridable
7. **Fail gracefully** — Show errors in context, log for debugging
8. **Persistence through files** — Survive crashes, support debugging
9. **Security by sanitization** — Never trust input
10. **Platform over polish** — Works on macOS and Linux, even if not identical
11. **Live view, not snapshots** — Nested tmux attach over capture-pane for real-time streaming
