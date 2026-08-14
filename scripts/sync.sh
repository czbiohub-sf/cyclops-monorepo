#!/usr/bin/env bash
#
# sync.sh — Sync the entire cyclops-monorepo (parent + all submodules).
#
# Usage:
#   bash scripts/sync.sh pull   Pull latest for all submodules + parent
#   bash scripts/sync.sh push   Push all submodules + parent
#   bash scripts/sync.sh        Full sync (pull then push)
#
# What it does:
#   pull:
#     1. Pulls the parent repo first (with --rebase) so that
#        .gitmodules branch config is up to date before touching
#        submodules.
#     2. For each submodule, ensures it is on a named branch:
#        - If the submodule has a `branch` set in .gitmodules, checks
#          out that branch. Every submodule sets one: all track `main`
#          except stitching, which tracks beta/nextflow_zarrv3_changes.
#        - If no branch is configured, falls back to "main" —
#          note this is NOT conditional on being in detached HEAD, so a
#          submodule sitting on a feature branch with no `branch` entry
#          WILL be checked out to main and rebased onto origin/main.
#          Set `branch` for any submodule whose feature branch should
#          survive a sync.
#     3. Fetches and pulls each submodule with --rebase for a clean
#        linear history.
#     4. Automatically stashes/unstashes dirty working trees so that
#        uncommitted changes don't block the pull.
#
#   push:
#     1. Pushes each submodule that is on a named branch.
#     2. Stages any updated submodule refs in the parent and commits
#        them (skipped if nothing changed).
#     3. Pushes the parent repo.
#
# What it does NOT do:
#   - Does NOT force-push. If the remote has diverged, the push will
#     fail and you need to pull first.
#   - Does NOT resolve merge/rebase conflicts. If a rebase conflicts,
#     it will pause and you must resolve manually (then `git rebase
#     --continue`).
#   - Does NOT run `uv sync` or rebuild Python packages.
#
# Edge cases to be aware of:
#   - Run with `bash scripts/sync.sh`, NOT `uv run scripts/sync.sh`.
#     uv rebuilds packages before the script runs, dirtying the working
#     tree and potentially causing pull failures.
#   - The stash/pop is per-submodule. If a stash pop fails (e.g. due to
#     a conflict with the newly pulled code), your changes will remain
#     in the stash — run `git stash list` and `git stash pop` manually.
#   - `push` uses `git add -A` in the parent repo, which stages ALL
#     changes (not just submodule refs). Review with `git status` if
#     you have other uncommitted work in the parent.
#
# Configuring a submodule's branch:
#   The branch a submodule tracks is read from .gitmodules. To change it:
#     git config -f .gitmodules submodule.<name>.branch <branch>
#   Submodules without a configured branch default to "main".
#

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Tag our stashes so we never pop stashes that weren't created by this script
# (e.g. user's manual stashes, or stale stashes from a previous crashed run).
SYNC_STASH_TAG="sync.sh auto-stash"

# Get the branch a submodule should be on.
# Reads from .gitmodules first, falls back to "main".
get_submodule_branch() {
    local name="$1"
    local branch
    branch=$(git config -f .gitmodules "submodule.${name}.branch" 2>/dev/null || true)
    echo "${branch:-main}"
}

# Resolve any currently-unmerged paths (from a prior interrupted stash pop) by
# keeping the current branch's version ("ours" in a stash-pop context = the
# already-pulled upstream state) and staging the file. This breaks the loop
# where a bad stash keeps re-conflicting on every sync run.
_resolve_unmerged_ours() {
    local unmerged
    unmerged=$(git diff --name-only --diff-filter=U 2>/dev/null || true)
    if [ -n "$unmerged" ]; then
        echo "  Auto-resolving unmerged paths (keep ours):"
        echo "$unmerged" | while read -r f; do
            [ -z "$f" ] && continue
            echo "    $f"
            git checkout --ours -- "$f" >/dev/null 2>&1 || true
            git add -- "$f" >/dev/null 2>&1 || true
        done
    fi
}

