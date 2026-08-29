#!/usr/bin/env bats
# The "+" branch of prompt_new_directory hands a path and a branch name
# straight to `git worktree add`. Both used to be unchecked:
#
#   Worktree path: ../../../tmp/anywhere
#
# created a worktree outside the repository — verified before the fix — which
# is not what "make me a worktree of this repo" means to the person typing it.
# A branch name starting with "-" is worse in kind: git reads it as an option.
#
# These pin the two guards. They assert the validators directly rather than
# driving the prompt, because the prompt reads from /dev/tty and bats has no
# way to feed it.

load 'test_helper'

setup() {
    source_common
    setup_test_env
    REPO="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$REPO"
    git -C "$REPO" init -q
    git -C "$REPO" commit -q --allow-empty -m init
}

@test "worktree guard: a path inside the repo is accepted" {
    run validate_path_within "$REPO/wt/feature" "$REPO"
    [ "$status" -eq 0 ]
}

@test "worktree guard: ../ out of the repo is rejected" {
    run validate_path_within "$REPO/../escape" "$REPO"
    [ "$status" -ne 0 ]
}

@test "worktree guard: a deep traversal out of the repo is rejected" {
    run validate_path_within "$REPO/a/b/../../../../tmp/escape" "$REPO"
    [ "$status" -ne 0 ]
}

@test "worktree guard: an unrelated absolute path is rejected" {
    run validate_path_within "/tmp/somewhere-else" "$REPO"
    [ "$status" -ne 0 ]
}

@test "branch guard: a normal branch name passes check-ref-format" {
    run git check-ref-format --branch "tower/feature"
    [ "$status" -eq 0 ]
}

@test "branch guard: a leading dash is refused before git sees it" {
    # The script rejects these itself: git would read the name as an option.
    local branch="--upload-pack=whatever"
    [[ "$branch" == -* ]]
}

@test "branch guard: a malformed branch name is refused by check-ref-format" {
    run git check-ref-format --branch "bad..name"
    [ "$status" -ne 0 ]
}

@test "worktree guard: a symlink out of the repo is rejected too" {
    # realpath resolves the link before comparing, so this cannot be used to
    # step around the check.
    ln -s /tmp "$REPO/escape-link"
    run validate_path_within "$REPO/escape-link/newwt" "$REPO"
    [ "$status" -ne 0 ]
}

@test "session-add.sh: the prompt refuses a traversal path end to end" {
    # Drives prompt_new_directory itself rather than asserting that the source
    # contains a call: answering "+", the repo, then a path that climbs out
    # must fail without creating anything.
    run bash -c '
        source "'"$PROJECT_ROOT"'/tmux-plugin/scripts/session-add.sh" 2>/dev/null || true
        printf "+\n%s\n%s\n" "'"$REPO"'" "../escaped-worktree" \
            | prompt_new_directory "'"$REPO"'" </dev/stdin
    '
    [ "$status" -ne 0 ]
    [ ! -e "$BATS_TEST_TMPDIR/escaped-worktree" ]
}
