#!/usr/bin/env bash
# Main session picker with tree view and preview
# Hybrid UI: Uses tree-view.sh for rendering, provides fzf overlay interface

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOWER_DIR="$(dirname "$SCRIPT_DIR")"
TOWER_SCRIPT_NAME="tower.sh"

# Source common library
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

debug_log "Starting tower.sh"

# Build tree structure using shared tree-view module
build_tree() {
    "$SCRIPT_DIR/tree-view.sh" full
}

# Parse selection and switch
handle_selection() {
    local selection="$1"
    local type selected_session selected_window selected_pane

    IFS=':' read -r type selected_session selected_window selected_pane _ <<< "$selection"

    case "$type" in
        session)
            tmux switch-client -t "$selected_session" || handle_error "Failed to switch to session"
            ;;
        window)
            tmux switch-client -t "${selected_session}:${selected_window}" || handle_error "Failed to switch to window"
            ;;
        pane)
            tmux switch-client -t "${selected_session}:${selected_window}.${selected_pane}" || handle_error "Failed to switch to pane"
            ;;
    esac
}

# Main
main() {
    # Check if fzf is available
    require_command fzf || exit 1

    # Build tree and show fzf picker
    local selection
    selection=$(build_tree | fzf-tmux -p 80%,70% \
        --ansi \
        --no-sort \
        --reverse \
        --header="Enter:select | n:new | r:rename | x:kill | D:diff | ?:help" \
        --preview="$SCRIPT_DIR/preview.sh {}" \
        --preview-window=right:50% \
        --bind="n:execute($SCRIPT_DIR/new-session.sh)+reload($SCRIPT_DIR/tower.sh --list)" \
        --bind="r:execute($SCRIPT_DIR/rename.sh {})+reload($SCRIPT_DIR/tower.sh --list)" \
        --bind="x:execute($SCRIPT_DIR/kill.sh {})+reload($SCRIPT_DIR/tower.sh --list)" \
        --bind="D:preview($SCRIPT_DIR/diff.sh {})" \
        --bind="?:preview($SCRIPT_DIR/help.sh)" \
        --delimiter=':' \
    ) || exit 0

    [[ -n "$selection" ]] && handle_selection "$selection"
}

# If called with --list, just output the tree (for reload)
if [[ "${1:-}" == "--list" ]]; then
    build_tree
else
    main
fi
