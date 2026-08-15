<#
.SYNOPSIS
    pull-windows.ps1 — Daily update script for Ekagra AI (Windows)

.DESCRIPTION
    Called automatically by Windows Task Scheduler every day at 11:30am.
    Fetches the private Ekagra AI repository and resets %USERPROFILE%\Ek-ai
    onto it, appending a timestamped record to %USERPROFILE%\Ek-ai\logs\pull.log.

    Self-contained: no user interaction, no network calls beyond the fetch.
    Safe to run repeatedly and silently.

    Unlike the macOS launcher, this does NOT delegate to the repo's tracked
    scripts/update.sh, which is bash and cannot be assumed present on Windows.
    The consequence is that a future fix to update logic reaches Windows only
    through a re-install. Acceptable while Windows is not a supported platform;
    revisit by calling update.sh through Git Bash if that changes.
#>

# --- Configuration ----------------------------------------------------------
# The local clone of the Ekagra AI repository (created by install-windows.ps1).
$repoDir = "$env:USERPROFILE\Ek-ai"
# Where we keep a human-readable record of every pull attempt.
$logFile = "$repoDir\logs\pull.log"
# Cap the log file at this many lines so it never grows without bound.
$maxLines = 500

# --- Sanity checks ----------------------------------------------------------
# If the repo directory is missing there is nothing we can do; log and exit.
if (-not (Test-Path $repoDir)) {
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content $logFile "[$stamp] Ekagra AI directory not found ($repoDir). Skipping pull."
    exit 1
}

# Ensure the logs directory exists. The installer creates it, but if a user
# (or cleanup tool) deletes it, our writes below would silently fail with no
# record to diagnose from. Self-heal rather than trust prior state.
$logDir = Split-Path $logFile -Parent
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

# Move into the repo so `git pull` operates on the right place.
Set-Location $repoDir

# --- Perform the pull -------------------------------------------------------
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Add-Content $logFile "─────────────────────"
Add-Content $logFile "[$timestamp] Starting pull"

# Run the pull, capturing all output (stdout + stderr) into the log.
# accept-new auto-trusts github.com's host key so an unattended scheduled pull
# can never hang on an interactive prompt; a *changed* known key still blocks.
$env:GIT_SSH_COMMAND = "ssh -o StrictHostKeyChecking=accept-new"

# Fetch, then move onto upstream with a hard reset. Not a merge, so it cannot
# conflict and cannot leave the repo in a state that blocks the next run. A
# merge needs somewhere to put a disagreement, and a fork with any local edit
# to a tracked file gives it one: that is how one machine ended up mid-merge,
# with every later run dying on "you have unmerged files".
#
# Local edits to tracked files are DISCARDED. Customization belongs in the
# gitignored override files (SETUP.md > Customizing your fork), which a reset
# never touches. Drift is saved to logs\drift-<timestamp>.patch first.
# Untracked files are left alone: no git clean.
$fetchOutput = git fetch origin 2>&1
Add-Content $logFile $fetchOutput
if ($LASTEXITCODE -ne 0) {
    Add-Content $logFile "[$timestamp] Pull failed: could not reach the remote"
    exit 1
}

$upstream = git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null
if ($LASTEXITCODE -ne 0 -or -not $upstream) { $upstream = "origin/main" }

$dirty = git status --porcelain --untracked-files=no 2>$null
$ahead = git log --oneline "$upstream..HEAD" 2>$null
if ($dirty -or $ahead) {
    $patch = "$repoDir\logs\drift-$(Get-Date -Format 'yyyyMMdd-HHmmss').patch"
    (git diff "$upstream...HEAD" 2>$null) + (git diff HEAD 2>$null) | Set-Content $patch
    Add-Content $logFile "[$timestamp] Local changes to tracked files discarded, saved to $(Split-Path $patch -Leaf)"
}

$resetOutput = git reset --hard $upstream 2>&1
Add-Content $logFile $resetOutput
if ($LASTEXITCODE -eq 0) {
    Add-Content $logFile "[$timestamp] Pull successful"
} else {
    Add-Content $logFile "[$timestamp] Pull failed: could not reset to $upstream"
}

# --- Log rotation -----------------------------------------------------------
# Keep only the most recent $maxLines lines to prevent unbounded growth.
# Only rotate if the file is large enough to matter (avoids touching a small log
# on every run, which would needlessly rewrite it).
if (Test-Path $logFile) {
    $lines = Get-Content $logFile
    if ($lines.Count -gt $maxLines) {
        $lines | Select-Object -Last $maxLines | Set-Content $logFile
    }
}

exit 0
