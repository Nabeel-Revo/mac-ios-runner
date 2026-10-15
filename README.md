# mac-ios-runner

Turn your Apple Silicon MacBook into a **GitHub Actions runner for iOS builds** without giving
build jobs access to your files, keychain or admin rights. While it's on, you get notifications
and a menu bar icon, so you always know when your Mac is building and who started the build.

> **Using Claude Code?** Open this folder and say *"set this up for me"*. Claude follows
> [`CLAUDE.md`](CLAUDE.md) and walks you through one step at a time.

---

## What you get

- **Isolation:** builds run as a separate, hidden, **non-admin** macOS user (`ci-runner`). Your
  home folder is locked, so a build can't read your files, SSH keys, browser data or keychain,
  and it can't use `sudo`.
- **Your Xcode stays yours:** the runner uses its own Xcode (e.g. `/Applications/Xcode-26.5.app`).
  Upgrade or beta-test your own Xcode freely.
- **Notifications** when the runner comes online, when a job starts (which workflow, who
  triggered it) and when it finishes (result, data used).
- **Menu bar icon** (via [SwiftBar](https://swiftbar.app)):

  | Icon | Meaning |
  |---|---|
  | 📱 green | On, waiting for jobs |
  | 🔨 orange | Building. The menu shows the job, workflow, who triggered it, live data |
  | 📱 grey with slash | Off |

  The menu has **Turn on/off**, **Priority** (Low / Standard), **Keep screen on during jobs**,
  **Open log** and **Job logs (by month)**.
- **Monthly job log** in `logs/YYYY-MM.tsv`: start, finish, minutes, job, workflow, triggered by,
  MB down/up and result.
- **Off by default, on when you want.** It uses nothing while off. A small background process
  runs while it's on and idle.

## How it works

```
GitHub ── job for runs-on: [self-hosted, macOS, ARM64, ios-build] ──▶ your Mac
                                                                         │
   launchd service (system) ── runs as user "ci-runner" ── GitHub Actions runner ── xcodebuild / EAS
                                                                         │
   runner.log (/Users/Shared/ci-runner) ──▶ notify.sh (you) ──▶ notifications, monthly log
                                                         └──▶ SwiftBar menu bar icon
```

## Requirements

- An **Apple Silicon** Mac (M1 or later) with **~20 GB free**: Xcode ~4 GB, iOS platform ~8 GB,
  plus build caches.
- An **admin account** on the Mac (for the one-time setup).
- [Homebrew](https://brew.sh).
- A **runner registration token** from a GitHub admin of your org (step 3). It's valid for 1 hour.
- Optional: the [GitHub CLI](https://cli.github.com) (`gh`) logged in, to show who triggered each job.

---

## Setup

Each step is something you run in Terminal. Do them in order.

### 1. Install the tools

```bash
brew install cocoapods fastlane
brew install --cask swiftbar
```

### 2. Install the runner's Xcode

Use the Xcode version your iOS builds expect. Ask your team or check another runner's build log.
The runner gets its **own copy**, separate from the one you use.

1. Download **Xcode <version> (Apple silicon)** (`.xip`) from
   https://developer.apple.com/download/all/ (Apple ID sign-in).
2. Extract it in an empty folder, then move it into Applications with a versioned name:
   ```bash
   mkdir -p ~/Downloads/xcode-runner && cd ~/Downloads/xcode-runner
   xip -x ~/Downloads/Xcode_26.5_Apple_silicon.xip          # 5–15 min, creates Xcode.app
   sudo mv Xcode.app /Applications/Xcode-26.5.app
   ```
3. Check it:
   ```bash
   DEVELOPER_DIR=/Applications/Xcode-26.5.app/Contents/Developer xcodebuild -version
   ```

### 3. Configure

```bash
git clone <this repo> ~/Repos/mac-ios-runner && cd ~/Repos/mac-ios-runner
cp config.env.example config.env
open -e config.env
```

Fill in at least:

| Setting | What to put |
|---|---|
| `GITHUB_URL` | `https://github.com/<your-org>` (or `https://github.com/<owner>/<repo>` for a single repo) |
| `RUNNER_NAME` | A name for this Mac on GitHub's runners page, e.g. `ab-macbook` |
| `RUNNER_LABELS` | The extra label(s) your iOS workflows use in `runs-on:`, e.g. `ios-build` |
| `WATCH_REPOS` | The repo(s) whose workflows use this runner, e.g. `your-org/your-app` |
| `XCODE_APP` | The path from step 2 |

### 4. Get a registration token

Registering a runner needs an **org owner** (or repo admin). Ask them to open:

**github.com/`<your-org>` → Settings → Actions → Runners → New runner → New self-hosted runner**

and send you the value after `--token` in the `./config.sh` line. Ignore the rest of that page;
`setup.sh` does it for Apple Silicon. The token **expires about 1 hour** after the page is opened,
so ask for it when you're ready for step 5.

> Don't paste the token into chats or commit it. It only goes into the command below.

### 5. Run the setup

```bash
sudo ./setup.sh <TOKEN>
```

What it does:

1. Creates the hidden standard user `ci-runner`.
2. Locks your home folder (`chmod 700`).
3. Prepares the runner's Xcode: license, first-launch components, **iOS platform** (~8 GB) and
   the **Apple WWDR G3** certificate.
4. Downloads the arm64 runner and registers it as `RUNNER_NAME`.
5. Installs the background service (left **off**).
6. Installs the notifier and points SwiftBar at this folder.

Safe to ignore in its output: `getcwd: Permission denied`, and a FileVault ("FDE") note from `sysadminctl`.

### 6. Turn it on

```bash
open -a SwiftBar          # menu bar icon
./runnerctl on
```

You should get an **"iOS runner, Online"** notification, the icon turns green, and your runner
shows **Idle** on GitHub's runners page.

- **No notification?** Run `osascript -e 'display notification "test" with title "iOS runner"'`
  once from **Script Editor**, allow notifications, then in **System Settings → Notifications →
  Script Editor** set the style to **Alerts** or **Banners**.
- **Icon after reboots:** **System Settings → General → Login Items & Extensions → Open at Login → + → SwiftBar**.

### 7. Test

Trigger an iOS workflow (or re-run one) while your runner is the only free one. In the run, the
job's **Set up job** step shows `Runner name: '<your RUNNER_NAME>'`.

---

## Daily use

| Do | How |
|---|---|
| Turn on / off | Menu bar → Turn on / Turn off, or `./runnerctl on` / `off` |
| See what it's doing | Menu bar icon, or `./runnerctl status` / `./runnerctl log` |
| Faster builds vs. a smoother Mac | Menu bar → Priority → **Standard** (default) or **Low**. Takes effect when no job is running; a running build is never interrupted |
| Keep the screen on during jobs | Menu bar → Keep screen on during jobs |
| Review past jobs | Menu bar → Job logs (by month), or `./runnerctl logs` |

**While the runner is on: keep the Mac plugged in and the lid open** (or use an external display).
Closing the lid on battery always sleeps the Mac, and GitHub then fails the job with *"The
self-hosted runner lost communication with the server"*. Before you pack up, use **Turn off**.

The runner state survives reboots: if it was on, it starts again at boot (even before you log in).

## Security: what a build can and can't do

A build runs as `ci-runner`. Anyone who can push a workflow to a repo that uses your runner's
labels can run code here, and so can a malicious dependency pulled in during a build.

| ✅ It can't | ⚠️ It can |
|---|---|
| Read your home folder (files, SSH keys, browser data, keychain) | Connect to services listening on your Mac (local databases, dev servers) |
| Use `sudo` or change system settings | Reach your home or office network |
| See your screen, keystrokes or control apps | See your running processes and their command-line arguments |
| | Read world-readable places (`/Applications`, `/opt/homebrew`, `/Users/Shared`) |
| | Leave files in its own home that later builds see |

Keep secrets out of command-line arguments, and don't leave password-less local services
(e.g. Redis, or a Postgres with a default password) listening while the runner is on. A `pf`
firewall rule blocking the `ci-runner` user from localhost and the LAN closes the main gap. It
isn't included yet.

## Uninstall

```bash
sudo ./uninstall.sh
```

This removes the service, the `ci-runner` user and its files, the notifier and the logs. Then ask
a GitHub admin to delete the runner from the runners page. Xcode, Homebrew tools and SwiftBar stay.

## Files

| File | Purpose |
|---|---|
| `config.env.example` | Settings template. Copy to `config.env` (gitignored) |
| `setup.sh` | One-time setup (sudo) |
| `runnerctl` | on / off / status / log / logs / screen / priority |
| `notify.sh` | Notifications, keep-awake, monthly logs (runs at login) |
| `menubar/ios-runner.10s.sh` | SwiftBar plugin |
| `uninstall.sh` | Removes everything setup created |
| `certs/AppleWWDRCAG3.cer` | Apple's WWDR G3 intermediate certificate (public, from apple.com) |
| `TROUBLESHOOTING.md` | Known problems and fixes |
