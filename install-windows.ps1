<#
.SYNOPSIS
    install-windows.ps1 — One-time setup for Ekagra AI (Windows)

.DESCRIPTION
    What it does (for a non-technical user, one command):
      1. Confirms Git for Windows is installed
      2. Generates a dedicated SSH key just for Ekagra (no GitHub account needed)
      3. Wires up an SSH config alias so git uses that key automatically
      4. Hands the public key to the user to send to their Ekagra contact, who
         registers it as a read-only deploy key on the private repo
      5. Clones the repo into %USERPROFILE%\Ek-ai
      6. Installs a daily pull script
      7. Schedules an automatic update every day at 11:30am via Task Scheduler

    Idempotent: re-running will not create a second SSH key, duplicate SSH
    config block, duplicate scheduled task, or a second clone.
#>

# Make the whole script stop on the first unexpected error, and treat any
# failure inside a native command (like git) as an error too.
$ErrorActionPreference = "Stop"

# ─── Configuration ──────────────────────────────────────────────────────────
# Custom SSH host alias (see ~/.ssh/config). Lets us pin a specific key to a
# specific repo without touching any other SSH setup the user may have.
$sshHostAlias = "ekagra-github"
$sshDir       = "$env:USERPROFILE\.ssh"
$keyPath      = "$sshDir\ekagra_deploy"
$configFile   = "$sshDir\config"
# The repo to clone, referenced via the SSH alias so the right key is used.
$repoUrl      = "git@${sshHostAlias}:ai-for-india-sid/d2c-ai-buddy.git"
# Where the repo lands on the user's machine.
$installDir   = "$env:USERPROFILE\Ek-ai"
# Name of the scheduled task that runs the daily pull.
$taskName     = "ekagra-ai Daily Pull"

# ─── Helpers ────────────────────────────────────────────────────────────────
function Ok   { param($msg) Write-Host "✓ $msg" }
function Fail { param($msg) Write-Host "✗ $msg"; exit 1 }

Write-Host "Welcome to Ekagra AI Setup"
Write-Host "This will take about a minute. Please don't close this window."
Write-Host ""

# ─── 1. Check git ───────────────────────────────────────────────────────────
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Git is not installed."
    Write-Host "Please download and install it from: https://git-scm.com/download/win"
    Write-Host "Then run this setup again."
    exit 1
}
Ok "Git found"

# ─── 2. Generate the dedicated SSH key (if missing) ─────────────────────────
if (-not (Test-Path $sshDir)) {
    New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
}

if (Test-Path $keyPath) {
    Ok "SSH key already exists, skipping"
} else {
    # -N '""' = empty passphrase (the scheduler needs to run unattended).
    # -f       = output path.
    # -C       = comment label, helps identify the key later.
    & ssh-keygen -t ed25519 -f $keyPath -N '""' -C "ekagra-ai-deploy" 2>$null | Out-Null
    if (-not (Test-Path $keyPath)) {
        Fail "Could not generate the security key. Please contact your Ekagra AI contact."
    }
    Ok "Security key generated"
}

# ─── 3. Add the SSH config entry (if missing) ───────────────────────────────
# IdentitiesOnly yes ensures git uses ONLY this key for github.com, so we never
# accidentally offer some other identity.
$existingConfig = ""
if (Test-Path $configFile) {
    $existingConfig = Get-Content $configFile -Raw
}

if ($existingConfig -match "(?m)^Host\s+$sshHostAlias\b") {
    Ok "SSH config already set up, skipping"
} else {
    $configBlock = @"

Host $sshHostAlias
  HostName github.com
  User git
  IdentityFile $keyPath
  IdentitiesOnly yes
"@
    Add-Content -Path $configFile -Value $configBlock
    Ok "SSH config updated"
}

# ─── 4. Copy public key + prompt user to send it to their contact ───────────
# Set-Clipboard puts the public key on the clipboard so the user can just paste it.
$pubKey = Get-Content "$keyPath.pub" -Raw
$pubKey | Set-Clipboard

