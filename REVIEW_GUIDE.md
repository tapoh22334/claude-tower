# Claude Tower - Comprehensive Product Review Guide

**Product**: claude-tower - tmux plugin for managing Claude Code sessions
**Version**: 1.0
**Review Date**: 2025-12-15
**Document Purpose**: QA Testing & Product Review Documentation

---

## Table of Contents

1. [Product Overview](#product-overview)
2. [Review Checklist](#review-checklist)
   - [Functionality & Core Features](#functionality--core-features)
   - [Security & Input Validation](#security--input-validation)
   - [Git Integration](#git-integration)
   - [User Experience & Usability](#user-experience--usability)
   - [Error Handling & Reliability](#error-handling--reliability)
   - [Performance & Resource Management](#performance--resource-management)
   - [Data Persistence & Cleanup](#data-persistence--cleanup)
   - [Documentation & Help](#documentation--help)
   - [Compatibility & Dependencies](#compatibility--dependencies)
3. [Test Scenarios & User Stories](#test-scenarios--user-stories)
4. [Testing Approach & Methodology](#testing-approach--methodology)
5. [Known Limitations & Edge Cases](#known-limitations--edge-cases)
6. [Security Validation](#security-validation)

---

## Product Overview

### Description
Claude Tower is a tmux plugin that provides session management for Claude Code CLI with tree-style navigation, live preview capabilities, and git worktree integration. It enables developers to efficiently manage multiple isolated Claude Code sessions with automatic worktree creation for parallel development workflows.

### Key Features
- **Dual Session Modes**: Workspace mode (git repos) and Simple mode (non-git directories)
- **Tree View Navigation**: Hierarchical display of sessions/windows/panes with icons
- **Live Preview**: Real-time preview of pane content and git status
- **Git Worktree Integration**: Automatic worktree creation with branch isolation
- **Session Lifecycle Management**: Create, rename, switch, and kill sessions
- **Orphan Cleanup**: Tool for managing stale worktrees after abnormal termination
- **Security-First Design**: Input sanitization, path validation, command injection prevention

### Target Users
- Developers using Claude Code CLI for AI-assisted development
- tmux power users managing multiple terminal sessions
- Teams working on multiple features/branches simultaneously
- DevOps engineers managing parallel deployments

### Critical Success Criteria
1. Sessions must be completely isolated (no cross-contamination)
2. Git worktrees must be properly created and cleaned up
3. User input must never cause security vulnerabilities
4. System must handle edge cases gracefully without data loss
5. Performance must remain responsive with 10+ active sessions

---

## Review Checklist

### Functionality & Core Features

#### Session Creation (High Priority)

- [ ] **[CRITICAL]** Can create Workspace session in git repository
  - _Verification_: Navigate to git repo, press `prefix + T`, enter session name
  - _Expected_: New tmux session created, worktree created at `~/.claude-tower/worktrees/<name>`
  - _Validation_: Check `git worktree list`, verify branch `tower/<name>` exists

- [ ] **[CRITICAL]** Can create Simple session in non-git directory
  - _Verification_: Navigate to non-git directory, press `prefix + T`, enter session name
  - _Expected_: New tmux session created without worktree
  - _Validation_: Session listed with [S] indicator in tree view

- [ ] **[HIGH]** Session naming accepts valid characters (alphanumeric, hyphen, underscore)
  - _Verification_: Try names: `my-project`, `test_123`, `Project1`
  - _Expected_: All names accepted and normalized correctly

- [ ] **[CRITICAL]** Session naming rejects dangerous characters
  - _Verification_: Try: `../etc`, `test;rm -rf`, `$(whoami)`, `test\`pwd\``
  - _Expected_: Characters sanitized or rejected with clear error message

- [ ] **[HIGH]** Duplicate session name handling
  - _Verification_: Create session "test", try creating another "test"
  - _Expected_: Switch to existing session with warning message

- [ ] **[MEDIUM]** Session name length limit enforced (64 chars)
  - _Verification_: Enter 100 character name
  - _Expected_: Truncated to 64 characters

#### Session Navigation (High Priority)

- [ ] **[CRITICAL]** Tree view displays all sessions correctly
  - _Verification_: Press `prefix + C`, view tree
  - _Expected_: All sessions shown with correct hierarchy and icons
  - _Validation_: 📁 for sessions, 🪟 for windows, ▫ for panes

- [ ] **[HIGH]** Active session/window/pane highlighted
  - _Verification_: Check active indicators in tree view
  - _Expected_: Active items marked with ● (green dot)

- [ ] **[HIGH]** Workspace sessions show git info
  - _Verification_: View Workspace session in tree
  - _Expected_: Shows [W], branch name with ⎇, diff stats (+X,-Y)

- [ ] **[HIGH]** Simple sessions show correct indicators
  - _Verification_: View Simple session in tree
  - _Expected_: Shows [S], "(no git)" message

- [ ] **[CRITICAL]** Can switch to session via Enter key
  - _Verification_: Select session in picker, press Enter
  - _Expected_: Switched to selected session immediately

- [ ] **[HIGH]** Can switch to specific window
  - _Verification_: Select window in tree, press Enter
  - _Expected_: Switched to that window in correct session

- [ ] **[HIGH]** Can switch to specific pane
  - _Verification_: Select pane in tree, press Enter
  - _Expected_: Switched to exact pane

#### Session Management (High Priority)

- [ ] **[CRITICAL]** Can rename session
  - _Verification_: Press `r` in picker, enter new name
  - _Expected_: Session renamed, metadata updated, worktree unaffected
  - _Validation_: Check `tmux list-sessions`, metadata file

- [ ] **[CRITICAL]** Can kill session with worktree cleanup
  - _Verification_: Select Workspace session, press `x`, confirm
  - _Expected_: Session killed, worktree removed, metadata deleted
  - _Validation_: `git worktree list` should not show worktree

- [ ] **[HIGH]** Can kill window
  - _Verification_: Select window, press `x`, confirm
  - _Expected_: Window killed, session remains

- [ ] **[HIGH]** Can kill pane
  - _Verification_: Select pane, press `x`, confirm
  - _Expected_: Pane killed, window remains

- [ ] **[HIGH]** Killing last window/pane triggers session cleanup
  - _Verification_: Kill all windows/panes in Workspace session
  - _Expected_: Worktree removed when session terminates

- [ ] **[MEDIUM]** Cancel operations work correctly
  - _Verification_: Try to kill/rename but select "No"
  - _Expected_: Operation cancelled, no changes made

#### Git Worktree Integration (Critical Priority)

- [ ] **[CRITICAL]** Worktree created at correct location
  - _Verification_: Create Workspace session
  - _Expected_: Worktree at `~/.claude-tower/worktrees/<session-name>`
  - _Validation_: Path resolves within worktree directory (no traversal)

- [ ] **[CRITICAL]** Branch created with correct naming
  - _Verification_: Check git branches after session creation
  - _Expected_: Branch `tower/<session-name>` exists

- [ ] **[HIGH]** Worktree based on current commit
  - _Verification_: Note current commit, create session, check worktree commit
  - _Expected_: Worktree starts from same commit as source repo

- [ ] **[HIGH]** Can create multiple worktrees from same repo
  - _Verification_: Create 3+ sessions from same repo
  - _Expected_: Each gets isolated worktree and branch

- [ ] **[CRITICAL]** Worktree cleanup on normal session exit
  - _Verification_: Exit session normally (exit command)
  - _Expected_: Worktree removed, branch removed (or kept based on policy)

- [ ] **[HIGH]** Diff stats displayed correctly in tree
  - _Verification_: Make changes in worktree, view tree
  - _Expected_: Shows +N,-M where N=added lines, M=deleted lines

- [ ] **[HIGH]** Handles existing branch gracefully
  - _Verification_: Create session, kill it, create with same name
  - _Expected_: Reuses existing branch or creates with different name

#### Live Preview (Medium Priority)

- [ ] **[MEDIUM]** Preview pane shows session content
  - _Verification_: Navigate through sessions in picker
  - _Expected_: Preview updates with pane content

- [ ] **[MEDIUM]** Preview shows git status for Workspace sessions
  - _Verification_: Select Workspace session in picker
  - _Expected_: Shows branch, commit, diff summary

- [ ] **[MEDIUM]** Preview handles large output
  - _Verification_: Select pane with 1000+ lines of output
  - _Expected_: Shows last 30 lines without lag

- [ ] **[LOW]** Preview updates in real-time
  - _Verification_: Navigate in picker while command runs in background
  - _Expected_: Preview content updates (may have slight delay)

#### Git Diff View (Medium Priority)

- [ ] **[MEDIUM]** Can view diff with 'D' key (Workspace only)
  - _Verification_: Make changes in Workspace session, press `D` in picker
  - _Expected_: Shows colorized diff

- [ ] **[MEDIUM]** Diff shows added/removed lines with colors
  - _Verification_: Check diff output colors
  - _Expected_: Green for additions, red for deletions

- [ ] **[LOW]** 'D' key disabled for Simple sessions
  - _Verification_: Select Simple session, press `D`
  - _Expected_: No diff shown or shows "Not a git repo" message

---

### Security & Input Validation

#### Input Sanitization (Critical Priority)

- [ ] **[CRITICAL]** Path traversal prevented in session names
  - _Verification_: Try names: `../../etc/passwd`, `../../../tmp`
  - _Expected_: Sanitized to valid characters, no directory traversal
  - _Test_: `sanitize_name "../../../etc/passwd"` → `"etcpasswd"`

- [ ] **[CRITICAL]** Command injection prevented
  - _Verification_: Try: `test; rm -rf /`, `test$(whoami)`, `test\`pwd\``
  - _Expected_: Special characters removed or escaped
  - _Test_: `sanitize_name "test; rm -rf /"` → `"testrm-rf"`

- [ ] **[CRITICAL]** Shell metacharacters removed
  - _Verification_: Try: `test|cat /etc/passwd`, `test&& whoami`
  - _Expected_: Metacharacters stripped

- [ ] **[CRITICAL]** Null byte injection prevented
  - _Verification_: Try name with null byte: `test\x00malicious`
  - _Expected_: Null bytes removed

- [ ] **[HIGH]** Unicode/multi-byte character handling
  - _Verification_: Try: `プロジェクト`, `test-名前`
  - _Expected_: Non-ASCII characters handled safely (removed or rejected)

#### Path Validation (Critical Priority)

- [ ] **[CRITICAL]** Worktree path stays within base directory
  - _Verification_: Create session, check resolved worktree path
  - _Expected_: `validate_path_within()` confirms path inside `TOWER_WORKTREE_DIR`
  - _Test_: Run unit test `tests/test_sanitize.bats::validate_path_within`

- [ ] **[CRITICAL]** Symlink escape prevention
  - _Verification_: Create symlink in worktree dir pointing to /tmp, try to use it
  - _Expected_: Symlink resolved, rejected if points outside base

- [ ] **[HIGH]** Relative path resolution
  - _Verification_: Try creating worktree with relative path components
  - _Expected_: Resolved to absolute path before validation

- [ ] **[HIGH]** Metadata file path validation
  - _Verification_: Check metadata files created at correct location
  - _Expected_: All in `~/.claude-tower/metadata/`, no escaping

#### Session Isolation (High Priority)

- [ ] **[CRITICAL]** Each Workspace session has isolated worktree
  - _Verification_: Create 2 sessions, make changes in each
  - _Expected_: Changes completely independent, no cross-contamination

- [ ] **[HIGH]** Simple sessions don't interfere with each other
  - _Verification_: Create 2 Simple sessions in same directory
  - _Expected_: Each has own tmux session, but share working directory

- [ ] **[HIGH]** Metadata isolated per session
  - _Verification_: Check metadata files
  - _Expected_: One `.meta` file per session with unique session_id

---

### Error Handling & Reliability

#### Dependency Checks (High Priority)

- [ ] **[CRITICAL]** Graceful failure if tmux not installed
  - _Verification_: Test on system without tmux (or temporarily rename binary)
  - _Expected_: Clear error: "tmux is required but not installed" with install hint

- [ ] **[CRITICAL]** Graceful failure if fzf not installed
  - _Verification_: Test without fzf
  - _Expected_: Error with installation instructions

- [ ] **[HIGH]** Git missing in Workspace mode
  - _Verification_: Try to create Workspace session without git
  - _Expected_: Fallback to Simple mode or clear error

- [ ] **[HIGH]** Claude CLI missing
  - _Verification_: Test with CLAUDE_TOWER_PROGRAM set to non-existent command
  - _Expected_: Session creates but shows error, or pre-flight check fails

- [ ] **[MEDIUM]** Dependency version checking (tmux 3.0+)
  - _Verification_: Check if version validated (manual test with old tmux)
  - _Expected_: Warning or error if tmux < 3.0

#### Error Recovery (High Priority)

- [ ] **[CRITICAL]** Handles git worktree add failure
  - _Verification_: Create scenario where worktree add fails (no permissions, disk full)
  - _Expected_: Clear error, no partial state, metadata not saved

- [ ] **[CRITICAL]** Handles session creation failure
  - _Verification_: Simulate tmux session creation failure
  - _Expected_: Worktree cleaned up, no orphaned resources

- [ ] **[HIGH]** Handles metadata write failure
  - _Verification_: Make metadata directory read-only
  - _Expected_: Error displayed, session may work but cleanup may fail

- [ ] **[HIGH]** Handles corrupt metadata files
  - _Verification_: Manually corrupt a .meta file
  - _Expected_: Session ignored or recreated, no crash

- [ ] **[HIGH]** Handles git repository in detached HEAD
  - _Verification_: Checkout detached HEAD, create Workspace session
  - _Expected_: Uses current commit, creates branch normally

- [ ] **[MEDIUM]** Handles git repository with no commits
  - _Verification_: Create empty git repo, try Workspace session
  - _Expected_: Clear error or fallback to Simple mode

#### Cleanup Edge Cases (Critical Priority)

- [ ] **[CRITICAL]** Orphan detection after kill -9
  - _Verification_: Create session, `kill -9` tmux process, run cleanup
  - _Expected_: Cleanup tool detects orphaned worktree

- [ ] **[CRITICAL]** Orphan cleanup removes worktree correctly
  - _Verification_: Run `cleanup.sh --force` on orphaned worktrees
  - _Expected_: Worktrees removed, metadata deleted, git clean

- [ ] **[HIGH]** Cleanup handles missing repository
  - _Verification_: Create session, delete source repo, run cleanup
  - _Expected_: Worktree directory removed manually, metadata cleaned

- [ ] **[HIGH]** Cleanup handles permission errors
  - _Verification_: Make worktree read-only, try cleanup
  - _Expected_: Uses --force flag, warns user

- [ ] **[MEDIUM]** Cleanup list shows accurate information
  - _Verification_: Run `cleanup.sh --list`
  - _Expected_: Shows session ID, type, path, creation time

#### Signal Handling (Medium Priority)

- [ ] **[MEDIUM]** Handles SIGTERM gracefully
  - _Verification_: Send SIGTERM to script during operation
  - _Expected_: Partial operations rolled back if possible

- [ ] **[LOW]** Handles SIGINT (Ctrl+C) gracefully
  - _Verification_: Press Ctrl+C during session creation
  - _Expected_: Operation cancelled cleanly

#### Error Messages (High Priority)

- [ ] **[HIGH]** Error messages are user-friendly
  - _Verification_: Trigger various errors, read messages
  - _Expected_: Clear, actionable, non-technical language

- [ ] **[HIGH]** Error messages suggest solutions
  - _Verification_: Check error text
  - _Expected_: Includes hints like installation commands

- [ ] **[MEDIUM]** Errors logged when debug enabled
  - _Verification_: Set `CLAUDE_TOWER_DEBUG=1`, trigger error
  - _Expected_: Detailed logs in `~/.claude-tower/metadata/tower.log`

---

### User Experience & Usability

#### Keyboard Shortcuts (High Priority)

- [ ] **[HIGH]** All documented shortcuts work
  - _Verification_: Test each: `prefix+C`, `prefix+T`, `n`, `r`, `x`, `D`, `?`
  - _Expected_: Each performs documented action

- [ ] **[MEDIUM]** Shortcuts shown in headers
  - _Verification_: Check fzf header text
  - _Expected_: "Enter:select | n:new | r:rename | x:kill | D:diff | ?:help"

- [ ] **[MEDIUM]** ESC key closes picker
  - _Verification_: Open picker, press ESC
  - _Expected_: Picker closes, returns to previous session

#### Visual Design (Medium Priority)

- [ ] **[MEDIUM]** Colors used effectively
  - _Verification_: View tree with multiple sessions
  - _Expected_: Sessions (blue), active (green), git (yellow), diffs (green/red)

- [ ] **[MEDIUM]** Icons render correctly
  - _Verification_: Check for: 📁 🪟 ▫ ● ⎇
  - _Expected_: All icons visible (terminal font support required)

- [ ] **[LOW]** Tree indentation clear
  - _Verification_: View nested windows/panes
  - _Expected_: Clear visual hierarchy with ├─ and └─

- [ ] **[LOW]** Layout responsive to terminal size
  - _Verification_: Resize terminal while picker open
  - _Expected_: fzf adjusts (80% width, 70% height)

#### Feedback & Confirmation (High Priority)

- [ ] **[HIGH]** Success messages shown
  - _Verification_: Perform actions, watch for confirmations
  - _Expected_: Green "Success:" messages via tmux display-message

- [ ] **[HIGH]** Confirmation required for destructive actions
  - _Verification_: Try killing session
  - _Expected_: "Kill session 'X'?" with Yes/No options

- [ ] **[MEDIUM]** Progress indication for slow operations
  - _Verification_: Create Workspace session (worktree creation can be slow)
  - _Expected_: Status messages shown during process

- [ ] **[LOW]** Warning messages distinguishable from errors
  - _Verification_: Trigger warnings (e.g., session exists)
  - _Expected_: Yellow "Warning:" distinct from red "Error:"

#### Help System (Medium Priority)

- [ ] **[MEDIUM]** Help screen accessible with '?'
  - _Verification_: Press `?` in picker
  - _Expected_: Help text shown in preview pane

- [ ] **[MEDIUM]** Help content accurate and complete
  - _Verification_: Read help text
  - _Expected_: Lists all shortcuts, explains modes

- [ ] **[LOW]** README installation instructions work
  - _Verification_: Follow README on fresh system
  - _Expected_: Plugin installs and works

#### Workflow Efficiency (Medium Priority)

- [ ] **[MEDIUM]** Can create and switch to session in <5 seconds
  - _Verification_: Time the workflow
  - _Expected_: Rapid session creation for productivity

- [ ] **[MEDIUM]** Tree view updates immediately after actions
  - _Verification_: Create session, check tree
  - _Expected_: New session appears without manual refresh

- [ ] **[LOW]** Picker remembers last selection position
  - _Verification_: Select session, close picker, reopen
  - _Expected_: Position may reset (acceptable) or remembered (nice to have)

---

### Performance & Resource Management

#### Scalability (High Priority)

- [ ] **[HIGH]** Handles 10+ concurrent sessions
  - _Verification_: Create 15 sessions, use tree view
  - _Expected_: No lag, all sessions listed

- [ ] **[HIGH]** Handles 50+ concurrent sessions
  - _Verification_: Create 50+ sessions (script recommended)
  - _Expected_: May slow down but remains functional

- [ ] **[MEDIUM]** Handles sessions with many windows/panes
  - _Verification_: Create session with 10 windows, 20 panes
  - _Expected_: Tree displays all correctly

- [ ] **[MEDIUM]** Preview performance with large output
  - _Verification_: Generate 10,000 lines in pane, preview it
  - _Expected_: Shows last 30 lines without blocking UI

#### Resource Usage (Medium Priority)

- [ ] **[MEDIUM]** Memory usage reasonable with many sessions
  - _Verification_: Monitor memory with 20+ sessions
  - _Expected_: Each session uses ~10-50MB (tmux + Claude)

- [ ] **[MEDIUM]** Disk space usage tracked
  - _Verification_: Check worktree directory size with multiple sessions
  - _Expected_: Each worktree ~= repo size (plus changes)

- [ ] **[LOW]** Metadata file size minimal
  - _Verification_: Check .meta file sizes
  - _Expected_: Each file <1KB

- [ ] **[LOW]** No memory leaks over time
  - _Verification_: Create/destroy sessions repeatedly, monitor memory
  - _Expected_: Memory stabilizes, doesn't grow indefinitely

#### Response Time (Medium Priority)

- [ ] **[MEDIUM]** Tree view renders in <500ms
  - _Verification_: Time from `prefix+C` to tree display
  - _Expected_: Instant or near-instant

- [ ] **[MEDIUM]** Session switching in <200ms
  - _Verification_: Time from Enter to session active
  - _Expected_: Immediate switch

- [ ] **[LOW]** Cleanup tool scans orphans in <2s
  - _Verification_: Time `cleanup.sh --list` with 20 metadata files
  - _Expected_: Fast scan

---

### Data Persistence & Cleanup

#### Metadata Persistence (High Priority)

- [ ] **[CRITICAL]** Metadata survives tmux server restart
  - _Verification_: Create session, kill tmux server, restart, check metadata
  - _Expected_: .meta files persist, orphan cleanup detects dead sessions

- [ ] **[HIGH]** Metadata includes all required fields
  - _Verification_: Read .meta file
  - _Expected_: session_id, session_type, repository_path, source_commit, worktree_path, created_at

- [ ] **[HIGH]** Metadata backward compatible
  - _Verification_: Test old metadata format (if applicable)
  - _Expected_: Loads old keys (mode → session_type, etc.)

- [ ] **[MEDIUM]** Metadata file format human-readable
  - _Verification_: `cat ~/.claude-tower/metadata/*.meta`
  - _Expected_: Simple key=value format

#### Cleanup Mechanisms (Critical Priority)

- [ ] **[CRITICAL]** Normal session exit cleans up worktree
  - _Verification_: Exit session normally, check worktree
  - _Expected_: Worktree removed, metadata deleted

- [ ] **[CRITICAL]** Cleanup tool detects all orphans
  - _Verification_: Create sessions, kill tmux abnormally, run cleanup --list
  - _Expected_: All orphaned sessions listed

- [ ] **[HIGH]** Cleanup tool interactive mode works
  - _Verification_: Run `cleanup.sh`, choose Yes/No
  - _Expected_: Confirmation dialog works, cleanup performed if Yes

- [ ] **[HIGH]** Cleanup tool force mode works
  - _Verification_: Run `cleanup.sh --force`
  - _Expected_: All orphans removed without prompts

- [ ] **[MEDIUM]** Cleanup handles partial failures
  - _Verification_: Make one worktree undeletable, run cleanup
  - _Expected_: Removes others, reports failure for problematic one

#### Data Directories (Medium Priority)

- [ ] **[MEDIUM]** Worktree directory created automatically
  - _Verification_: Fresh install, create session
  - _Expected_: `~/.claude-tower/worktrees/` created

- [ ] **[MEDIUM]** Metadata directory created automatically
  - _Verification_: Fresh install
  - _Expected_: `~/.claude-tower/metadata/` created

- [ ] **[LOW]** Custom directories via environment variables work
  - _Verification_: Set CLAUDE_TOWER_WORKTREE_DIR, create session
  - _Expected_: Worktrees created in custom location

---

### Documentation & Help

#### README Quality (High Priority)

- [ ] **[HIGH]** Installation instructions accurate
  - _Verification_: Follow README on fresh system (manual or TPM)
  - _Expected_: Plugin installs successfully

- [ ] **[HIGH]** Usage examples work
  - _Verification_: Try all examples from README
  - _Expected_: All commands work as documented

- [ ] **[MEDIUM]** Troubleshooting section helpful
  - _Verification_: Read troubleshooting, verify scenarios
  - _Expected_: Common issues covered with solutions

- [ ] **[MEDIUM]** Configuration options documented
  - _Verification_: Check README config section
  - _Expected_: All environment variables and tmux options listed

#### Inline Help (Medium Priority)

- [ ] **[MEDIUM]** `--help` flag works for cleanup.sh
  - _Verification_: `cleanup.sh --help`
  - _Expected_: Usage information displayed

- [ ] **[LOW]** Error messages reference documentation
  - _Verification_: Check error text
  - _Expected_: May include links or "see README" hints

#### Code Comments (Low Priority)

- [ ] **[LOW]** Security functions well-commented
  - _Verification_: Read `common.sh` sanitization section
  - _Expected_: Clear explanations of security measures

- [ ] **[LOW]** Complex logic explained
  - _Verification_: Read worktree creation code
  - _Expected_: Comments explain why, not just what

---

### Compatibility & Dependencies

#### tmux Compatibility (High Priority)

- [ ] **[HIGH]** Works with tmux 3.0
  - _Verification_: Test on system with tmux 3.0
  - _Expected_: All features work

- [ ] **[HIGH]** Works with tmux 3.2+
  - _Verification_: Test on modern tmux
  - _Expected_: All features work

- [ ] **[MEDIUM]** Handles tmux 2.x gracefully
  - _Verification_: Test on old tmux (if available)
  - _Expected_: Error or degraded functionality warning

#### Operating System Compatibility (High Priority)

- [ ] **[HIGH]** Works on macOS
  - _Verification_: Test on macOS (current: Darwin 24.3.0)
  - _Expected_: Full functionality

- [ ] **[HIGH]** Works on Linux (Ubuntu/Debian)
  - _Verification_: Test on Ubuntu 22.04 LTS
  - _Expected_: Full functionality

- [ ] **[MEDIUM]** Works on Linux (Fedora/RHEL)
  - _Verification_: Test on Fedora/CentOS
  - _Expected_: Full functionality

- [ ] **[LOW]** Works on BSD
  - _Verification_: Test on FreeBSD (if available)
  - _Expected_: May have minor issues with GNU-specific commands

#### Shell Compatibility (Medium Priority)

- [ ] **[MEDIUM]** Scripts use portable bash syntax
  - _Verification_: Check shebang, run shellcheck
  - _Expected_: No bashisms that require bash 5+

- [ ] **[MEDIUM]** Works with bash 3.2+ (macOS default)
  - _Verification_: Test on macOS with system bash
  - _Expected_: All scripts execute

- [ ] **[LOW]** Error if executed with sh instead of bash
  - _Verification_: Try running script with `sh script.sh`
  - _Expected_: May fail with clear error

#### Git Compatibility (Medium Priority)

- [ ] **[MEDIUM]** Works with git 2.20+
  - _Verification_: Check git worktree features used
  - _Expected_: Standard worktree commands (add, remove, list)

- [ ] **[LOW]** Handles git configuration edge cases
  - _Verification_: Test with unusual gitconfig (different core.worktree, etc.)
  - _Expected_: Works or shows clear error

#### fzf Compatibility (Medium Priority)

- [ ] **[MEDIUM]** Works with fzf 0.30+
  - _Verification_: Check fzf features used
  - _Expected_: Standard preview, bind options

- [ ] **[LOW]** Handles missing fzf-tmux
  - _Verification_: Remove fzf-tmux wrapper
  - _Expected_: Clear error about fzf installation

#### Claude CLI Compatibility (High Priority)

- [ ] **[HIGH]** Works with current Claude CLI
  - _Verification_: Test with latest `claude` binary
  - _Expected_: Sessions start Claude correctly

- [ ] **[MEDIUM]** Handles Claude CLI updates
  - _Verification_: Check if hardcoded to specific version
  - _Expected_: Version-agnostic, just executes $CLAUDE_TOWER_PROGRAM

- [ ] **[MEDIUM]** Custom program via CLAUDE_TOWER_PROGRAM
  - _Verification_: Set to different program (e.g., `vim`)
  - _Expected_: Works with any CLI program

---

## Test Scenarios & User Stories

### Story 1: First-Time User Creates Workspace Session

**User Type**: Developer new to Claude Tower
**Objective**: Create first Workspace session to work on a feature branch
**Preconditions**:
- Claude Tower installed via TPM
- Working in a git repository (`~/projects/myapp`)
- Currently on `main` branch
- Dependencies installed (tmux, fzf, git, claude)

**Step-by-Step Actions**:

1. **Open tmux session**
   - Start tmux: `tmux`
   - Expected: Normal tmux session starts

2. **Navigate to project**
   - `cd ~/projects/myapp`
   - Expected: In git repository root

3. **Create new session**
   - Press `Ctrl+b` then `T` (or custom prefix)
   - Expected: fzf prompt appears asking for session name

4. **Enter session name**
   - Type: `feature-auth`
   - Press Enter
   - Expected:
     - Message: "Creating Workspace session: feature-auth"
     - Worktree creation messages displayed
     - Success: "Created worktree at: ~/.claude-tower/worktrees/feature-auth"
     - Success: "Created session: tower_feature-auth"
     - Automatically switched to new session

5. **Verify worktree created**
   - In new session, run: `pwd`
   - Expected: Working directory is `~/.claude-tower/worktrees/feature-auth`
   - Run: `git branch --show-current`
   - Expected: On branch `tower/feature-auth`

6. **Verify Claude running**
   - Expected: Claude Code CLI is running in the pane

7. **Make changes and verify isolation**
   - Create a test file: `echo "test" > test.txt`
   - Switch back to original directory: `cd ~/projects/myapp`
   - Check: `ls test.txt`
   - Expected: File does not exist (isolated in worktree)

8. **View session in tree**
   - Press `Ctrl+b` then `C`
   - Expected: Tree shows:
     ```
     📁 ● [W] tower_feature-auth  ⎇ tower/feature-auth
       └─ 🪟 0: main ●
          └─ ▫ 0: claude ●
     ```

**Validation Points**:
- [ ] Worktree created at correct path
- [ ] Branch `tower/feature-auth` created from current commit
- [ ] Session completely isolated from source repository
- [ ] Claude CLI started automatically
- [ ] Metadata file exists: `~/.claude-tower/metadata/tower_feature-auth.meta`
- [ ] Tree view shows [W] indicator and git info

**Edge Cases to Test**:
- Try creating session with same name again (should switch to existing)
- Try special characters in name (should be sanitized)
- Try on detached HEAD (should still work)

---

### Story 2: Developer Switches Between Multiple Active Sessions

**User Type**: Experienced tmux user
**Objective**: Quickly navigate between multiple ongoing projects
**Preconditions**:
- 5 existing sessions:
  - `tower_api-work` (Workspace, 3 windows)
  - `tower_frontend` (Workspace, 2 windows)
  - `tower_docs` (Simple, 1 window)
  - `tower_testing` (Workspace, modified files)
  - `tower_scripts` (Simple)

**Step-by-Step Actions**:

1. **Open session picker**
   - Press `Ctrl+b` then `C`
   - Expected: fzf opens with tree of all 5 sessions

2. **Review tree structure**
   - Expected: Tree shows hierarchical view:
     ```
     📁 ● [W] tower_api-work  ⎇ tower/api-work +15,-3
       ├─ 🪟 0: main ●
       │  └─ ▫ 0: claude ●
       ├─ 🪟 1: shell
       │  └─ ▫ 0: zsh
       └─ 🪟 2: tests
          └─ ▫ 0: pytest
     📁 [W] tower_frontend  ⎇ tower/frontend
       └─ 🪟 0: main
          └─ ▫ 0: claude
     📁 [S] tower_docs  (no git)
       └─ 🪟 0: main
          └─ ▫ 0: claude
     ...
     ```

3. **Use preview to examine session**
   - Navigate to `tower_testing` with arrow keys
   - Expected: Preview pane shows:
     - Current directory
     - Git status (modified files)
     - Pane content preview

4. **View git diff**
   - With `tower_testing` selected, press `D`
   - Expected: Preview switches to colorized git diff
   - Green lines for additions, red for deletions

5. **Switch to specific window**
   - Navigate to `tower_api-work` → window 2: tests
   - Press Enter
   - Expected: Immediately switched to that exact window

6. **Quick switch back**
   - Press `Ctrl+b` `C` again
   - Arrow down to `tower_frontend`
   - Press Enter
   - Expected: Switched to frontend session

7. **Create new session while picker open**
   - Open picker again
   - Press `n` (new session)
   - Enter name: `hotfix-bug`
   - Expected: New session created, tree reloads automatically showing 6 sessions

**Validation Points**:
- [ ] All sessions visible in tree
- [ ] Active session marked with ●
- [ ] Git info accurate (branch, diff stats)
- [ ] Preview updates as navigation occurs
- [ ] Session switching is instant (<200ms)
- [ ] Tree auto-reloads after new session creation

**Edge Cases to Test**:
- Press ESC to cancel without switching
- Try 'D' on Simple session (should no-op or show message)
- Navigate with many sessions (50+) to test performance

---

### Story 3: Cleaning Up After Abnormal Termination

**User Type**: Developer after system crash
**Objective**: Recover disk space by cleaning orphaned worktrees
**Preconditions**:
- System crashed or tmux was killed with `kill -9`
- 3 Workspace sessions existed but tmux server is now gone
- Worktrees and metadata files remain on disk

**Step-by-Step Actions**:

1. **Restart tmux**
   - Run: `tmux`
   - Expected: Fresh tmux with no sessions

2. **Check for orphaned worktrees (manual)**
   - Run: `ls ~/.claude-tower/worktrees/`
   - Expected: Shows orphaned directories: `session1`, `session2`, `session3`
   - Run: `ls ~/.claude-tower/metadata/`
   - Expected: Shows .meta files: `tower_session1.meta`, etc.

3. **Run cleanup list command**
   - Run: `~/.tmux/plugins/claude-tower/tmux-plugin/scripts/cleanup.sh --list`
   - Expected: Output shows:
     ```
     ━━━ Orphaned Worktrees ━━━

     [1] tower_session1
         Session Type: workspace
         Worktree: /Users/dev/.claude-tower/worktrees/session1
         Status: Exists
         Created: 2025-12-14T10:30:00+00:00

     [2] tower_session2
         Session Type: workspace
         Worktree: /Users/dev/.claude-tower/worktrees/session2
         Status: Exists
         Created: 2025-12-14T11:15:00+00:00

     [3] tower_session3
         Session Type: simple
         Created: 2025-12-14T14:20:00+00:00

     Total: 3 orphaned worktree(s)
     ```

4. **Run interactive cleanup**
   - Run: `~/.tmux/plugins/claude-tower/tmux-plugin/scripts/cleanup.sh`
   - Expected: Shows list, then asks: "Remove all orphaned worktrees?"
   - Options: "Yes" / "No"

5. **Confirm cleanup**
   - Select "Yes"
   - Expected: Progress messages:
     ```
     Removing: tower_session1... OK
     Removing: tower_session2... OK
     Removing: tower_session3... OK

     Cleanup complete. Removed: 3, Failed: 0
     ```

6. **Verify cleanup completed**
   - Run: `ls ~/.claude-tower/worktrees/`
   - Expected: Empty or only active sessions
   - Run: `ls ~/.claude-tower/metadata/`
   - Expected: No .meta files for removed sessions
   - Run: `git worktree list` in source repo
   - Expected: Orphaned worktrees not listed

7. **Run cleanup again**
   - Run: `cleanup.sh --list`
   - Expected: "No orphaned worktrees found."

**Validation Points**:
- [ ] Orphan detection accurate (doesn't list active sessions)
- [ ] Worktrees removed from filesystem
- [ ] Git worktree references cleaned up
- [ ] Metadata files deleted
- [ ] No errors during cleanup
- [ ] Idempotent (can run multiple times safely)

**Edge Cases to Test**:
- Run cleanup when no orphans exist (should show "none found")
- Run `cleanup.sh --force` (should skip confirmation)
- Delete source repository before cleanup (should still clean worktree dir)
- Make worktree read-only, then cleanup (should use --force flag)
- Interrupt cleanup with Ctrl+C (should stop gracefully)

---

### Story 4: Renaming Session to Match New Branch

**User Type**: Developer refactoring task naming
**Objective**: Rename session to match updated branch naming convention
**Preconditions**:
- Existing Workspace session: `tower_feat1`
- Working on branch: `tower/feat1`
- Team decides to use new naming: `feature-login`

**Step-by-Step Actions**:

1. **Verify current session**
   - Check current session: `tmux display-message -p '#S'`
   - Expected: `tower_feat1`

2. **Open session picker**
   - Press `Ctrl+b` then `C`
   - Expected: Tree shows current session

3. **Initiate rename**
   - Navigate to `tower_feat1`
   - Press `r`
   - Expected: fzf prompt: "New name for session 'tower_feat1':"

4. **Enter new name**
   - Type: `feature-login`
   - Press Enter
   - Expected:
     - Message: "Renaming session..."
     - Success: "Renamed session to: tower_feature-login"

5. **Verify session renamed**
   - Check session: `tmux display-message -p '#S'`
   - Expected: `tower_feature-login`
   - Expected: Still in same worktree (path unchanged)

6. **Check metadata updated**
   - Run: `cat ~/.claude-tower/metadata/tower_feature-login.meta`
   - Expected: session_id updated
   - Old metadata file deleted: `tower_feat1.meta` should not exist

7. **Verify tree view updated**
   - Open picker again
   - Expected: Tree shows `tower_feature-login` not `tower_feat1`

8. **Check git branch NOT renamed**
   - Run: `git branch`
   - Expected: Still on `tower/feat1` (branch name independent of session name)
   - Note: This is expected behavior - session rename doesn't affect git

**Validation Points**:
- [ ] Session renamed successfully
- [ ] Metadata file renamed and updated
- [ ] Still attached to same worktree
- [ ] Git branch unchanged (as designed)
- [ ] Tree view reflects new name
- [ ] Can still perform all operations on renamed session

**Edge Cases to Test**:
- Rename to existing session name (should warn or reject)
- Rename with invalid characters (should sanitize)
- Rename while processes running in session (should work)
- Rename Simple session (should work same way)

---

### Story 5: Killing Session and Verifying Complete Cleanup

**User Type**: Developer finishing a task
**Objective**: Delete completed session and ensure no leftover resources
**Preconditions**:
- Workspace session `tower_bugfix-123` exists
- Worktree at `~/.claude-tower/worktrees/bugfix-123`
- Branch `tower/bugfix-123` exists
- Metadata file exists

**Step-by-Step Actions**:

1. **Open session picker**
   - Press `Ctrl+b` then `C`
   - Expected: Tree shows all sessions including `tower_bugfix-123`

2. **Select session to kill**
   - Navigate to `tower_bugfix-123`
   - Press `x`
   - Expected: Confirmation dialog: "Kill session 'tower_bugfix-123'?"
   - Options: "Yes" / "No"

3. **Confirm kill**
   - Select "Yes"
   - Expected: Progress messages:
     - "Removed worktree: ..."
     - "Killed session: tower_bugfix-123"

4. **Verify session killed**
   - Run: `tmux list-sessions`
   - Expected: `tower_bugfix-123` not in list

5. **Verify worktree removed**
   - Run: `ls ~/.claude-tower/worktrees/`
   - Expected: `bugfix-123` directory does not exist
   - Run: `git worktree list` in source repo
   - Expected: Worktree not listed

6. **Verify metadata deleted**
   - Run: `ls ~/.claude-tower/metadata/tower_bugfix-123.meta`
   - Expected: File not found

7. **Verify tree view updated**
   - Open picker again
   - Expected: `tower_bugfix-123` not shown

8. **Check orphan cleanup doesn't find it**
   - Run: `cleanup.sh --list`
   - Expected: `tower_bugfix-123` not listed (clean kill, not orphaned)

**Validation Points**:
- [ ] Tmux session terminated
- [ ] Worktree directory removed
- [ ] Git worktree reference removed
- [ ] Metadata file deleted
- [ ] No orphaned resources
- [ ] Can recreate session with same name

**Edge Cases to Test**:
- Kill session with unsaved work (should still kill, user responsibility)
- Kill session that's the only one (should work, may exit tmux)
- Kill session while command running (should kill immediately)
- Cancel kill operation (select "No" - nothing should change)
- Kill window instead of session (worktree should remain)
- Kill last window in session (should trigger full cleanup)

---

### Story 6: Working with Non-Git Directory (Simple Mode)

**User Type**: Developer working on scripts
**Objective**: Use Claude Tower for non-git projects
**Preconditions**:
- Directory `~/scripts/` exists (not a git repo)
- Need quick access to Claude for script writing

**Step-by-Step Actions**:

1. **Navigate to scripts directory**
   - `cd ~/scripts/`
   - Verify not git: `git status` → error

2. **Create Simple session**
   - Press `Ctrl+b` then `T`
   - Enter name: `my-scripts`
   - Expected: Message: "Creating Simple session: my-scripts"
   - Success: "Created session: tower_my-scripts"

3. **Verify working directory**
   - Run: `pwd`
   - Expected: `/Users/dev/scripts` (original directory, NOT a worktree)

4. **Verify no worktree created**
   - Run: `ls ~/.claude-tower/worktrees/`
   - Expected: `my-scripts` directory does not exist

5. **View in tree**
   - Press `Ctrl+b` `C`
   - Expected: Tree shows:
     ```
     📁 [S] tower_my-scripts  (no git)
       └─ 🪟 0: main
          └─ ▫ 0: claude
     ```

6. **Try git diff (should not work)**
   - In picker, select session, press `D`
   - Expected: No diff shown or message "Not a git repository"

7. **Kill session**
   - Select session, press `x`, confirm
   - Expected: Session killed, no worktree cleanup (none to clean)

**Validation Points**:
- [ ] Simple session created in original directory
- [ ] No worktree created
- [ ] Tree shows [S] indicator
- [ ] Git operations disabled/skipped
- [ ] Metadata shows session_type: simple
- [ ] Kill operation simpler (no worktree cleanup)

**Edge Cases to Test**:
- Create Simple session in git repo (should detect git, offer Workspace)
- Create multiple Simple sessions in same directory (should work, share dir)
- Simple session in directory that later becomes git repo (should still work)

---

### Story 7: Testing Input Sanitization (Security)

**User Type**: QA tester / Security reviewer
**Objective**: Verify malicious input is safely handled
**Preconditions**:
- Claude Tower installed
- Testing environment (not production)

**Step-by-Step Actions**:

1. **Test path traversal in session name**
   - Press `Ctrl+b` `T`
   - Enter: `../../../../etc/passwd`
   - Expected: Sanitized to `etcpasswd`, session created safely

2. **Test command injection**
   - Create session with name: `test; rm -rf /`
   - Expected: Sanitized to `testrm-rf`
   - Verify: No files deleted, system safe

3. **Test shell metacharacters**
   - Create session: `test|cat /etc/passwd`
   - Expected: Sanitized, no command executed

4. **Test backtick substitution**
   - Create session: `test\`whoami\``
   - Expected: Sanitized, no command executed

5. **Test dollar substitution**
   - Create session: `test$(whoami)`
   - Expected: Sanitized

6. **Verify worktree path safe**
   - After creating session with malicious name
   - Check: `realpath ~/.claude-tower/worktrees/*`
   - Expected: All paths within `~/.claude-tower/worktrees/`

7. **Test metadata file safety**
   - Check metadata files created
   - Expected: All in `~/.claude-tower/metadata/`
   - Run: `cat ~/.claude-tower/metadata/*.meta`
   - Expected: No code execution, safe content

**Validation Points**:
- [ ] No path traversal possible
- [ ] No command injection possible
- [ ] All input sanitized before use
- [ ] Worktree paths validated
- [ ] Metadata paths validated
- [ ] Unit tests pass for sanitization functions

**Edge Cases to Test**:
- Null byte injection: `test\x00malicious`
- Unicode: various unicode characters
- Very long names (>64 chars) - should truncate
- Empty input - should reject or use default

---

### Story 8: Stress Testing with Many Sessions

**User Type**: Power user with many projects
**Objective**: Verify system handles heavy usage
**Preconditions**:
- Script to create multiple sessions
- Sufficient disk space

**Step-by-Step Actions**:

1. **Create script to generate sessions**
   ```bash
   for i in {1..30}; do
     tmux send-keys "Ctrl+b" "T"
     sleep 1
     tmux send-keys "session-$i" "Enter"
     sleep 2
   done
   ```

2. **Execute script**
   - Run script
   - Expected: 30 sessions created over ~2 minutes

3. **Open tree view**
   - Press `Ctrl+b` `C`
   - Expected: Tree displays all 30 sessions
   - Check: Scrolling smooth, no lag

4. **Test navigation**
   - Arrow through all sessions
   - Expected: Preview updates, no freezing

5. **Check memory usage**
   - Run: `ps aux | grep tmux`
   - Expected: Reasonable memory (each session ~20-50MB)

6. **Check disk usage**
   - Run: `du -sh ~/.claude-tower/worktrees/`
   - Expected: Proportional to number of sessions × repo size

7. **Test operations with many sessions**
   - Kill a session in the middle of the list
   - Expected: Works normally, tree updates

8. **Cleanup all sessions**
   - Use script or manually kill all
   - Run: `cleanup.sh --force`
   - Expected: All worktrees cleaned up successfully

**Validation Points**:
- [ ] Can create 30+ sessions
- [ ] Tree view remains responsive
- [ ] Memory usage reasonable
- [ ] Disk usage tracked correctly
- [ ] All operations work at scale
- [ ] Cleanup handles bulk removal

**Edge Cases to Test**:
- 50 sessions
- 100 sessions (if system allows)
- Mix of Workspace and Simple sessions
- Sessions with many windows/panes each

---

## Testing Approach & Methodology

### Test Pyramid Structure

Claude Tower implements a comprehensive test pyramid:

```
        ┌─────────────┐
        │ E2E Tests   │  Integration with real tmux/git
        │   (bats)    │  Scenarios in tests/scenarios/
        └─────────────┘
             ▲
        ┌─────────────┐
        │Integration  │  tmux + scripts interaction
        │  Tests      │  tests/integration/
        └─────────────┘
             ▲
        ┌─────────────┐
        │Unit Tests   │  Function-level validation
        │  (bats)     │  tests/test_*.bats
        └─────────────┘
```

### Recommended Testing Sequence

#### Phase 1: Automated Unit Tests (Required)

Run existing test suite:

```bash
# All tests
/Users/iwase/working/claude-tower/tests/run_all_tests.sh

# Individual test suites
bats /Users/iwase/working/claude-tower/tests/test_sanitize.bats        # Security/input validation
bats /Users/iwase/working/claude-tower/tests/test_validation.bats      # Path/session validation
bats /Users/iwase/working/claude-tower/tests/test_metadata.bats        # Metadata operations
bats /Users/iwase/working/claude-tower/tests/test_orphan.bats          # Cleanup detection
bats /Users/iwase/working/claude-tower/tests/test_error_handling.bats  # Error scenarios
```

**Success Criteria**: All unit tests pass (100% pass rate required)

#### Phase 2: Integration Tests (Required)

```bash
# Integration tests
/Users/iwase/working/claude-tower/tests/run_integration_tests.sh

# E2E workflow tests
/Users/iwase/working/claude-tower/tests/run_e2e_tests.sh
```

**Success Criteria**: All integration tests pass

#### Phase 3: Manual Functional Testing (High Priority)

Use this review guide to manually test:
1. Core session management (Stories 1, 2, 4, 5)
2. Security features (Story 7)
3. Cleanup mechanisms (Story 3)
4. Simple mode (Story 6)

**Success Criteria**: All HIGH and CRITICAL priority checklist items pass

#### Phase 4: Exploratory Testing (Medium Priority)

- Test edge cases not covered by automated tests
- Simulate user workflows (Stories 7, 8)
- Stress testing with many sessions
- Cross-platform testing (macOS, Linux)

#### Phase 5: Performance & Scalability (Low Priority)

- Load testing with 50+ sessions
- Memory leak detection (long-running sessions)
- Response time measurements

### Test Environment Setup

#### Minimal Test Environment

```bash
# Requirements
- tmux 3.0+
- fzf
- git
- bash 3.2+
- bats (for automated tests)
```

#### Docker Test Environment (Recommended)

Use provided Docker environment for isolated testing:

```bash
# Build test container
docker build -f tests/docker/Dockerfile -t claude-tower-test .

# Run tests in container
docker run --rm claude-tower-test ./tests/run_all_tests.sh
```

### Test Data Management

#### Creating Test Sessions

```bash
# Helper function for reviewers
create_test_session() {
  local name="$1"
  echo "$name" | tmux send-keys "Ctrl+b" "T"
  tmux send-keys "Enter"
}

# Create 5 test sessions
for i in {1..5}; do
  create_test_session "test-$i"
  sleep 1
done
```

#### Cleanup Test Data

```bash
# Kill all tower sessions
tmux list-sessions -F '#{session_name}' | \
  grep '^tower_' | \
  xargs -I {} tmux kill-session -t {}

# Force cleanup orphans
~/.tmux/plugins/claude-tower/tmux-plugin/scripts/cleanup.sh --force
```

### Bug Reporting Template

When issues are found:

```markdown
## Bug Report

**Title**: [Brief description]

**Severity**: Critical | High | Medium | Low

**Environment**:
- OS: [macOS 14.0 / Ubuntu 22.04 / etc.]
- tmux version: [3.2a]
- git version: [2.39.0]
- Plugin version: [commit hash]

**Steps to Reproduce**:
1. [Step 1]
2. [Step 2]
3. [Step 3]

**Expected Behavior**:
[What should happen]

**Actual Behavior**:
[What actually happens]

**Logs** (if `CLAUDE_TOWER_DEBUG=1`):
```
[Log output]
```

**Screenshots** (if applicable):
[Attach tree view, error messages]

**Workaround** (if known):
[Temporary fix]
```

### Performance Benchmarking

#### Response Time Measurements

```bash
# Measure tree build time
time ~/.tmux/plugins/claude-tower/tmux-plugin/scripts/tower.sh --list

# Measure cleanup scan time
time ~/.tmux/plugins/claude-tower/tmux-plugin/scripts/cleanup.sh --list
```

**Benchmarks**:
- Tree build: <500ms with 10 sessions
- Cleanup scan: <2s with 20 metadata files
- Session switch: <200ms

#### Resource Monitoring

```bash
# Monitor memory during testing
while true; do
  ps aux | grep tmux | awk '{sum+=$6} END {print "Total tmux memory: " sum/1024 " MB"}'
  sleep 5
done

# Check disk usage
watch -n 5 'du -sh ~/.claude-tower/worktrees/'
```

---

## Known Limitations & Edge Cases

### Architectural Limitations

1. **Session Naming Constraints**
   - Maximum 64 characters (truncated)
   - Only alphanumeric, hyphen, underscore allowed
   - Reason: Security (prevents injection), filesystem compatibility

2. **Git Worktree Dependencies**
   - Requires git 2.5+ for worktree support
   - Each worktree is full repository size (disk space consideration)
   - Worktree limit per repo: ~1000 (git limitation, not claude-tower)

3. **tmux Version Requirements**
   - Requires tmux 3.0+ for certain display options
   - Older versions may have degraded UI

### Edge Cases to Document

#### Session Name Conflicts

**Scenario**: User creates session "test", then "TEST"
**Behavior**: Normalized to same name (tower_test)
**Impact**: Second creation switches to first session
**Workaround**: Use different names

#### Abnormal Termination

**Scenario**: System crash, `kill -9`, power loss
**Behavior**: Worktrees orphaned
**Impact**: Disk space used until manual cleanup
**Resolution**: Run `cleanup.sh` periodically or after system recovery

#### Repository Deletion

**Scenario**: Source git repository deleted while sessions exist
**Behavior**: Sessions continue to work (worktrees independent)
**Impact**: Cleanup may fail to remove git worktree reference
**Resolution**: Cleanup tool removes directories even if git fails

#### Disk Space Exhaustion

**Scenario**: Create many Workspace sessions, run out of disk space
**Behavior**: Session creation fails with git error
**Impact**: Partial state possible (directory created but worktree failed)
**Prevention**: Monitor disk space, limit concurrent sessions

#### Unicode/Special Characters

**Scenario**: User enters emoji or non-ASCII characters in name
**Behavior**: Removed by sanitization
**Impact**: May result in empty name or unexpected normalization
**Recommendation**: Use ASCII-only names

#### Network Filesystems

**Scenario**: `~/.claude-tower/` on NFS or other network filesystem
**Behavior**: May work but with performance degradation
**Impact**: Slow worktree operations, potential lock issues
**Recommendation**: Use local filesystem for worktree directory

#### Multiple tmux Servers

**Scenario**: User runs multiple tmux servers (different sockets)
**Behavior**: Each server has own sessions, but shares metadata
**Impact**: Cleanup tool may detect active sessions as orphaned
**Workaround**: Use separate metadata directories per server

---

## Security Validation

### Critical Security Functions

All critical security functions are unit tested. Verify:

```bash
# Run security-focused tests
bats /Users/iwase/working/claude-tower/tests/test_sanitize.bats
bats /Users/iwase/working/claude-tower/tests/test_validation.bats
```

### Manual Security Review

- [ ] Review `sanitize_name()` in `/Users/iwase/working/claude-tower/tmux-plugin/lib/common.sh` (lines 109-114)
  - Confirms: Only allows `[a-zA-Z0-9_-]`
  - Confirms: Truncates to 64 characters
  - Confirms: Removes path traversal (../)

- [ ] Review `validate_path_within()` (lines 124-135)
  - Confirms: Uses `realpath` to resolve symlinks
  - Confirms: Checks resolved path starts with base directory
  - Confirms: Prevents directory escape

- [ ] Review `normalize_session_name()` (lines 143-146)
  - Confirms: Adds `tower_` prefix (namespace isolation)
  - Confirms: Replaces spaces/dots with underscores

- [ ] Code audit: No `eval`, no unquoted variables in commands

### Penetration Testing Scenarios

For security-conscious reviews, attempt:

1. **Path Traversal**: Try to create files outside allowed directories
2. **Command Injection**: Try to execute arbitrary commands via input
3. **Race Conditions**: Try to create sessions with same name simultaneously
4. **Symlink Attacks**: Create malicious symlinks, verify they're detected
5. **Resource Exhaustion**: Create many sessions rapidly, check limits

**Expected**: All attacks mitigated, system remains secure

---

## Review Sign-Off

### Reviewer Information

- **Reviewer Name**: ___________________________
- **Review Date**: ___________________________
- **Plugin Version Tested**: ___________________________

### Review Completion

- [ ] All CRITICAL priority items tested and passed
- [ ] All HIGH priority items tested and passed
- [ ] At least 3 user stories completed end-to-end
- [ ] Security validation checklist completed
- [ ] Automated test suite run and passed
- [ ] Issues documented with severity and reproduction steps

### Recommendation

- [ ] **Approved for Release**: All critical issues resolved
- [ ] **Approved with Minor Issues**: Non-blocking issues documented
- [ ] **Requires Revision**: Critical issues must be fixed before release

**Notes**:
_________________________________________________________________
_________________________________________________________________
_________________________________________________________________

**Signature**: ____________________________  **Date**: __________

---

**End of Review Guide**
