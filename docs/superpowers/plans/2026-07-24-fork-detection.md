# Fork Detection + Nested Display Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Detect `/fork`-ed Claude sessions from their transcripts and show each fork nested under its parent session in the Tower Navigator list.

**Architecture:** Add two detection functions to `lib/claude-sessions.sh` that recover the parent↔fork link from the only on-disk signal — message `uuid`s copied verbatim into the fork's new-sessionId transcript. The Navigator's group-building loop consumes these to insert an indented fork row directly after its parent's row. Registered-session enumeration (`list_all_sessions`) is unchanged.

**Tech Stack:** Bash 4.0+, bats (tests), tmux. No new dependencies.

## Global Constraints

- ShellCheck compliant (exclude SC2034, SC1091, SC2317).
- 4-space indentation (shfmt -i 4 -ci).
- Internal functions prefixed with underscore: `_internal_func()`.
- Files under 500 lines.
- `grep -o`/`-m` are GNU extensions; keep flags separated (no `-om1`).
- Slug dirs start with `-`; every grep/stat on transcript paths uses absolute paths and the `--` separator.
- Tests: bats, `load 'test_helper'`, `source_common` + `setup_test_env` in `setup()`.

---

### Task 1: `find_fork_parent` — recover a fork's parent sessionId

**Files:**
- Modify: `tmux-plugin/lib/claude-sessions.sh` (add function after `find_session_jsonl`, ~line 28)
- Test: `tests/test_fork_detection.bats` (create)
- Modify: `tests/test_helper.bash` (add `create_fork_pair_jsonl` helper after `create_empty_jsonl`, ~line 95)

**Interfaces:**
- Consumes: `find_session_jsonl(session_id)` → jsonl path; `get_session_cwd(jsonl)` → cwd.
- Produces: `find_fork_parent(child_session_id)` → prints parent Claude sessionId and returns 0 when found; returns 1 (no output) otherwise. A "parent" is another `*.jsonl` in the SAME slug directory, with an OLDER mtime, that shares at least one of the child's first-5 message `uuid`s.

- [ ] **Step 1: Add the test helper for fork/parent fixtures**

In `tests/test_helper.bash`, after `create_empty_jsonl` (ends ~line 95), add:

```bash
# Create a parent transcript and a fork transcript that copies the parent's
# first messages by uuid (sessionId rewritten to the fork's id) — the real
# on-disk fork signature. $1 slug, $2 parent uuid, $3 fork uuid, $4 cwd.
# The fork file is touched newer than the parent.
create_fork_pair_jsonl() {
    local slug="$1" parent="$2" fork="$3" cwd="$4"
    local dir="${CLAUDE_PROJECTS_DIR}/${slug}"
    mkdir -p "$dir"
    local pf="${dir}/${parent}.jsonl" ff="${dir}/${fork}.jsonl"
    local u1="aaaaaaaa-0000-4000-8000-000000000001"
    local u2="aaaaaaaa-0000-4000-8000-000000000002"
    # Parent: two messages with uuids u1,u2 under the parent sessionId.
    printf '{"type":"user","cwd":"%s","sessionId":"%s","uuid":"%s"}\n' "$cwd" "$parent" "$u1" >"$pf"
    printf '{"type":"assistant","cwd":"%s","sessionId":"%s","uuid":"%s"}\n' "$cwd" "$parent" "$u2" >>"$pf"
    # Fork: same uuids u1,u2 but sessionId rewritten to the fork id, plus a
    # new fork-only message.
    printf '{"type":"user","cwd":"%s","sessionId":"%s","uuid":"%s"}\n' "$cwd" "$fork" "$u1" >"$ff"
    printf '{"type":"assistant","cwd":"%s","sessionId":"%s","uuid":"%s"}\n' "$cwd" "$fork" "$u2" >>"$ff"
    printf '{"type":"user","cwd":"%s","sessionId":"%s","uuid":"%s"}\n' "$cwd" "$fork" "bbbbbbbb-0000-4000-8000-000000000003" >>"$ff"
    # Ensure fork is newer than parent.
    touch -d '2020-01-01 00:00:00' "$pf"
    touch -d '2020-01-01 00:00:10' "$ff"
    printf '%s\t%s\n' "$pf" "$ff"
}
```

- [ ] **Step 2: Write the failing test**

Create `tests/test_fork_detection.bats`:

