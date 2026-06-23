#!/bin/bash
#
# pull-mac.sh — Daily update script for Ekagra AI (macOS)
#
# Called automatically by launchd every day at 11:30am.
# Pulls the latest changes from the private Ekagra AI repository into ~/Ek-ai
# and appends a timestamped record to ~/Ek-ai/logs/pull.log.
#
# This script is intentionally self-contained: no user interaction, no network calls
# beyond the git pull itself. It is safe to run repeatedly and silently.

# --- Configuration ----------------------------------------------------------
# The local clone of the Ekagra AI repository (created by install-mac.sh).
REPO_DIR="$HOME/Ek-ai"
# Where we keep a human-readable record of every pull attempt.
LOG_FILE="$REPO_DIR/logs/pull.log"
# Cap the log file at this many lines so it never grows without bound.
MAX_LOG_LINES=500

# --- Sanity checks ----------------------------------------------------------
# If the repo directory is missing there is nothing we can do; log and exit.
if [ ! -d "$REPO_DIR" ]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Ekagra AI directory not found ($REPO_DIR). Skipping pull." >> "$LOG_FILE" 2>/dev/null
  exit 1
fi

# Ensure the logs directory exists. The installer creates it, but if a user
# (or cleanup tool) deletes it, our appends below would silently fail with no
# record to diagnose from. Self-heal rather than trust prior state.
mkdir -p "$(dirname "$LOG_FILE")"

# Move into the repo so `git pull` operates on the right place.
cd "$REPO_DIR" || exit 1

# --- Perform the pull -------------------------------------------------------
echo "─────────────────────" >> "$LOG_FILE"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting pull" >> "$LOG_FILE"

# Run the pull, capturing all output (stdout + stderr) into the log.
git pull >> "$LOG_FILE" 2>&1
EXIT_CODE=$?

# Record the outcome with a friendly, non-technical summary line.
if [ $EXIT_CODE -eq 0 ]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Pull successful" >> "$LOG_FILE"
else
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Pull failed with exit code $EXIT_CODE" >> "$LOG_FILE"
fi

# --- Log rotation -----------------------------------------------------------
# Keep only the most recent MAX_LOG_LINES lines to prevent unbounded growth.
# Write to a temp file first, then atomically replace — avoids truncating
# the log if the machine loses power mid-write.
tail -n "$MAX_LOG_LINES" "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"

exit 0
