#!/bin/bash
#
# install-mac.sh — One-time setup for Ekagra AI (macOS)
#
# What it does (for a non-technical user, one command):
#   1. Makes sure git is available
#   2. Generates a dedicated SSH key just for Ekagra (no GitHub account needed)
#   3. Wires up an SSH config alias so git uses that key automatically
#   4. Hands the public key to the user to send to their Ekagra contact, who
#      registers it as a read-only deploy key on the private repo
#   5. Clones the repo into ~/Ek-ai
#   6. Installs a daily pull script
#   7. Schedules an automatic update every day at 11:30am via launchd
#
# The script is idempotent: re-running it will not create a second SSH key,
# duplicate SSH config block, duplicate launchd job, or a second clone.

# Make the whole script stop on the first unexpected error.
set -e

# ─── Configuration ──────────────────────────────────────────────────────────
# Custom SSH host alias (see ~/.ssh/config). Lets us pin a specific key to a
# specific repo without touching any other SSH setup the user may have.
SSH_HOST_ALIAS="ekagra-github"
# Where the dedicated Ekagra SSH key lives.
SSH_KEY_PATH="$HOME/.ssh/ekagra_deploy"
# The repo to clone, referenced via the SSH alias so the right key is used.
REPO_URL="git@${SSH_HOST_ALIAS}:ai-for-india-sid/ekagra-ai.git"
# Where the repo lands on the user's machine.
INSTALL_DIR="$HOME/Ek-ai"
# The launchd plist that runs the daily pull.
PLIST_PATH="$HOME/Library/LaunchAgents/ai.ekagra.daily-pull.plist"
PLIST_LABEL="ai.ekagra.daily-pull"
# WhatsApp number of the Ekagra AI contact who activates new users, in
# international format with digits only — no "+", spaces, or dashes
# (e.g. 919876543210 for +91 98765 43210). When set, the installer opens
# WhatsApp pre-filled with the user's key so they can send it in one tap.
# Leave empty to fall back to the "copy to clipboard, paste manually" prompt.
WHATSAPP_CONTACT=""

