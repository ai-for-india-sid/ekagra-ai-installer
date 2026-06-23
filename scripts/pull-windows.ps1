<#
.SYNOPSIS
    pull-windows.ps1 — Daily update script for Ekagra AI (Windows)

.DESCRIPTION
    Called automatically by Windows Task Scheduler every day at 11:30am.
    Pulls the latest changes from the private Ekagra AI repository into
    %USERPROFILE%\ekagra-ai and appends a timestamped record to
    %USERPROFILE%\ekagra-ai\logs\pull.log.

    Self-contained: no user interaction, no network calls beyond the git pull.
    Safe to run repeatedly and silently.
#>

# --- Configuration ----------------------------------------------------------
# The local clone of the Ekagra AI repository (created by install-windows.ps1).
$repoDir = "$env:USERPROFILE\ekagra-ai"
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

# Move into the repo so `git pull` operates on the right place.
Set-Location $repoDir

# --- Perform the pull -------------------------------------------------------
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Add-Content $logFile "─────────────────────"
Add-Content $logFile "[$timestamp] Starting pull"

# Run the pull, capturing all output (stdout + stderr) into the log.
$output = git pull 2>&1
Add-Content $logFile $output

# Record the outcome with a friendly, non-technical summary line.
if ($LASTEXITCODE -eq 0) {
    Add-Content $logFile "[$timestamp] Pull successful"
} else {
    Add-Content $logFile "[$timestamp] Pull failed with exit code $LASTEXITCODE"
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
