# Tasks: Tower v2 - セッション管理の簡素化

**Input**: Design documents from `/specs/001-tower-v2-simplify/`
**Prerequisites**: plan.md, spec.md, data-model.md, contracts/cli.md, research.md

**Tests**: TDD approach - tests included for core functionality

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

```
tmux-plugin/
├── scripts/     # Shell scripts
├── lib/         # Common libraries
└── conf/        # Configuration

tests/           # bats test files
```

---

## Phase 1: Setup

**Purpose**: Prepare codebase for v2 changes

- [x] T001 Create feature branch backup of current common.sh in tmux-plugin/lib/common.sh.v1.bak
- [x] T002 [P] Verify bats test framework is available and working with `./tests/bats/bin/bats --version`

---

## Phase 2: Foundational (Core Metadata Changes)

**Purpose**: Update metadata functions that ALL user stories depend on

**CRITICAL**: No user story work can begin until this phase is complete

- [x] T003 Update `save_metadata()` function in tmux-plugin/lib/common.sh to use v2 format (session_id, session_name, directory_path, created_at only)
- [x] T004 Update `load_metadata()` function in tmux-plugin/lib/common.sh with v1 backward compatibility (worktree_path, repository_path → directory_path)
- [x] T005 Add `shorten_path()` helper function in tmux-plugin/lib/common.sh for ~ expansion in display
- [x] T006 Remove `TYPE_WORKTREE`, `TYPE_SIMPLE` constants from tmux-plugin/lib/common.sh
- [x] T007 Remove `ICON_TYPE_WORKTREE`, `ICON_TYPE_SIMPLE` constants from tmux-plugin/lib/common.sh
- [x] T008 Remove `get_session_type()` function from tmux-plugin/lib/common.sh
- [x] T009 Remove `get_type_icon()` function from tmux-plugin/lib/common.sh
- [x] T010 Remove `_create_worktree_session()` function from tmux-plugin/lib/common.sh
- [x] T011 Remove `find_orphaned_worktrees()` function from tmux-plugin/lib/common.sh
- [x] T012 Remove `remove_orphaned_worktree()` function from tmux-plugin/lib/common.sh
- [x] T013 Remove `cleanup_orphaned_worktree()` function from tmux-plugin/lib/common.sh

**Checkpoint**: Foundational metadata functions ready - user story implementation can now begin

---

## Phase 3: User Story 1 - CLIでセッションを追加する (Priority: P1) MVP

**Goal**: ユーザーが `tower add <path>` でセッションを作成できる

**Independent Test**: `tower add /tmp/test-dir` を実行し、セッションが作成されClaude Codeが起動することを確認

### Tests for User Story 1

- [x] T014 [P] [US1] Create test file tests/test_session_add.bats with test cases for tower add command
- [x] T015 [P] [US1] Add test: tower add creates session with valid directory path
- [x] T016 [P] [US1] Add test: tower add with -n option uses custom session name
- [x] T017 [P] [US1] Add test: tower add fails if path does not exist
- [x] T018 [P] [US1] Add test: tower add fails if path is not a directory
- [x] T019 [P] [US1] Add test: tower add fails if session name already exists

### Implementation for User Story 1

- [x] T020 [US1] Create CLI entry point script tmux-plugin/scripts/tower with add/rm subcommand routing
- [x] T021 [US1] Create tmux-plugin/scripts/session-add.sh implementing `tower add` per contracts/cli.md
- [x] T022 [US1] Implement path validation (exists, is directory) in session-add.sh
- [x] T023 [US1] Implement session name derivation from directory name in session-add.sh
- [x] T024 [US1] Implement -n/--name option parsing in session-add.sh
- [x] T025 [US1] Update `create_session()` in tmux-plugin/lib/common.sh to accept only (name, directory_path)
- [x] T026 [US1] Update `_create_simple_session()` in tmux-plugin/lib/common.sh to save v2 metadata
- [x] T027 [US1] Add executable permission to tmux-plugin/scripts/tower
- [x] T028 [US1] Run tests/test_session_add.bats and verify all tests pass

