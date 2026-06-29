# ekagra-ai-installer

One-command setup scripts that let a **user** install the Ekagra AI
"chief-of-staff" from a private GitHub repo — **no GitHub account, no git
knowledge required** on their end. After setup, their machine pulls fresh
content automatically every morning at 11:30am.

This repo holds the installer. The actual product lives in
[`ai-for-india-sid/ekagra-ai`](https://github.com/ai-for-india-sid/ekagra-ai)
and is pulled onto the user's machine at install time.

---

## What is Ekagra?

**Ekagra** is an AI "chief-of-staff" — a personal assistant that lives on the
user's own machine. Rather than running as a hosted web app, its content is
distributed as files in a private GitHub repo
([`ai-for-india-sid/ekagra-ai`](https://github.com/ai-for-india-sid/ekagra-ai))
and synced down to each user's computer.

The model is deliberately simple:

- **It lives locally.** The product is cloned into `~/Ek-ai` on the user's
  machine, so it works offline and the user owns their copy.
- **It stays fresh on its own.** A scheduled daily `git pull` at 11:30am keeps
  each machine up to date with the latest content — the user never touches git.
- **It's private by design.** Each user gets their own read-only SSH deploy key,
  so access can be granted or revoked per person without affecting anyone else.

This repo (`ekagra-ai-installer`) is just the **installer** that sets all of
that up in one command. Ekagra itself is the content that gets pulled down.

---

## How it works (the 30-second version)

1. The user runs a one-line install command (Mac or Windows).
2. The script generates a dedicated **SSH key** on their machine and copies the
   public half to their clipboard.
3. The user pastes that key into WhatsApp/email and sends it to their Ekagra
   contact (Sid).
4. **Sid adds it as a read-only deploy key** on the private repo (see
   [Per-user manual step](#per-user-manual-step--sid-only)).
5. The user presses Enter; the script clones the repo and schedules a daily
   `git pull` at 11:30am. Done — they never touch git again.

Each user gets their own key, so a single compromised machine can be revoked
without affecting anyone else.

---

## File structure

```
ekagra-ai-installer/
├── README.md                     ← this file
├── install-mac.sh                ← one-time setup for Mac users
├── install-windows.ps1           ← one-time setup for Windows users
└── scripts/
    ├── pull-mac.sh               ← daily pull, called by launchd
    └── pull-windows.ps1          ← daily pull, called by Task Scheduler
```

| File | What it does |
|------|--------------|
| `install-mac.sh` | One-time Mac setup: checks git, generates an SSH key, wires up SSH config, prompts the user to send their key to Ekagra, clones the repo into `~/Ek-ai`, installs the daily pull script, and registers a launchd job for 11:30am. |
| `install-windows.ps1` | Same flow for Windows, using Task Scheduler instead of launchd. |
| `scripts/pull-mac.sh` | Runs daily via launchd. Does a `git pull`, appends a timestamped line to `~/Ek-ai/logs/pull.log`, and rotates the log to its last 500 lines. No user interaction. |
| `scripts/pull-windows.ps1` | Windows equivalent of the above. Writes to `%USERPROFILE%\Ek-ai\logs\pull.log`. |

Both install scripts are **idempotent** — safe to re-run. They will not create a
second SSH key, duplicate SSH config block, duplicate scheduled job, or a second
clone.

---

## For end users — how to install

> These one-liners download the installer straight from this repo and run it.
> They are what you paste into a chat with a new user.

### Mac (Terminal)

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ai-for-india-sid/ekagra-ai-installer/main/install-mac.sh)"
```

### Windows (PowerShell — right-click → "Run as Administrator" not required)

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; `
irm https://raw.githubusercontent.com/ai-for-india-sid/ekagra-ai-installer/main/install-windows.ps1 | iex
```

The installer pauses halfway and tells the user to send you their key. **That's
your cue** to do the per-user step below. Once you confirm activation, they
press Enter and finish on their own.

---

## Per-user manual step — Sid only

Every new user sends you a public key (looks like
`ssh-ed25519 AAAAC3N... ekagra-ai-deploy`). You must register it on the private
repo before their install can finish.

1. Go to **https://github.com/ai-for-india-sid/ekagra-ai/settings/keys**
   (repo → **Settings** → **Deploy keys**).
2. Click **Add deploy key**.
3. **Title:** the user's name (e.g. `Riya — MacBook`), so you can identify it later.
4. **Key:** paste the key the user sent you.
5. Leave **"Allow write access" unchecked** (read-only is all they need).
6. Click **Add key**.

To revoke a user later: same page → **Delete** next to their key. Instant,
affects only that one machine.

> ⚠️ Deploy keys are per-repo and capped at 1 active key each in some GitHub
> configs. This repo uses one key per user, which GitHub supports. If you ever
> hit a limit, switch to a **machine user** account — see
> [Troubleshooting](#troubleshooting).

---

## How to host the installers publicly

The one-liners above pull the scripts from this repo's `main` branch via
`raw.githubusercontent.com`. **No extra hosting is needed** — just keep this
repo public and push changes to `main`.

To update an installer:

1. Edit the file in this repo.
2. Commit and push to `main`.
3. The next user who runs the one-liner gets the new version automatically
   (GitHub's raw endpoint serves the latest `main` content within seconds).

> The raw URL format is:
> `https://raw.githubusercontent.com/ai-for-india-sid/ekagra-ai-installer/main/<filename>`
>
> If you ever want a **pinned, immutable** version (so an installer can't change
> under you), use a commit SHA or git tag instead of `main`:
> `https://raw.githubusercontent.com/ai-for-india-sid/ekagra-ai-installer/<SHA>/install-mac.sh`

---

## Verifying a user's setup is working

After a user finishes install, ask them to share the contents of their pull log.

**Mac:**
```bash
cat ~/Ek-ai/logs/pull.log
```

**Windows:**
```powershell
Get-Content "$env:USERPROFILE\Ek-ai\logs\pull.log"
```

A healthy log looks like:
```
─────────────────────
[2026-06-23 11:30:00] Starting pull
Already up to date.
[2026-06-23 11:30:01] Pull successful
```

If you see `Pull failed`, the most common cause is the deploy key wasn't added
(or was added with a typo). Re-check the [per-user step](#per-user-manual-step--sid-only).

### Manually trigger a pull (don't wait for 11:30am)

**Mac:**
```bash
bash ~/Ek-ai/scripts/pull-mac.sh
```

**Windows:**
```powershell
& "$env:USERPROFILE\Ek-ai\scripts\pull-windows.ps1"
```

Then re-check the log as above.

---

## Testing the installer yourself (before shipping to users)

You can dry-run the full flow on your own machine without affecting a real user.

**Mac:**
```bash
# 1. Run the installer from this repo
bash install-mac.sh
# 2. When it pauses, add the key it copied to your clipboard as a deploy key
#    on ekagra-ai (see per-user step above), then press Enter.
# 3. Verify the clone landed:
ls ~/Ek-ai
# 4. Verify the schedule is registered:
launchctl list | grep ekagra
# 5. Trigger a manual pull and check the log:
bash ~/Ek-ai/scripts/pull-mac.sh
cat ~/Ek-ai/logs/pull.log
```

**Windows:**
```powershell
# 1. Run the installer
.\install-windows.ps1
# 2. When it pauses, add the deploy key, then press Enter.
# 3. Verify the clone:
Get-ChildItem "$env:USERPROFILE\Ek-ai"
# 4. Verify the scheduled task exists:
Get-ScheduledTask -TaskName "ekagra-ai Daily Pull"
# 5. Trigger a manual pull and check the log:
& "$env:USERPROFILE\Ek-ai\scripts\pull-windows.ps1"
Get-Content "$env:USERPROFILE\Ek-ai\logs\pull.log"
```

To **uninstall** (useful while testing):
```bash
# Mac
launchctl unload ~/Library/LaunchAgents/ai.ekagra.daily-pull.plist
rm ~/Library/LaunchAgents/ai.ekagra.daily-pull.plist
rm -rf ~/Ek-ai
rm -f ~/.ssh/ekagra_deploy ~/.ssh/ekagra_deploy.pub
# (also remove the ekagra-github block from ~/.ssh/config)
```
```powershell
# Windows
Unregister-ScheduledTask -TaskName "ekagra-ai Daily Pull" -Confirm:$false
Remove-Item -Recurse -Force "$env:USERPROFILE\Ek-ai"
Remove-Item -Force "$env:USERPROFILE\.ssh\ekagra_deploy", "$env:USERPROFILE\.ssh\ekagra_deploy.pub"
# (also remove the ekagra-github block from %USERPROFILE%\.ssh\config)
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `✗ Could not connect to the repository.` at clone time | Deploy key not yet added, or added with a typo | Re-add the key on the repo's Deploy keys page; have the user re-run install. |
| `Permission denied (publickey)` in pull.log | Key was deleted from the repo, or the user's `~/.ssh/config` lost the `ekagra-github` block | Re-add the key / re-run install. |
| Clone hangs / fails silently with `authenticity of host 'github.com' can't be established` | First-ever SSH connection to github.com on that machine; SSH wants interactive confirmation but the clone suppresses output | The installer now pre-trusts GitHub's host keys automatically. For an existing install that hit this, run `ssh -T git@ekagra-github` once and answer `yes`, then re-run the installer. |
| Pull log shows nothing / file missing | The scheduled job hasn't fired yet, or the machine was off at 11:30am and hasn't woken | Have the user run the manual pull command above. On Windows, `-StartWhenAvailable` means it'll catch up on wake. On Mac, `RunAtLoad` makes it run on every login too, so a missed pull is caught up the moment the lid opens and the user logs in. |
| launchd job exists but never runs | Mac was off at 11:30am and not yet logged in | The job also runs at login (`RunAtLoad`), so it'll catch up when the user next logs in. If it's still not running, have them run the manual pull command. |
| `Set-ExecutionPolicy` blocked on Windows | Corporate policy restricts scripts | Have them run the one-liner as written; `-Scope Process` usually clears it. If truly blocked, run `powershell.exe -ExecutionPolicy Bypass -File install-windows.ps1` from a downloaded copy. |
| Hitting GitHub deploy-key limits | Many users on one repo | Migrate to a **machine user** account that has read access to the repo, and use one shared key — see GitHub's [machine user docs](https://docs.github.com/en/get-started/learning-about-github/types-of-github-accounts#machine-accounts). |

---

## Design constraints (for maintainers)

- **Pure bash and PowerShell only.** No Python, Node, Ruby, or package managers.
- **Works offline** after the initial clone (the only network call is `git pull`).
- **Idempotent.** Re-running install never breaks anything or duplicates state.
- **No raw git errors shown to users.** Every failure is wrapped in plain English.
- **Per-user keys**, so compromise of one machine is revocable in isolation.
