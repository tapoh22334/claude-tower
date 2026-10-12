#!/usr/bin/env bats
# Unit tests for fork detection (claude-sessions.sh)

load 'test_helper'

PARENT="cccccccc-1111-4111-8111-111111111111"
FORK="dddddddd-2222-4222-8222-222222222222"
SOLO="eeeeeeee-3333-4333-8333-333333333333"
SLUG="-home-user-proj"
DIR="/home/user/proj"

setup() {
    source_common
    setup_test_env
}

teardown() {
    teardown_test_env
}

# Write one transcript of $3 messages, all carrying uuid $4, mtime $5.
_mk_transcript() {
    local sid="$1" slug="$2" n="$3" uuid="$4" stamp="$5"
    local d="${CLAUDE_PROJECTS_DIR}/${slug}"
    mkdir -p "$d"
    local f="${d}/${sid}.jsonl" i
    : >"$f"
    for ((i = 0; i < n; i++)); do
        printf '{"type":"user","cwd":"%s","sessionId":"%s","uuid":"%s"}\n' \
            "$DIR" "$sid" "$uuid" >>"$f"
    done
    touch -d "$stamp" "$f"
    echo "$f"
}

@test "find_fork_parent: returns parent sessionId for a fork" {
    create_fork_pair_jsonl "$SLUG" "$PARENT" "$FORK" "$DIR" >/dev/null
    run find_fork_parent "$FORK"
    [ "$status" -eq 0 ]
    [ "$output" = "$PARENT" ]
}

@test "find_fork_parent: returns 1 for an independent session (no shared uuids)" {
    # SOLO has its own uuids; another session shares none.
    local dir="${CLAUDE_PROJECTS_DIR}/${SLUG}"
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
    create_fork_pair_jsonl "$SLUG" "$PARENT" "$FORK" "$DIR" >/dev/null
    # Asking for the PARENT must not return the (newer) fork.
    run find_fork_parent "$PARENT"
    [ "$status" -eq 1 ]
}

@test "find_fork_parent: nearest older sharing candidate wins (#29)" {
    # A chain: grandparent -> parent -> child, all carrying the same copied
    # uuid. The child was forked from the NEAREST one, not the oldest.
    local u="aaaaaaaa-0000-4000-8000-00000000000f"
    local gp="11111111-1111-4111-8111-111111111111"
    local pa="22222222-2222-4222-8222-222222222222"
    local ch="33333333-3333-4333-8333-333333333333"
    _mk_transcript "$gp" "$SLUG" 2 "$u" '2020-01-01 00:00:00' >/dev/null
    _mk_transcript "$pa" "$SLUG" 2 "$u" '2020-01-01 00:00:30' >/dev/null
    _mk_transcript "$ch" "$SLUG" 2 "$u" '2020-01-01 00:01:00' >/dev/null
    run find_fork_parent "$ch"
    [ "$status" -eq 0 ]
    [ "$output" = "$pa" ]
}

@test "find_fork_parent: same-mtime candidates resolve deterministically" {
    # Two candidates written in the same second both share the child's uuid.
    # The documented rule is lexically smallest sessionId; the point is that
    # the answer is the SAME on every call, not glob-order roulette.
    local u="aaaaaaaa-0000-4000-8000-00000000001f"
    local a="11111111-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    local b="99999999-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    local ch="44444444-4444-4444-8444-444444444444"
    _mk_transcript "$a" "$SLUG" 2 "$u" '2020-01-01 00:00:10' >/dev/null
    _mk_transcript "$b" "$SLUG" 2 "$u" '2020-01-01 00:00:10' >/dev/null
    _mk_transcript "$ch" "$SLUG" 2 "$u" '2020-01-01 00:00:20' >/dev/null
    run find_fork_parent "$ch"
    [ "$status" -eq 0 ]
    [ "$output" = "$a" ]
    # Same answer again — no dependence on glob expansion order.
    run find_fork_parent "$ch"
    [ "$output" = "$a" ]
}

@test "find_fork_parent: uuid scan is bounded by MESSAGES, not by matching lines" {
    # `grep -o -m N` stops after N lines that MATCH, skipping over every
    # non-matching line on the way — so on a transcript whose leading records
    # carry no uuid (queue-operations, summaries) it reads arbitrarily deep
    # and can match a uuid that is nowhere near the copied fork prefix.
    # A fork's copy always starts at message 1, so the scan must be a window
    # on the first N messages: `head -n N` then collect.
    #
    # Here the candidate shares a uuid only at message 20. That is not a
    # copied prefix, so it must NOT be reported as a parent.
    local d="${CLAUDE_PROJECTS_DIR}/${SLUG}"
    mkdir -p "$d"
    local late="aaaaaaaa-0000-4000-8000-00000000002f"
    local pa="55555555-5555-4555-8555-555555555555"
    local ch="66666666-6666-4666-8666-666666666666"
    local pf="${d}/${pa}.jsonl" cf="${d}/${ch}.jsonl"
    : >"$pf"
    local i
    # 19 records with no uuid field at all, then the shared one.
    for ((i = 1; i <= 19; i++)); do
        printf '{"type":"queue-operation","op":"enqueue","seq":%d}\n' "$i" >>"$pf"
    done
    printf '{"type":"user","sessionId":"%s","uuid":"%s"}\n' "$pa" "$late" >>"$pf"
    printf '{"type":"user","sessionId":"%s","uuid":"%s"}\n' "$ch" "$late" >"$cf"
    touch -d '2020-01-01 00:00:00' "$pf"
    touch -d '2020-01-01 00:00:10' "$cf"
    run find_fork_parent "$ch"
    [ "$status" -eq 1 ]
}

