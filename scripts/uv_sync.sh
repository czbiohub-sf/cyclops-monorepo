#!/usr/bin/env bash
# uv_sync.sh — NFS-safe wrapper around uv sync
#
# On NFS, `uv sync --reinstall` can fail because stale file handles
# prevent removal of __pycache__ directories inside .venv.
#
# This script works around the issue by renaming the old .venv out of
# the way (atomic on same filesystem), running a fresh uv sync, then
# cleaning up the old venv in the background.
#
# Usage:
#   bash scripts/uv_sync.sh              # base install
#   bash scripts/uv_sync.sh --all-extras # full install with RAPIDS, tracking, viz
#   bash scripts/uv_sync.sh --extra rapids --extra tracking
#
# All arguments are forwarded to `uv sync`.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VENV_DIR="$PROJECT_DIR/.venv"

cd "$PROJECT_DIR"

# If .venv exists, move it aside to avoid NFS stale handle errors
if [ -d "$VENV_DIR" ]; then
    OLD_VENV="$VENV_DIR.old.$$"
    echo "Moving existing .venv aside to avoid NFS lock issues..."
    mv "$VENV_DIR" "$OLD_VENV"
fi

# Create .venv using system Python so other users can access it
# (uv-managed Python lives under ~/.local which is inaccessible to others)
echo "Creating venv with system Python 3.12..."
uv venv --python /usr/bin/python3.12

# Run fresh uv sync (installs deps into the new .venv)
echo "Running: uv sync $*"
uv sync "$@"

# Clean up old venv in background (may take a moment on NFS)
if [ -n "${OLD_VENV:-}" ] && [ -d "${OLD_VENV:-}" ]; then
    echo "Cleaning up old venv in background..."
    rm -rf "$OLD_VENV" &
fi

echo "Done."