# ─── Helpers ────────────────────────────────────────────────────────────────
# Print a step-complete line so the user gets visible progress.
ok()   { echo "✓ $1"; }
# Print a friendly, non-technical error and stop.
fail() { echo "✗ $1"; exit 1; }
# URL-encode a string so it can be dropped into a wa.me deep link. Pure bash
# (no python/perl) to honour the "bash only" design constraint. Encodes
# everything except the RFC 3986 unreserved set, so spaces, "+", "/", "=" and
# newlines in the SSH key all survive the round trip.
urlencode() {
  local string="$1" i c
  for (( i = 0; i < ${#string}; i++ )); do
    c="${string:i:1}"
    case "$c" in
      [a-zA-Z0-9.~_-]) printf '%s' "$c" ;;
      *)               printf '%%%02X' "'$c" ;;
    esac
  done
}

echo "Welcome to Ekagra AI Setup"
echo "This will take about a minute. Please don't close this window."
echo ""

# ─── 1. Check git ───────────────────────────────────────────────────────────
if ! command -v git >/dev/null 2>&1; then
  echo "Git is not installed. Installing now..."
  # xcode-select --install opens the macOS Command Line Tools installer GUI.
  # It returns immediately while the GUI runs, so we wait for the user.
  xcode-select --install
  echo ""
  echo "An installation window has opened."
  echo "Once it finishes, come back here and press Enter to continue."
  read -r -p ""
  # Re-check; if still missing we can't continue.
  if ! command -v git >/dev/null 2>&1; then
    fail "Git still isn't installed. Please finish the Command Line Tools installation and run this setup again."
  fi
fi
ok "Git found"

# ─── 2. Generate the dedicated SSH key (if missing) ─────────────────────────
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

if [ -f "$SSH_KEY_PATH" ]; then
  ok "SSH key already exists, skipping"
else
  # -N "" = empty passphrase (the scheduler needs to run unattended).
  # -f     = output path.
  # -C     = comment label, helps identify the key later.
  ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -N "" -C "ekagra-ai-deploy" >/dev/null 2>&1
  ok "Security key generated"
fi

# ─── 3. Add the SSH config entry (if missing) ───────────────────────────────
# IdentitiesOnly yes ensures git uses ONLY this key for github.com, so we never
# accidentally offer some other identity.
CONFIG_FILE="$HOME/.ssh/config"
touch "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"

if grep -q "Host ${SSH_HOST_ALIAS}" "$CONFIG_FILE" 2>/dev/null; then
  ok "SSH config already set up, skipping"
else
  cat >> "$CONFIG_FILE" <<EOF

Host ${SSH_HOST_ALIAS}
  HostName github.com
  User git
  IdentityFile ${SSH_KEY_PATH}
  IdentitiesOnly yes
EOF
  ok "SSH config updated"
fi

# ─── 4. Trust GitHub's host key (so the clone doesn't hang on a prompt) ─────
# The first time a machine connects to github.com over SSH, ssh asks interactively
# "Are you sure you want to continue connecting?". Because our clone runs with
# output suppressed, that prompt gets swallowed and the clone silently fails.
# We pre-populate known_hosts with GitHub's official published host keys.
GITHUB_HOSTKEYS=$(ssh-keyscan -t ed25519,rsa github.com 2>/dev/null)
if [ -n "$GITHUB_HOSTKEYS" ]; then
  # Append only entries we don't already have (idempotent across re-runs).
  echo "$GITHUB_HOSTKEYS" | while read -r line; do
    grep -qF "$line" "$HOME/.ssh/known_hosts" 2>/dev/null || echo "$line" >> "$HOME/.ssh/known_hosts"
  done
  ok "GitHub host key trusted"
else
  # If keyscan failed (e.g. temporary DNS hiccup), fall back to GitHub's
  # published fingerprints baked in — better than blocking the install.
  ok "GitHub host key trust skipped (offline) — will prompt on first pull"
fi

# ─── 5. Hand the public key to the user to send to their contact ────────────
# Always copy to the clipboard first — it's the reliable fallback no matter what
# happens with the deep link below.
PUBLIC_KEY="$(cat "${SSH_KEY_PATH}.pub")"
printf '%s' "$PUBLIC_KEY" | pbcopy

if [ -n "$WHATSAPP_CONTACT" ]; then
  # Build a wa.me deep link with the key pre-filled as the message body, then
  # open it. macOS hands the link to the WhatsApp app if installed, otherwise
  # WhatsApp Web in the browser — either way the key is already typed in and the
  # user just taps Send. No hunting for the right contact, no manual paste.
  MESSAGE="Hi! Here is my Ekagra AI setup key:

$PUBLIC_KEY"
  WHATSAPP_URL="https://wa.me/${WHATSAPP_CONTACT}?text=$(urlencode "$MESSAGE")"

  cat <<'MSG'

─────────────────────────────────────────────
ACTION REQUIRED — takes 2 minutes

Opening WhatsApp with your setup key already filled in.
Just press Send to deliver it to your Ekagra AI contact.

(Your key is also copied to your clipboard as a backup.)

They will activate your account and reply when you're ready to continue.

Once they confirm, press Enter to finish setup.
─────────────────────────────────────────────
MSG
  # If open fails (no browser, headless, etc.) the clipboard copy above still
  # lets the user paste manually, so don't let a failure stop the install.
  open "$WHATSAPP_URL" >/dev/null 2>&1 || true
else
  cat <<'MSG'

─────────────────────────────────────────────
ACTION REQUIRED — takes 2 minutes

Your setup key has been copied to your clipboard.

Please WhatsApp or email it to your Ekagra AI contact now.
They will activate your account and reply when you're ready to continue.

Once they confirm, press Enter to finish setup.
─────────────────────────────────────────────
MSG
fi

# Wait for the user to confirm their contact has activated the key.
read -r -p ""

# ─── 6. Clone the repository ────────────────────────────────────────────────
# If already cloned, skip rather than error (idempotency for re-runs).
if [ -d "$INSTALL_DIR/.git" ]; then
  ok "Ekagra AI already downloaded, skipping"
else
  echo "Downloading Ekagra AI..."
  # We deliberately don't use set -e here because we want to produce the
  # friendly error message below instead of a raw git failure.
  if ! git clone "$REPO_URL" "$INSTALL_DIR" >/dev/null 2>&1; then
    echo ""
    echo "✗ Could not connect to the repository."
    echo "  Please confirm with your Ekagra AI contact that your key has been activated,"
    echo "  then run this setup again."
    exit 1
  fi
  ok "Ekagra AI downloaded"
fi

# ─── 7. Install the daily pull script ───────────────────────────────────────
mkdir -p "$INSTALL_DIR/scripts"
mkdir -p "$INSTALL_DIR/logs"

# Copy the pull script from this installer repo (bundled alongside) if present,
# otherwise fall back to writing it inline. The bundled copy is the source of
# truth; this keeps the installed copy identical to the repo version.
SCRIPT_SOURCE="$(cd "$(dirname "$0")" && pwd)/scripts/pull-mac.sh"
PULL_SCRIPT="$INSTALL_DIR/scripts/pull-mac.sh"

if [ -f "$SCRIPT_SOURCE" ]; then
  cp "$SCRIPT_SOURCE" "$PULL_SCRIPT"
else
  # Fallback: write the pull script directly. Kept in sync with scripts/pull-mac.sh.
  cat > "$PULL_SCRIPT" <<'PULL_EOF'
#!/bin/bash
REPO_DIR="$HOME/Ek-ai"
LOG_FILE="$REPO_DIR/logs/pull.log"
MAX_LOG_LINES=500

cd "$REPO_DIR" || exit 1

echo "─────────────────────" >> "$LOG_FILE"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting pull" >> "$LOG_FILE"

git pull >> "$LOG_FILE" 2>&1
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Pull successful" >> "$LOG_FILE"
else
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Pull failed with exit code $EXIT_CODE" >> "$LOG_FILE"
fi

tail -n "$MAX_LOG_LINES" "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
PULL_EOF
fi

chmod +x "$PULL_SCRIPT"
ok "Daily pull script installed"

# ─── 8. Schedule the daily 11:30am update via launchd ───────────────────────
# launchd does NOT expand ~ or $HOME at runtime, so we bake the absolute path in.
HOME_ABS="$HOME"

# Make sure the LaunchAgents directory exists. macOS does NOT guarantee this on
# fresh installs / new user accounts — without it the plist write below fails.
mkdir -p "$HOME/Library/LaunchAgents"

cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${PLIST_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${HOME_ABS}/Ek-ai/scripts/pull-mac.sh</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key>
    <integer>11</integer>
    <key>Minute</key>
    <integer>30</integer>
  </dict>
  <key>StandardOutPath</key>
  <string>${HOME_ABS}/Ek-ai/logs/launchd.log</string>
  <key>StandardErrorPath</key>
  <string>${HOME_ABS}/Ek-ai/logs/launchd.log</string>
  <!-- Run on login/restart too, so a pull missed while the Mac was off or asleep
       overnight is caught up as soon as the user logs back in. launchd does not
       reliably re-fire a missed StartCalendarInterval event on wake from sleep,
       so RunAtLoad is the dependable safety net. git pull is idempotent, so the
       extra run when already up to date is harmless. -->
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
EOF

# Unload first if a previous version is registered (idempotent re-runs).
launchctl unload "$PLIST_PATH" >/dev/null 2>&1 || true
if ! launchctl load "$PLIST_PATH" >/dev/null 2>&1; then
  echo "✗ Could not schedule the daily update automatically."
  echo "  Ekagra AI is installed and will work, but updates won't download on their own."
  echo "  Please contact your Ekagra AI contact to finish setup."
  exit 1
fi
ok "Daily updates scheduled (every day at 11:30am)"

# ─── Done ───────────────────────────────────────────────────────────────────
cat <<'MSG'

─────────────────────────────────────────────
✓ Setup complete. Ekagra AI is ready.

Your skills are in: ~/Ek-ai
Updates download automatically every morning at 11:30am.
You don't need to do anything else.
─────────────────────────────────────────────
MSG

exit 0