# Drop any stashes whose subject contains our SYNC_STASH_TAG. Those are from
# previous sync.sh runs that failed mid-pop. Iterate high-to-low so indices
# stay valid after drops.
_drop_stale_sync_stashes() {
    local lines
    lines=$(git stash list 2>/dev/null | grep -nF "$SYNC_STASH_TAG" || true)
    if [ -n "$lines" ]; then
        echo "  Dropping stale sync stashes:"
        echo "$lines" | awk -F: '{print $1}' | sort -rn | while read -r lineno; do
            local idx=$((lineno - 1))
            echo "    stash@{${idx}}"
            git stash drop -q "stash@{${idx}}" || true
        done
    fi
}

# Push a tagged stash only if the tree has something to stash. Exports
# DID_STASH=1 if a stash was actually created, 0 otherwise.
_safe_stash_push() {
    DID_STASH=0
    if git diff --quiet && git diff --cached --quiet \
       && [ -z "$(git ls-files --others --exclude-standard)" ]; then
        return 0
    fi
    if git stash push -u -q -m "$SYNC_STASH_TAG $(date -u +%FT%TZ)" 2>/dev/null; then
        DID_STASH=1
    fi
}

# Pop the tagged stash we just pushed. If pop conflicts, auto-resolve by
# keeping ours and drop the poisoned stash (otherwise the next sync run will
# re-pop it and re-conflict in a loop — the bug this function prevents).
_safe_stash_pop() {
    [ "${DID_STASH:-0}" -eq 1 ] || return 0
    # Only pop if our tagged stash is still the top entry.
    local top
    top=$(git stash list 2>/dev/null | head -n1 || true)
    if ! echo "$top" | grep -qF "$SYNC_STASH_TAG"; then
        return 0
    fi
    if git stash pop -q 2>/dev/null; then
        return 0
    fi
    echo "  Stash pop conflicted — auto-resolving (keep ours) and dropping stash"
    _resolve_unmerged_ours
    # Conflicting pop leaves the stash at stash@{0}; drop it.
    git stash drop -q "stash@{0}" 2>/dev/null || true
}

# Subshells inside `git submodule foreach` need these to be visible
export SYNC_STASH_TAG
export -f _resolve_unmerged_ours _drop_stale_sync_stashes _safe_stash_push _safe_stash_pop

pull_all() {
    echo "=== Pulling parent repo (to get latest .gitmodules) ==="
    _resolve_unmerged_ours
    _drop_stale_sync_stashes
    _safe_stash_push
    git pull --rebase origin "$(git rev-parse --abbrev-ref HEAD)"
    _safe_stash_pop

    echo "=== Pulling submodules ==="
    git submodule init -q

    git submodule foreach -q 'echo $name' | while read -r sub; do
        BRANCH=$(get_submodule_branch "$sub")
        echo "--- $sub ($BRANCH) ---"
        (
            cd "$sub"
            _resolve_unmerged_ours
            _drop_stale_sync_stashes
            git fetch --all -q
            CURRENT=$(git rev-parse --abbrev-ref HEAD)
            if [ "$CURRENT" != "$BRANCH" ]; then
                _safe_stash_push
                git checkout "$BRANCH" 2>/dev/null || git checkout -b "$BRANCH" "origin/$BRANCH"
            fi
            _safe_stash_push
            git pull --rebase origin "$BRANCH" || true
            _safe_stash_pop
        )
    done
}

push_all() {
    echo "=== Pushing submodules ==="
    git submodule foreach -q 'echo $name' | while read -r sub; do
        BRANCH=$(get_submodule_branch "$sub")
        echo "--- $sub ($BRANCH) ---"
        (
            cd "$sub"
            git push origin "$BRANCH" || true
        )
    done

    echo "=== Updating submodule refs in parent ==="
    git add -A
    if ! git diff --cached --quiet; then
        git commit -m "update submodule refs"
    else
        echo "(no submodule ref changes to commit)"
    fi

    echo "=== Pushing parent repo ==="
    git push origin "$(git rev-parse --abbrev-ref HEAD)"
}

case "${1:-sync}" in
    pull)  pull_all ;;
    push)  push_all ;;
    sync)  pull_all; push_all ;;
    *)     echo "Usage: $0 [pull|push|sync]"; exit 1 ;;
esac

echo "=== Done ==="
