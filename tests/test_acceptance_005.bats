#!/usr/bin/env bats
# Acceptance for 005-nav-badges: background shells count as work, and the
# rows show agents (✦N) and shells (⚙N) right after the state icon.
# Test names equal the scenario names in
# value/005-nav-badges/acceptance/005-nav-badges.feature.

load 'test_helper'

UUID_A="11111111-1111-4111-8111-111111111111"

setup() {
    source_common
    setup_test_env
}

teardown() {
    teardown_test_env
}

_pane() { cat "${BATS_TEST_DIRNAME}/fixtures/panes/$1.txt"; }

# navigator-list.sh sources common.sh (readonly), so each case runs in a
# fresh bash. Session N's pane shows "<agents>:<shells>" from PANES_SPEC,
# e.g. "tower_x=2:1 tower_y=0:1".
_run_nav() {
    run bash -c '
        export CLAUDE_TOWER_METADATA_DIR="'"$CLAUDE_TOWER_METADATA_DIR"'"
        export CLAUDE_PROJECTS_DIR="'"$CLAUDE_PROJECTS_DIR"'"
        export CLAUDE_TOWER_NAV_SOCKET="acc005-nav-$$"
        export CLAUDE_TOWER_SESSION_SOCKET="acc005-sess-$$"
        source "'"$PROJECT_ROOT"'/tmux-plugin/scripts/navigator-list.sh"
        set +e
        tput() { case "$1" in cols) echo 80 ;; lines) echo 24 ;; ed) printf "" ;; *) command tput "$@" 2>/dev/null ;; esac; }
        _session_label() { echo "t-${1#tower_}"; }
        _session_dir() { echo "/proj/demo"; }
        mark_session_seen() { :; }
        init_session_seen() { :; }
        is_session_unread() { return 1; }
        count_unregistered_processes_in_dir() { echo 0; }
        live_claude_id() { echo "${1#tower_}"; }
        find_session_jsonl() { echo "/dev/null"; }
        _spec() { local kv; for kv in $PANES_SPEC; do [[ "${kv%%=*}" == "$1" ]] && echo "${kv#*=}"; done; }
        count_active_subagents() { local s; s=$(_spec "$2"); echo "${s%%:*}"; }
        session_tmux() {
            [[ "$1" == capture-pane ]] || return 0
            local s n
            s=$(_spec "${3%%:*}"); n="${s##*:}"
            printf "%s\n" "────" "❯ " "────"
            if [[ "${n:-0}" -gt 1 ]]; then echo "  ⏵⏵ auto mode on · $n shells"
            elif [[ "${n:-0}" -eq 1 ]]; then echo "  ⏵⏵ auto mode on · 1 shell"
            else echo "  ⏵⏵ auto mode on"; fi
        }
        # Rows as drawn: spinner frame in, colour out.
        rows() {
            local r
            for r in "${SESSION_DISPLAYS[@]}"; do
                r="${r//$SPIN_PLACEHOLDER/⠋}"
                printf "%s\n" "$(_strip_ansi_str "$r")"
            done
        }
        # Cell where the title starts ("t-" marks it). Every glyph before it
        # (state icons, ✦, ⚙) is one cell in tmux, so cells = characters.
        title_col() { local r="$1"; printf "%s" "${r%%t-*}" | LC_ALL=C.UTF-8 wc -m; }
        '"$1"'
    '
}

@test "プロンプト待ちでもバックグラウンドでシェルが動いていれば、作業中になり ⚙ が付く" {
    local f
    f=$(create_mock_jsonl "-home-user-proj" "$UUID_A" "/home/user/proj")
    touch -d "2020-01-01 00:00:00" "$f"
    run is_session_busy "$f" "tower_${UUID_A}" "$(_pane background-shell-only | sed 's/· 1 shell/· 2 shells/')"
    [ "$status" -eq 0 ]

    PANES_SPEC="tower_x=0:2" _run_nav '
        list_all_sessions() { echo "tower_x:busy"; }
        build_session_list
        rows | grep "t-x"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "⠋ ⚙2 t-x" ]
}

