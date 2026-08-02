#!/usr/bin/env bats
# nav_read_key: the guard against the orphaned-terminal busy-loop.
# Root cause it defends: when a view's tmux pane vanishes, `read -rsn1 -t`
# returns EOF (exit 1) instantly every call, spinning the CPU for days.
# nav_read_key must (a) fire — return 2 — after a run of instant EOFs so the
# caller can exit, and (b) NEVER fire on a genuine idle (timeouts), or a
# normally-waiting Navigator would quit itself.

load 'test_helper'

setup() {
    source_common
}

@test "nav_read_key: returns 0 and captures the key when input is available" {
    run bash -c '
        source "'"$PROJECT_ROOT"'/tmux-plugin/lib/common.sh" 2>/dev/null
        set +e
        printf "j" | { nav_read_key key 1; rc=$?; echo "rc=$rc key=$key"; }
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"rc=0"* ]]
    [[ "$output" == *"key=j"* ]]
}

@test "nav_read_key: returns 1 (timeout) on a genuine idle, never fires the guard" {
    # An open fd with no writer -> read times out (rc>128) -> nav_read_key
    # maps to rc 1 and resets the streak. The guard (rc 2) must never appear.
    run bash -c '
        source "'"$PROJECT_ROOT"'/tmux-plugin/lib/common.sh" 2>/dev/null
        set +e
        fifo=$(mktemp -u); mkfifo "$fifo"; exec 3<>"$fifo"
        fired=0
        for i in 1 2 3 4 5 6; do
            nav_read_key key 0.15 <&3; rc=$?
            [ "$rc" -eq 2 ] && fired=1
        done
        exec 3>&-; rm -f "$fifo"
        echo "fired=$fired last_rc=$rc streak=$NAV_EOF_STREAK"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"fired=0"* ]]
    # each idle tick is a timeout, so the EOF streak stays at zero
    [[ "$output" == *"streak=0"* ]]
}

@test "nav_read_key: fires (returns 2) after a run of instant EOFs" {
    # stdin closed -> EOF every call. The guard must fire at the limit and
    # not spin. Bound the whole thing so a regression (busy-loop) times out.
    run timeout 10 bash -c '
        source "'"$PROJECT_ROOT"'/tmux-plugin/lib/common.sh" 2>/dev/null
        set +e
        n=0
        while : ; do
            nav_read_key key 0.25 </dev/null; rc=$?
            n=$((n+1))
            [ "$rc" -eq 2 ] && { echo "FIRED n=$n"; break; }
            [ "$n" -gt 100 ] && { echo "BUSY_LOOP n=$n"; break; }
        done
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"FIRED"* ]]
    [[ "$output" != *"BUSY_LOOP"* ]]
}

@test "nav_read_key: EOF streak is bounded by NAV_EOF_LIMIT" {
    # With a low limit, the guard fires that many EOFs in.
    run timeout 10 bash -c '
        export TOWER_NAV_EOF_LIMIT=3
        source "'"$PROJECT_ROOT"'/tmux-plugin/lib/common.sh" 2>/dev/null
        set +e
        n=0
        while : ; do
            nav_read_key key 0.25 </dev/null; rc=$?
            n=$((n+1))
            [ "$rc" -eq 2 ] && { echo "n=$n"; break; }
            [ "$n" -gt 50 ] && { echo "n=OVER"; break; }
        done
    '
    [ "$status" -eq 0 ]
    [[ "$output" == "n=3" ]]
}

@test "nav_read_key: a key after some EOFs resets the streak (transient EOF is not fatal)" {
    # Not every non-timeout is a dead terminal; a couple of EOFs followed by a
    # key must reset, so a brief hiccup never accumulates toward the guard.
    run bash -c '
        export TOWER_NAV_EOF_LIMIT=5
        source "'"$PROJECT_ROOT"'/tmux-plugin/lib/common.sh" 2>/dev/null
        set +e
        nav_read_key key 0.25 </dev/null; # streak 1
        nav_read_key key 0.25 </dev/null; # streak 2
        # Heredoc (not a pipe) so the streak reset happens in THIS shell, not
        # a subshell — mirrors how the view loops call it inline.
        nav_read_key key 1 <<<"k"          # key -> reset
        echo "streak_after_key=$NAV_EOF_STREAK"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"streak_after_key=0"* ]]
}