**Checkpoint**: `tower add` is fully functional - users can create sessions via CLI

---

## Phase 4: User Story 2 - CLIでセッションを削除する (Priority: P1)

**Goal**: ユーザーが `tower rm <name>` でセッションを削除できる（ディレクトリは保持）

**Independent Test**: `tower rm session-name` を実行し、セッションが削除されるがディレクトリは残っていることを確認

### Tests for User Story 2

- [x] T029 [P] [US2] Create test file tests/test_session_delete_v2.bats with v2 deletion test cases
- [x] T030 [P] [US2] Add test: tower rm deletes session metadata
- [x] T031 [P] [US2] Add test: tower rm does NOT delete directory
- [x] T032 [P] [US2] Add test: tower rm with -f skips confirmation
- [x] T033 [P] [US2] Add test: tower rm fails if session does not exist

### Implementation for User Story 2

- [x] T034 [US2] Update tmux-plugin/scripts/session-delete.sh to accept -f/--force option
- [x] T035 [US2] Update `delete_session()` in tmux-plugin/lib/common.sh to remove worktree deletion logic
- [x] T036 [US2] Ensure delete_session() only removes metadata and tmux session (not directories)
- [x] T037 [US2] Update confirmation message to NOT mention worktree/branch deletion
- [x] T038 [US2] Run tests/test_session_delete_v2.bats and verify all tests pass

**Checkpoint**: `tower rm` is fully functional - users can delete sessions without losing directories

---

## Phase 5: User Story 3 - Navigatorでセッション一覧を確認する (Priority: P2)

**Goal**: Navigatorでセッション名とパスが表示される（タイプアイコン廃止）

**Independent Test**: `prefix + t` でNavigatorを開き、セッション名とパスが一覧表示されることを確認

### Tests for User Story 3

- [x] T039 [P] [US3] Update tests/test_navigator.bats to verify path display instead of type icon

### Implementation for User Story 3

- [x] T040 [US3] Update `build_session_list()` in tmux-plugin/scripts/navigator-list.sh to show path instead of type icon
- [x] T041 [US3] Use `shorten_path()` to display ~ for home directory in navigator-list.sh
- [x] T042 [US3] Adjust column widths for session name and path display in navigator-list.sh
- [x] T043 [US3] Remove `n` key handler (create_session_inline) from tmux-plugin/scripts/navigator-list.sh
- [x] T044 [US3] Remove `D` key handler (delete_selected) from tmux-plugin/scripts/navigator-list.sh
- [x] T045 [US3] Remove `create_session_inline()` function from navigator-list.sh
- [x] T046 [US3] Remove `delete_selected()` function from navigator-list.sh
- [x] T047 [US3] Update footer help text in navigator-list.sh (remove n:new D:del)
- [x] T048 [US3] Run tests/test_navigator.bats and verify path display works correctly

**Checkpoint**: Navigator shows simplified session list with paths

---

## Phase 6: User Story 4 - Navigatorからセッションにアタッチする (Priority: P2)

**Goal**: 既存のアタッチ機能が引き続き動作することを確認

**Independent Test**: NavigatorでセッションをEnterで選択し、アタッチできることを確認

### Implementation for User Story 4

- [x] T049 [US4] Verify Enter key attach functionality still works in navigator-list.sh (no changes expected)
- [x] T050 [US4] Verify `r` key restore functionality works with v2 metadata in navigator-list.sh
- [x] T051 [US4] Update `restore_session()` in tmux-plugin/lib/common.sh to use directory_path from v2 metadata

**Checkpoint**: Navigator attach and restore work correctly with v2 metadata

---

## Phase 7: User Story 5 - 既存v1セッションの後方互換性 (Priority: P3)

**Goal**: v1形式のmetadataを持つセッションが引き続き動作する

**Independent Test**: v1形式のmetadataファイルを配置し、Navigatorで表示・操作できることを確認

### Tests for User Story 5

