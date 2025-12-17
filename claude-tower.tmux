#!/usr/bin/env bash
# TPM entry point - delegates to actual plugin script
# https://github.com/tapoh22334/claude-tower

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Run the actual plugin script
source "$CURRENT_DIR/tmux-plugin/claude-tower.tmux"