```bash
#!/usr/bin/env bats
# Unit tests for fork detection (claude-sessions.sh)

load 'test_helper'

PARENT="cccccccc-1111-4111-8111-111111111111"
FORK="dddddddd-2222-4222-8222-222222222222"
SOLO="eeeeeeee-3333-4333-8333-333333333333"

setup() {
    source_common
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "find_fork_parent: returns parent sessionId for a fork" {
    create_fork_pair_jsonl "-home-user-proj" "$PARENT" "$FORK" "/home/user/proj" >/dev/null
    run find_fork_parent "$FORK"
    [ "$status" -eq 0 ]
    [ "$output" = "$PARENT" ]
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `./tests/bats/bin/bats tests/test_fork_detection.bats -f "returns parent"`
Expected: FAIL — `find_fork_parent: command not found`.

- [ ] **Step 4: Implement `find_fork_parent`**

In `tmux-plugin/lib/claude-sessions.sh`, after `find_session_jsonl` (the `}` at ~line 28), add:

```bash
# Recover a fork's parent Claude sessionId. A /fork copies the parent's
# messages into a NEW sessionId transcript, keeping their uuids but
# rewriting sessionId; forkedFrom is not persisted. So the fork's first
# messages share uuids with the parent's transcript in the same slug dir.
# Output: parent sessionId (returns 1, no output, when not a fork).
# Match rule: another *.jsonl in the same dir, older mtime, sharing at
# least one of the child's first-5 uuids. Nearest-older wins.
_FORK_SCAN_LINES=5
find_fork_parent() {
    local child_id="$1"
    local child_jsonl child_dir child_mtime
    child_jsonl=$(find_session_jsonl "$child_id") || return 1
    child_dir=$(dirname -- "$child_jsonl")
    child_mtime=$(stat -c %Y -- "$child_jsonl" 2>/dev/null) || return 1

    local child_uuids
    child_uuids=$(grep -o -m "$_FORK_SCAN_LINES" '"uuid":"[^"]*"' -- "$child_jsonl" 2>/dev/null | sort -u)
    [[ -n "$child_uuids" ]] || return 1

    local best="" best_mtime=0 f cand_id cand_mtime shared
    for f in "$child_dir"/*.jsonl; do
        [[ -f "$f" ]] || continue
        [[ "$f" == "$child_jsonl" ]] && continue
        cand_id=$(basename -- "$f" .jsonl)
        [[ "$cand_id" =~ ^[0-9a-f-]{36}$ ]] || continue
        cand_mtime=$(stat -c %Y -- "$f" 2>/dev/null) || continue
        ((cand_mtime <= child_mtime)) || continue
        shared=$(grep -o -m "$_FORK_SCAN_LINES" '"uuid":"[^"]*"' -- "$f" 2>/dev/null \
            | sort -u | grep -Fx -f <(printf '%s\n' "$child_uuids") | head -n 1)
        [[ -n "$shared" ]] || continue
        if ((cand_mtime >= best_mtime)); then
            best="$cand_id"
            best_mtime=$cand_mtime
        fi
    done
    [[ -n "$best" ]] || return 1
    printf '%s\n' "$best"
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `./tests/bats/bin/bats tests/test_fork_detection.bats -f "returns parent"`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add tmux-plugin/lib/claude-sessions.sh tests/test_fork_detection.bats tests/test_helper.bash
git commit -m "feat: find_fork_parent — recover a fork's parent via shared message uuids"
```

---

### Task 2: `find_fork_parent` negative cases (no false positives)

**Files:**
- Test: `tests/test_fork_detection.bats` (add tests)
- Modify: `tmux-plugin/lib/claude-sessions.sh` (only if a test fails)

**Interfaces:**
- Consumes: `find_fork_parent` from Task 1; `create_mock_jsonl` (existing helper — emits no `uuid` fields).

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_fork_detection.bats`:

```bash
@test "find_fork_parent: returns 1 for an independent session (no shared uuids)" {
    # SOLO has its own uuids; another session shares none.
    local dir="${CLAUDE_PROJECTS_DIR}/-home-user-proj"
    mkdir -p "$dir"
    printf '{"type":"user","cwd":"/p","sessionId":"%s","uuid":"11110000-0000-4000-8000-000000000001"}\n' "$SOLO" >"${dir}/${SOLO}.jsonl"
    printf '{"type":"user","cwd":"/p","sessionId":"other","uuid":"99990000-0000-4000-8000-000000000009"}\n' >"${dir}/99999999-9999-4999-8999-999999999999.jsonl"
    run find_fork_parent "$SOLO"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "find_fork_parent: returns 1 when the transcript is missing" {
    run find_fork_parent "00000000-0000-4000-8000-000000000000"
    [ "$status" -eq 1 ]
}

@test "find_fork_parent: does not match a NEWER sibling as parent" {
    create_fork_pair_jsonl "-home-user-proj" "$PARENT" "$FORK" "/home/user/proj" >/dev/null
    # Asking for the PARENT must not return the (newer) fork.
    run find_fork_parent "$PARENT"
    [ "$status" -eq 1 ]
}
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `./tests/bats/bin/bats tests/test_fork_detection.bats`
Expected: all PASS. (The `find_fork_parent` logic already handles these — older-mtime gate rejects the newer sibling; no shared uuids rejects the independent pair.)

- [ ] **Step 3: Commit**

```bash
git add tests/test_fork_detection.bats
git commit -m "test: find_fork_parent negative cases (independent, missing, newer-sibling)"
```

---

### Task 3: `list_fork_sessions` — enumerate unregistered forks in a directory

**Files:**
- Modify: `tmux-plugin/lib/claude-sessions.sh` (add after `count_unregistered_processes_in_dir`, ~line 188)
- Test: `tests/test_fork_detection.bats` (add tests)

**Interfaces:**
- Consumes: `list_live_claude_processes` → `<sid>\t<pid>\t<cwd>` lines (stubbed in tests); `has_metadata(tower_<sid>)` (stubbed in tests); `find_fork_parent` from Task 1.
- Produces: `list_fork_sessions(dir)` → prints `<child_sid>\t<parent_sid>\t<pid>` for each live, unregistered process in `dir` whose `find_fork_parent` resolves. Prints nothing (returns 0) when none.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_fork_detection.bats`:

```bash
@test "list_fork_sessions: lists an unregistered fork with its parent and pid" {
    create_fork_pair_jsonl "-home-user-proj" "$PARENT" "$FORK" "/home/user/proj" >/dev/null
    # Stub the live-process source: the fork is live at pid 4242.
    list_live_claude_processes() {
        printf '%s\t%s\t%s\n' "$FORK" "4242" "/home/user/proj"
    }
    # Nothing is registered in Tower.
    has_metadata() { return 1; }
    run list_fork_sessions "/home/user/proj"
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '%s\t%s\t%s' "$FORK" "$PARENT" "4242")" ]
}

@test "list_fork_sessions: skips forks already registered in Tower" {
    create_fork_pair_jsonl "-home-user-proj" "$PARENT" "$FORK" "/home/user/proj" >/dev/null
    list_live_claude_processes() { printf '%s\t%s\t%s\n' "$FORK" "4242" "/home/user/proj"; }
    has_metadata() { return 0; }   # everything is registered
    run list_fork_sessions "/home/user/proj"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "list_fork_sessions: skips live processes with no fork parent" {
    list_live_claude_processes() { printf '%s\t%s\t%s\n' "$SOLO" "4243" "/home/user/proj"; }
    has_metadata() { return 1; }
    run list_fork_sessions "/home/user/proj"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/bats/bin/bats tests/test_fork_detection.bats -f "list_fork_sessions"`
Expected: FAIL — `list_fork_sessions: command not found`.

- [ ] **Step 3: Implement `list_fork_sessions`**

In `tmux-plugin/lib/claude-sessions.sh`, after `count_unregistered_processes_in_dir` (its closing `}` ~line 188), add:

```bash
# Live, unregistered forks whose directory is $1.
# Output: <child_sid>\t<parent_sid>\t<pid>   one line per fork.
list_fork_sessions() {
    local dir="$1"
    local sid pid cwd parent
    while IFS=$'\t' read -r sid pid cwd; do
        [[ "$cwd" == "$dir" ]] || continue
        has_metadata "tower_${sid}" && continue
        parent=$(find_fork_parent "$sid") || continue
        printf '%s\t%s\t%s\n' "$sid" "$parent" "$pid"
    done < <(list_live_claude_processes)
    return 0
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./tests/bats/bin/bats tests/test_fork_detection.bats -f "list_fork_sessions"`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add tmux-plugin/lib/claude-sessions.sh tests/test_fork_detection.bats
git commit -m "feat: list_fork_sessions — live unregistered forks with parent + pid"
```

---

### Task 4: Nest fork rows under their parent in the Navigator

**Files:**
- Modify: `tmux-plugin/scripts/navigator-list.sh` (group-building loop, ~lines 282-291; and `_session_label`/selection helpers as noted)

**Interfaces:**
- Consumes: `list_fork_sessions(dir)` from Task 3; `get_session_title`, `truncate_display`, `_compose_row`, `_content_width`, `NAV_RIGHT_COL`, `NAV_C_EXTERNAL` (existing).
- Produces: fork rows appended to `SESSION_IDS`/`SESSION_DISPLAYS`/`SESSION_DIRS`/`SESSION_HEADERS`, with the fork's raw Claude sessionId (no `tower_` prefix) as its `SESSION_IDS` entry.

- [ ] **Step 1: Add a fork-row label helper**

In `tmux-plugin/scripts/navigator-list.sh`, after `_session_label` (its `}` ~line 121), add:

```bash
# Row label for a nested fork: "↳ " + the fork's conversation title.
_fork_label() {
    local claude_id="$1"
    local label
    label=$(get_session_title "$claude_id" 2>/dev/null) || label=""
    [[ -z "$label" ]] && label="${claude_id:0:7}"
    local width budget
    width=$(_content_width)
    # Extra 2 cells of indent vs a normal row (the "↳ " prefix).
    budget=$((width - 6 - NAV_RIGHT_COL))
    ((budget < 18)) && budget=18
    printf '↳ %s\n' "$(truncate_display "$label" "$budget")"
}
```

- [ ] **Step 2: Insert fork rows after each parent row in the group loop**

In `build_session_list`, the inner group loop currently reads (~lines 282-290):

```bash
        for ((j = i; j < ${#raw_ids[@]}; j++)); do
            if [[ "${raw_dirs[$j]}" == "$d" ]]; then
                SESSION_IDS+=("${raw_ids[$j]}")
                SESSION_DISPLAYS+=("${raw_displays[$j]}")
                SESSION_DIRS+=("$d")
                SESSION_HEADERS+=("$header")
                header=""
            fi
        done
```

Replace it with (adds fork children after each parent, then any orphan forks at group end):

```bash
        # Collect this dir's live forks once: child<TAB>parent<TAB>pid.
        local -a fork_child=() fork_parent=()
        local fchild fparent fpid
        while IFS=$'\t' read -r fchild fparent fpid; do
            [[ -n "$fchild" ]] || continue
            fork_child+=("$fchild")
            fork_parent+=("$fparent")
        done < <(list_fork_sessions "$d")

        local m
        for ((j = i; j < ${#raw_ids[@]}; j++)); do
            if [[ "${raw_dirs[$j]}" == "$d" ]]; then
                SESSION_IDS+=("${raw_ids[$j]}")
                SESSION_DISPLAYS+=("${raw_displays[$j]}")
                SESSION_DIRS+=("$d")
                SESSION_HEADERS+=("$header")
                header=""
                # Nest any fork whose parent is this row's Claude id.
                local parent_cid="${raw_ids[$j]#tower_}"
                for ((m = 0; m < ${#fork_child[@]}; m++)); do
                    [[ -n "${fork_child[$m]}" ]] || continue
                    if [[ "${fork_parent[$m]}" == "$parent_cid" ]]; then
                        SESSION_IDS+=("${fork_child[$m]}")
                        SESSION_DISPLAYS+=("$(_compose_row \
                            "${NAV_C_EXTERNAL}◇${NAV_C_NORMAL}" \
                            "$(_fork_label "${fork_child[$m]}")" \
                            "${NAV_C_EXTERNAL}⚡${NAV_C_NORMAL}")")
                        SESSION_DIRS+=("$d")
                        SESSION_HEADERS+=("")
                        fork_child[$m]=""   # consumed
                    fi
                done
            fi
        done
        # Forks whose parent is not a registered row in this group: show
        # them standalone at group end (single external row, no ↳).
        for ((m = 0; m < ${#fork_child[@]}; m++)); do
            [[ -n "${fork_child[$m]}" ]] || continue
            SESSION_IDS+=("${fork_child[$m]}")
            SESSION_DISPLAYS+=("$(_compose_row \
                "${NAV_C_EXTERNAL}◇${NAV_C_NORMAL}" \
                "$(get_session_title "${fork_child[$m]}" 2>/dev/null || echo "${fork_child[$m]:0:7}")" \
                "${NAV_C_EXTERNAL}⚡${NAV_C_NORMAL}")")
            SESSION_DIRS+=("$d")
            SESSION_HEADERS+=("")
        done
```

- [ ] **Step 3: Lint and format**

Run: `make lint && make format`
Expected: shellcheck passes (SC2034/SC1091/SC2317 excluded); shfmt reports no diff for `navigator-list.sh`. Fix any reported issues inline.

- [ ] **Step 4: Smoke-test the list builds without error**

Run:
```bash
cd tmux-plugin && bash -n scripts/navigator-list.sh && echo "syntax ok"
```
Expected: `syntax ok`.

- [ ] **Step 5: Commit**

```bash
git add tmux-plugin/scripts/navigator-list.sh
git commit -m "feat: nest detected forks under their parent in the Navigator list"
```

---

### Task 5: Selecting a fork row resumes the fork's own session

**Files:**
- Modify: `tmux-plugin/scripts/navigator-list.sh` (the external-resume branch, ~line 682)
- Test: manual (documented) — selection wiring has no unit harness in this repo.

**Interfaces:**
- Consumes: the existing external-state resume path (`get_display_state "$selected" == "external"`, ~line 682) and `get_nav_selected`.
- Produces: a fork row (whose `SESSION_IDS` entry is a raw Claude sessionId, not `tower_*`) routes through the external-resume branch instead of the `has_metadata` "Not registered" dead-end.

- [ ] **Step 1: Read the current external branch**

Run: `sed -n '680,700p' tmux-plugin/scripts/navigator-list.sh`
Confirm `restore_selected` returns early with "Not registered — press n to add" when `! has_metadata "$selected"`.

- [ ] **Step 2: Route unregistered fork ids to the external resume path**

In `restore_selected`, replace the `has_metadata` early-return block (~lines 702-708):

```bash
    # Check if metadata exists (can restore)
    if ! has_metadata "$selected"; then
        # No metadata - can't restore
        echo ""
        echo "  ${NAV_C_DIM}Not registered — press n to add${NAV_C_NORMAL}"
        sleep 0.3
        return 0
    fi
```

with:

```bash
    # Check if metadata exists (can restore)
    if ! has_metadata "$selected"; then
        # A selected fork row carries a raw Claude sessionId (no tower_
        # prefix) for a live, unregistered session. Offer to add it so the
        # user can resume it under Tower rather than dead-ending.
        if [[ "$selected" != tower_* ]] && is_claude_process_alive "$selected"; then
            echo ""
            echo "  ${NAV_C_DIM}Fork — press n to add it to Tower${NAV_C_NORMAL}"
            sleep 0.5
            return 0
        fi
        echo ""
        echo "  ${NAV_C_DIM}Not registered — press n to add${NAV_C_NORMAL}"
        sleep 0.3
        return 0
    fi
```

- [ ] **Step 3: Lint and syntax-check**

Run: `make lint && cd tmux-plugin && bash -n scripts/navigator-list.sh && echo "syntax ok"`
Expected: shellcheck passes; `syntax ok`.

- [ ] **Step 4: Commit**

```bash
git add tmux-plugin/scripts/navigator-list.sh
git commit -m "feat: fork row selection points the user to add it to Tower"
```

---

### Task 6: Full test + lint pass and cleanup

**Files:**
- None (verification only), plus removing the throwaway investigation transcripts created during design.

- [ ] **Step 1: Run the fork detection suite**

Run: `./tests/bats/bin/bats tests/test_fork_detection.bats`
Expected: all PASS.

- [ ] **Step 2: Run the full test suite**

Run: `make test`
Expected: no new failures vs. baseline. (If pre-existing failures exist, confirm they are unrelated to fork detection.)

- [ ] **Step 3: Run lint and format checks**

Run: `make lint && make format`
Expected: clean.

- [ ] **Step 4: Remove the throwaway investigation transcripts**

The design phase generated two real transcripts under the scratchpad slug. Remove them so they don't linger as detectable sessions:

```bash
rm -f ~/.claude/projects/-tmp-claude-1000--home-iwase-working-claude-tower-598142dd-7d59-4f24-9e78-b5755b754eb1-scratchpad/64c519ad-ec45-4e25-976a-932e001a0e08.jsonl \
      ~/.claude/projects/-tmp-claude-1000--home-iwase-working-claude-tower-598142dd-7d59-4f24-9e78-b5755b754eb1-scratchpad/5c878742-89b0-4ef6-afad-faca181bfa58.jsonl
```

- [ ] **Step 5: Final commit (if any lint/format fixes were applied)**

```bash
git add -A tmux-plugin/ tests/
git commit -m "chore: fork detection lint/format pass" || echo "nothing to commit"
```
