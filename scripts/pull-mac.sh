#!/bin/bash
#
# pull-mac.sh - daily update launcher for Ekagra AI (macOS)
#
# Called by launchd (ai.ekagra.daily-pull) once a day and at login.
#
# Thin on purpose. The real update logic lives in the framework repo at
# scripts/update.sh, which is TRACKED, so a fix to it reaches every machine
# through the update itself. This file is installer-written and gitignored in
# the repo, which means changing it costs a re-install on every machine. That
# is a bill we pay once, here, and then stop paying.

REPO_DIR="$HOME/Ek-ai"
LOG_FILE="$REPO_DIR/logs/pull.log"
UPDATER="$REPO_DIR/scripts/update.sh"
MAX_LOG_LINES=500

if [ ! -d "$REPO_DIR" ]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Ekagra AI directory not found ($REPO_DIR). Skipping pull." >> "$LOG_FILE" 2>/dev/null
  exit 1
fi

mkdir -p "$(dirname "$LOG_FILE")"
cd "$REPO_DIR" || exit 1

# Normal path: hand off to the tracked updater.
if [ -f "$UPDATER" ]; then
  exec bash "$UPDATER" "$@"
fi

# ── Bootstrap path ──────────────────────────────────────────────────────────
# This clone predates scripts/update.sh. Fetch and reset inline, which does two
# things at once: it unwedges a repo the old `git pull` updater left mid-merge
# (a conflict there blocked every later run until somebody noticed), and it
# brings scripts/update.sh in, so the tracked script takes over from the next
# run. Deliberately minimal - it should be needed exactly once per machine.
echo "─────────────────────" >> "$LOG_FILE"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting pull (bootstrap: no scripts/update.sh yet)" >> "$LOG_FILE"

BEFORE_SHA="$(git rev-parse HEAD 2>/dev/null || echo unknown)"

if ! GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new" git fetch origin >> "$LOG_FILE" 2>&1; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Pull failed: could not reach the remote" >> "$LOG_FILE"
  exit 1
fi

UPSTREAM="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || echo origin/main)"

# Save anything local before discarding it. The point of the reset is that it
# always succeeds; the operator's work should still be recoverable afterwards.
if [ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)$(git log --oneline "$UPSTREAM..HEAD" 2>/dev/null)" ]; then
  PATCH="$REPO_DIR/logs/drift-$(date '+%Y%m%d-%H%M%S').patch"
  { git diff "$UPSTREAM...HEAD" 2>/dev/null; git diff HEAD 2>/dev/null; } > "$PATCH" 2>/dev/null
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Local changes to tracked files discarded, saved to $(basename "$PATCH")" >> "$LOG_FILE"
fi

if git reset --hard "$UPSTREAM" >> "$LOG_FILE" 2>&1; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Pull successful ($BEFORE_SHA -> $(git rev-parse HEAD))" >> "$LOG_FILE"
else
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Pull failed: could not reset to $UPSTREAM" >> "$LOG_FILE"
fi

tail -n "$MAX_LOG_LINES" "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
exit 0
