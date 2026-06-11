#!/usr/bin/env bash
# tile-sweep.sh - one-shot startup cleanup of orphaned Tile artifacts.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/error-recovery.sh"
source "$SCRIPT_DIR/../lib/tile.sh"
tile_sweep_orphans