Write-Host ""
Write-Host "─────────────────────────────────────────────"
Write-Host "ACTION REQUIRED — takes 2 minutes"
Write-Host ""
Write-Host "Your setup key has been copied to your clipboard."
Write-Host ""
Write-Host "Please WhatsApp or email it to your Ekagra AI contact now."
Write-Host "They will activate your account and reply when you're ready to continue."
Write-Host ""
Write-Host "Once they confirm, press Enter to finish setup."
Write-Host "─────────────────────────────────────────────"
Read-Host "Press Enter when your contact confirms your account is activated" | Out-Null

# ─── 5. Clone the repository ────────────────────────────────────────────────
# If already cloned, skip rather than error (idempotency for re-runs).
if (Test-Path "$installDir\.git") {
    Ok "Ekagra AI already downloaded, skipping"
} else {
    Write-Host "Downloading Ekagra AI..."
    $ErrorActionPreference = "Continue"   # let git fail without throwing
    & git clone $repoUrl $installDir 2>$null | Out-Null
    $cloneExit = $LASTEXITCODE
    $ErrorActionPreference = "Stop"
    if ($cloneExit -ne 0) {
        Write-Host ""
        Write-Host "✗ Could not connect to the repository."
        Write-Host "  Please confirm with your Ekagra AI contact that your key has been activated,"
        Write-Host "  then run this setup again."
        exit 1
    }
    Ok "Ekagra AI downloaded"
}

# ─── 6. Install the daily pull script ───────────────────────────────────────
$scriptsDir = "$installDir\scripts"
$logsDir    = "$installDir\logs"
New-Item -ItemType Directory -Path $scriptsDir -Force | Out-Null
New-Item -ItemType Directory -Path $logsDir    -Force | Out-Null

# Copy the pull script from this installer repo (bundled alongside) if present,
# otherwise fall back to writing it inline. The bundled copy is the source of
# truth; this keeps the installed copy identical to the repo version.
$pullScript  = "$scriptsDir\pull-windows.ps1"
$scriptSource = Join-Path $PSScriptRoot "scripts\pull-windows.ps1"

if (Test-Path $scriptSource) {
    Copy-Item $scriptSource $pullScript -Force
} else {
    # Fallback: write the pull script directly. Kept in sync with scripts/pull-windows.ps1.
    $pullBody = @'
$repoDir = "$env:USERPROFILE\Ek-ai"
$logFile = "$repoDir\logs\pull.log"
$maxLines = 500

Set-Location $repoDir

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Add-Content $logFile "─────────────────────"
Add-Content $logFile "[$timestamp] Starting pull"

$output = git pull 2>&1
Add-Content $logFile $output

if ($LASTEXITCODE -eq 0) {
  Add-Content $logFile "[$timestamp] Pull successful"
} else {
  Add-Content $logFile "[$timestamp] Pull failed with exit code $LASTEXITCODE"
}

$lines = Get-Content $logFile
if ($lines.Count -gt $maxLines) {
  $lines | Select-Object -Last $maxLines | Set-Content $logFile
}
'@
    Set-Content -Path $pullScript -Value $pullBody -Encoding UTF8
}
Ok "Daily pull script installed"

# ─── 7. Schedule the daily 11:30am update via Task Scheduler ────────────────
# -StartWhenAvailable: if the machine is asleep/off at 11:30am, the task runs as
# soon as it wakes. Important for laptop users who won't always be on at 11:30.
try {
    $action = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-NonInteractive -File `"$installDir\scripts\pull-windows.ps1`""
    $trigger = New-ScheduledTaskTrigger -Daily -At "11:30AM"
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable
    Register-ScheduledTask `
        -TaskName $taskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Force | Out-Null
} catch {
    Write-Host "✗ Could not schedule the daily update automatically."
    Write-Host "  Ekagra AI is installed and will work, but updates won't download on their own."
    Write-Host "  Please contact your Ekagra AI contact to finish setup."
    exit 1
}
Ok "Daily updates scheduled (every day at 11:30am)"

# ─── Done ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "─────────────────────────────────────────────"
Write-Host "✓ Setup complete. Ekagra AI is ready."
Write-Host ""
Write-Host "Your skills are in: %USERPROFILE%\Ek-ai"
Write-Host "Updates download automatically every morning at 11:30am."
Write-Host "You don't need to do anything else."
Write-Host "─────────────────────────────────────────────"

exit 0