@test "Claude が終了して残った画面のシェルは数えない" {
    local f
    f=$(create_mock_jsonl "-home-user-proj" "$UUID_A" "/home/user/proj")
    touch -d "2020-01-01 00:00:00" "$f"
    run is_session_busy "$f" "tower_${UUID_A}" "$(_pane background-shell-only; echo 'user@host ~/proj $ ')"
    [ "$status" -eq 1 ]
}

@test "バッジのない一覧はバッジ欄を設けない" {
    PANES_SPEC="" _run_nav '
        list_all_sessions() { printf "%s\n" "tower_a:active" "tower_b:dormant" "tower_c:busy"; }
        build_session_list
        rows | grep "t-"
    '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "  t-a" ]
    [ "${lines[1]}" = "○ t-b" ]
    [ "${lines[2]}" = "⠋ t-c" ]
}

@test "エージェントとシェルのバッジが並び、タイトルの桁がそろう" {
    PANES_SPEC="tower_x=2:1 tower_y=0:1" _run_nav '
        list_all_sessions() { printf "%s\n" "tower_x:busy" "tower_y:busy" "tower_z:active"; }
        build_session_list
        while IFS= read -r r; do
            [[ "$r" == *t-* ]] && printf "%s|%s\n" "$(title_col "$r")" "$r"
        done < <(rows)
    '
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == *"|⠋ ✦2 ⚙1 t-x" ]]
    [[ "${lines[1]}" == *"|⠋ ⚙1"*"t-y" ]]
    [[ "${lines[2]}" == *"t-z" ]]
    [ "${lines[0]%%|*}" = "${lines[1]%%|*}" ]
    [ "${lines[1]%%|*}" = "${lines[2]%%|*}" ]
}

@test "行の右端に記号用の幅を予約しない" {
    PANES_SPEC="" _run_nav '
        long=$(printf "x%.0s" {1..200})
        r=$(_compose_row "○" "$long" "")
        printf "  %s" "$(_strip_ansi_str "$r")" | LC_ALL=C.UTF-8 wc -m
        _content_width
    '
    [ "$status" -eq 0 ]
    # Cells as tmux draws them. The cut title ends at the right edge, short
    # by at most 2: the icon and the "…" are each measured as two cells and
    # drawn in one. The old reserve for the right column left 6.
    [ "${lines[0]}" -le "${lines[1]}" ]
    [ "${lines[0]}" -ge $((lines[1] - 2)) ]
}

@test "ヘルプが ✦ と ⚙ の意味を示し、80×24 に収まる" {
    PANES_SPEC="" _run_nav '
        clear() { :; }
        read() { :; }
        show_help 2>/dev/null
    '
    local text line w n=0
    text=$(printf "%s\n" "$output" | sed -E $'s/\033\\[[0-9;?]*[a-zA-Z]//g')
    [[ "$text" == *"✦N agents"* ]]
    [[ "$text" == *"⚙N shells"* ]]
    while IFS= read -r line; do
        n=$((n + 1))
        # Characters, not bytes: under the C locale (Docker) ${#line} counts
        # each ✦ as three. Every glyph in the help is one cell in tmux.
        w=$(printf "%s" "$line" | LC_ALL=C.UTF-8 wc -m)
        [ "$w" -le 80 ] || { echo "too wide ($w): $line"; return 1; }
    done <<<"$text"
    [ "$n" -le 24 ]
}

@test "起動中と削除中の行も、ほかの行と同じ桁からタイトルが始まる" {
    PANES_SPEC="tower_x=2:1" _run_nav '
        list_all_sessions() { printf "%s\n" "tower_x:busy" "tower_y:active"; }
        build_session_list
        _mark_session_deleting tower_y
        _remember_session_row tower_n /proj/demo
        while IFS= read -r r; do
            [[ "$r" == *t-* ]] && printf "%s|%s\n" "$(title_col "$r")" "$r"
        done < <(rows)
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"deleting"* ]]
    [ "$(printf "%s\n" "${lines[@]}" | cut -d"|" -f1 | sort -u | wc -l)" -eq 1 ]
}