- [x] T052 [P] [US5] Update tests/test_metadata.bats to test v1 format loading
- [x] T053 [P] [US5] Add test: load_metadata reads worktree_path as directory_path
- [x] T054 [P] [US5] Add test: load_metadata reads repository_path as fallback for directory_path

### Implementation for User Story 5

- [x] T055 [US5] Verify load_metadata() correctly maps v1 fields to v2 structure in common.sh
- [x] T056 [US5] Test v1 worktree session appears in Navigator with correct path
- [x] T057 [US5] Verify v1 session deletion does NOT delete worktree directory
- [x] T058 [US5] Run tests/test_metadata.bats with v1 compatibility tests

**Checkpoint**: All existing v1 sessions continue to work with v2 codebase

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Cleanup and documentation

- [x] T059 [P] Remove worktree cleanup logic from tmux-plugin/scripts/cleanup.sh
- [x] T060 [P] Update tmux-plugin/scripts/session-new.sh to delegate to session-add.sh or mark deprecated
- [x] T061 [P] Run shellcheck on all modified scripts
- [x] T062 [P] Run full test suite with `make test`
- [x] T063 Add migration guide section to README.md explaining v1→v2 changes
- [x] T064 Update tmux-plugin/README.md with new CLI commands (tower add/rm)
- [x] T065 Remove backup file tmux-plugin/lib/common.sh.v1.bak after verification

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup - BLOCKS all user stories
- **User Stories (Phase 3-7)**: All depend on Foundational phase completion
  - US1 and US2 can proceed in parallel (different scripts)
  - US3 depends on US1/US2 for metadata format
  - US4 depends on US3 for Navigator changes
  - US5 can proceed in parallel with US3/US4 (testing compatibility)
- **Polish (Phase 8)**: Depends on all user stories complete

### User Story Dependencies

| Story | Depends On | Can Run Parallel With |
|-------|------------|----------------------|
| US1 (tower add) | Foundational | US2 |
| US2 (tower rm) | Foundational | US1 |
| US3 (Navigator display) | US1, US2 | US5 |
| US4 (Navigator attach) | US3 | US5 |
| US5 (v1 compat) | Foundational | US3, US4 |

### Within Each User Story

1. Tests MUST be written and FAIL before implementation
2. Core logic before integration
3. Run tests after implementation
4. Story complete before checkpoint

### Parallel Opportunities

**Foundational Phase**:
- T006, T007, T008, T009 can run in parallel (removing constants/functions)
- T010, T011, T012, T013 can run in parallel (removing worktree functions)

**User Story 1**:
- T014-T019 (tests) can run in parallel
- T020, T021 can run in parallel (different scripts)

**User Story 2**:
- T029-T033 (tests) can run in parallel

**Cross-Story**:
- US1 and US2 can be worked on simultaneously
- US3 and US5 can be worked on simultaneously after US1/US2

---

## Parallel Example: User Story 1

```bash
# Launch all tests together:
Task: "Create test file tests/test_session_add.bats"
Task: "Add test: tower add creates session with valid directory path"
Task: "Add test: tower add with -n option uses custom session name"

# Launch CLI scripts together:
Task: "Create CLI entry point tmux-plugin/scripts/tower"
Task: "Create tmux-plugin/scripts/session-add.sh"
```

---

## Implementation Strategy

### MVP First (User Stories 1 & 2 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL)
3. Complete Phase 3: User Story 1 (tower add)
4. Complete Phase 4: User Story 2 (tower rm)
5. **STOP and VALIDATE**: CLI workflow complete, test independently
6. Users can now create/delete sessions via CLI

### Incremental Delivery

1. Setup + Foundational → Core ready
2. Add US1 + US2 → CLI complete → MVP!
3. Add US3 → Navigator updated → Better UX
4. Add US4 → Attach verified → Full navigation
5. Add US5 → v1 compatibility → No breaking changes for existing users
6. Polish → Production ready

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story
- Each user story should be independently completable and testable
- Verify tests fail before implementing
- Commit after each task or logical group
- Run `make lint` frequently to catch shellcheck issues early
