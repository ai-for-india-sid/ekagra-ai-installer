#!/bin/bash
#
# pull-mac.sh — Daily update script for Ekagra AI (macOS)
#
# Called automatically by launchd every day at 11:30am.
# Pulls the latest changes from the private Ekagra AI repository into ~/Ek-ai
# and appends a timestamped record to ~/Ek-ai/logs/pull.log.
#
# This script runs with no user interaction. Beyond the git pull it makes one
# fire-and-forget telemetry POST (a fleet-update heartbeat — see "Fleet-update
# telemetry" below). It is safe to run repeatedly and silently.

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

# Record the current commit first, so we can tell a real update from a no-op pull.
BEFORE_SHA="$(git rev-parse HEAD 2>/dev/null || echo unknown)"

# Run the pull, capturing all output (stdout + stderr) into the log.
# accept-new auto-trusts github.com's host key so an unattended scheduled pull
# can never hang on an interactive prompt; a *changed* known key still blocks.
GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new" git pull >> "$LOG_FILE" 2>&1
EXIT_CODE=$?

# Record the outcome with a friendly, non-technical summary line.
if [ $EXIT_CODE -eq 0 ]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Pull successful" >> "$LOG_FILE"
else
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Pull failed with exit code $EXIT_CODE" >> "$LOG_FILE"
fi

# --- Fleet-update telemetry -------------------------------------------------
# Emit a PostHog event so this daily pull is visible remotely. It's the only
# telemetry that runs OUTSIDE a Claude session, so it's the one way to know a
# fork is still auto-updating (framework_pulled, updated=true when new commits
# landed) or stuck (framework_pull_failed). Reuses the repo's own telemetry hook
# — one PostHog transport, one write-only key. Fire-and-forget: it never touches
# the pull's success. The hook needs jq + curl, which launchd's minimal PATH
# omits, so we prepend the usual Homebrew locations for this call only.
TRACK="$REPO_DIR/hooks/track-event.sh"
if [ -x "$TRACK" ]; then
  AFTER_SHA="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
  if [ $EXIT_CODE -eq 0 ]; then
    UPDATED=false; [ "$BEFORE_SHA" != "$AFTER_SHA" ] && UPDATED=true
    printf '{"updated":%s,"from_sha":"%s","to_sha":"%s"}' "$UPDATED" "$BEFORE_SHA" "$AFTER_SHA" \
      | PATH="/opt/homebrew/bin:/usr/local/bin:$PATH" "$TRACK" custom framework_pulled >/dev/null 2>&1 || true
  else
    printf '{"exit_code":%s,"from_sha":"%s"}' "$EXIT_CODE" "$BEFORE_SHA" \
      | PATH="/opt/homebrew/bin:/usr/local/bin:$PATH" "$TRACK" custom framework_pull_failed >/dev/null 2>&1 || true
  fi
fi

# --- Log rotation -----------------------------------------------------------
# Keep only the most recent MAX_LOG_LINES lines to prevent unbounded growth.
# Write to a temp file first, then atomically replace — avoids truncating
# the log if the machine loses power mid-write.
tail -n "$MAX_LOG_LINES" "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"

exit 0