@test "find_fork_parent: a copied prefix is found past non-matching leading records" {
    # The mirror case: the shared uuid sits within the first N MESSAGES but
    # after records that carry no uuid. The window must still reach it.
    local d="${CLAUDE_PROJECTS_DIR}/${SLUG}"
    mkdir -p "$d"
    local shared="aaaaaaaa-0000-4000-8000-00000000003f"
    local pa="aaaa5555-5555-4555-8555-555555555555"
    local ch="bbbb6666-6666-4666-8666-666666666666"
    local pf="${d}/${pa}.jsonl" cf="${d}/${ch}.jsonl"
    printf '{"type":"queue-operation","op":"enqueue"}\n' >"$pf"
    printf '{"type":"queue-operation","op":"enqueue"}\n' >>"$pf"
    printf '{"type":"user","sessionId":"%s","uuid":"%s"}\n' "$pa" "$shared" >>"$pf"
    printf '{"type":"queue-operation","op":"enqueue"}\n' >"$cf"
    printf '{"type":"user","sessionId":"%s","uuid":"%s"}\n' "$ch" "$shared" >>"$cf"
    touch -d '2020-01-01 00:00:00' "$pf"
    touch -d '2020-01-01 00:00:10' "$cf"
    run find_fork_parent "$ch"
    [ "$status" -eq 0 ]
    [ "$output" = "$pa" ]
}

@test "find_fork_parent: compaction is not a fork (#29)" {
    # Compaction continues one session into a new file: same sessionId, but
    # the new file starts from the summary, so no uuid crosses the files.
    # Without shared uuids there is no parent to report.
    local d="${CLAUDE_PROJECTS_DIR}/${SLUG}"
    mkdir -p "$d"
    local sid="77777777-7777-4777-8777-777777777777"
    local cont="88888888-8888-4888-8888-888888888888"
    printf '{"type":"user","sessionId":"%s","uuid":"aaaaaaaa-0000-4000-8000-000000000101"}\n' "$sid" >"${d}/${sid}.jsonl"
    printf '{"type":"assistant","sessionId":"%s","uuid":"aaaaaaaa-0000-4000-8000-000000000102"}\n' "$sid" >>"${d}/${sid}.jsonl"
    # The continuation file: same sessionId, entirely fresh uuids.
    printf '{"type":"user","sessionId":"%s","uuid":"aaaaaaaa-0000-4000-8000-000000000201"}\n' "$sid" >"${d}/${cont}.jsonl"
    printf '{"type":"assistant","sessionId":"%s","uuid":"aaaaaaaa-0000-4000-8000-000000000202"}\n' "$sid" >>"${d}/${cont}.jsonl"
    touch -d '2020-01-01 00:00:00' "${d}/${sid}.jsonl"
    touch -d '2020-01-01 00:00:10' "${d}/${cont}.jsonl"
    run find_fork_parent "$cont"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "list_fork_sessions: lists an unregistered fork with its parent and pid" {
    create_fork_pair_jsonl "$SLUG" "$PARENT" "$FORK" "$DIR" >/dev/null
    # Stub the live-process source: the fork is live at pid 4242.
    list_live_claude_processes() {
        printf '%s\t%s\t%s\n' "$FORK" "4242" "$DIR"
    }
    # Nothing is registered in Tower.
    has_metadata() { return 1; }
    run list_fork_sessions "$DIR"
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '%s\t%s\t%s' "$FORK" "$PARENT" "4242")" ]
}

@test "list_fork_sessions: skips forks already registered in Tower" {
    create_fork_pair_jsonl "$SLUG" "$PARENT" "$FORK" "$DIR" >/dev/null
    list_live_claude_processes() { printf '%s\t%s\t%s\n' "$FORK" "4242" "$DIR"; }
    has_metadata() { return 0; }   # everything is registered
    run list_fork_sessions "$DIR"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "list_fork_sessions: skips live processes with no fork parent" {
    list_live_claude_processes() { printf '%s\t%s\t%s\n' "$SOLO" "4243" "$DIR"; }
    has_metadata() { return 1; }
    run list_fork_sessions "$DIR"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "list_fork_sessions: uses a pre-fetched process table instead of rescanning" {
    create_fork_pair_jsonl "$SLUG" "$PARENT" "$FORK" "$DIR" >/dev/null
    # A caller-supplied table must be used verbatim; the scan must not run.
    list_live_claude_processes() { echo "RESCANNED" >&2; return 1; }
    has_metadata() { return 1; }
    run list_fork_sessions "$DIR" "$(printf '%s\t%s\t%s' "$FORK" "7777" "$DIR")"
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '%s\t%s\t%s' "$FORK" "$PARENT" "7777")" ]
}

@test "list_fork_sessions: an empty pre-fetched table yields nothing" {
    # Distinguishes "no live processes" from "no table passed" — an empty
    # string must not fall back to a fresh scan.
    list_live_claude_processes() { printf '%s\t%s\t%s\n' "$FORK" "4242" "$DIR"; }
    has_metadata() { return 1; }
    run list_fork_sessions "$DIR" ""
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
