# Troubleshooting

Problems hit while building this, with their fixes. Find your symptom.

## Setup

**`config.sh` / registration fails (`NotFound`, invalid or expired token).**
Registration tokens expire about 1 hour after the admin opened the *New self-hosted runner* page.
Ask for a fresh one and re-run `sudo ./setup.sh <TOKEN>`. Re-running is safe.

**The admin's page shows an `osx-x64` download.**
Ignore it. The token works for any architecture, and `setup.sh` downloads the arm64 runner. An x64
runner would register with the `X64` label, and arm64 jobs would never reach it.

**Setup prints `getcwd: cannot access parent directories: Permission denied`.**
Harmless. Setup locks your home folder, and the runner user can't see the folder you started from.

**`sysadminctl` prints "No clear text password … will not allow user to use FDE".**
Harmless. The runner user can't unlock FileVault at boot, and it never needs to log in.

**Want to rename the runner?**
GitHub can't rename runners. Change `RUNNER_NAME`, get a fresh token, and re-run setup. Ask an
admin to delete the old (offline) entry, or it disappears after about 14 days.

## Builds

**`Distribution certificate with fingerprint … hasn't been imported successfully`**
(EAS `PREPARE_CREDENTIALS` step). The Mac is missing Apple's **WWDR G3** intermediate
certificate: only the expired 2023 one is installed, so macOS can't validate the distribution
certificate. Setup installs it. To check:
```bash
security find-certificate -a -c "Apple Worldwide Developer Relations" -p /Library/Keychains/System.keychain | grep -c BEGIN   # expect 2+
```
To install manually:
`sudo security add-certificates -k /Library/Keychains/System.keychain certs/AppleWWDRCAG3.cer`

**`xcodebuild: error: Unable to find a destination … iOS 26.x is not installed`.**
Xcode 26+ ships without the iOS platform. Setup downloads it. To do it manually:
```bash
sudo DEVELOPER_DIR=/Applications/Xcode-26.5.app/Contents/Developer xcodebuild -downloadPlatform iOS
```

**Builds are very slow (e.g. 60+ min for an archive that takes ~5 min elsewhere).**
Priority is **Low**: macOS keeps "background" services on the efficiency cores. Switch to
**Standard** (menu bar → Priority). It applies after the current job. Measured: 64 min at Low vs
5 min at Standard for the same build. The first build on a new Mac is also slower (nothing cached).

**Job fails with "The self-hosted runner lost communication with the server", no log.**
The Mac slept or lost network mid-job, usually **lid closed on battery** (check with
`pmset -g log | grep -i "Clamshell Sleep"`). Keep it plugged in with the lid open, or turn the
runner off before closing the lid. GitHub marks the job *Abandoned* only after a long timeout;
re-run it after that. A submit step may still have reached Apple/Expo before the drop, so check the
submission (e.g. on expo.dev) before re-running a submit.

**A re-run or follow-up job waits in the queue even though the runner was just used.**
GitHub doesn't keep a workflow on one runner. Each job joins the queue for its labels, and the
**oldest** queued job goes to the next free runner. Another team member's earlier-queued build can
go before your submit step.

## Notifications and menu bar

**No notifications.**
Notifications come from **Script Editor** (`osascript`). Open Script Editor, run
`display notification "hi"`, allow it, then set **System Settings → Notifications → Script
Editor → Alerts/Banners**. Check that Focus / Do Not Disturb is off.

**Notifications land in Notification Center but don't pop up.**
Script Editor's alert style is *None*. Set it to *Banners* or *Alerts*.

**Menu bar icon missing.**
SwiftBar isn't running. Run `open -a SwiftBar`, and add it to **Login Items** for after reboots.
On a MacBook, a full menu bar hides icons behind the notch: quit something to make room.

**Priority menu item looks greyed out.**
SwiftBar greys rows with a submenu but no action. The plugin gives the row a no-op action so the
submenu opens on hover. If you edited the plugin, keep that.

**Priority says Low after switching to Standard.**
A running process's priority can't be changed. The new priority applies when the runner restarts,
which happens automatically when no job is running. The menu shows
`Low → Standard after this job` while a restart is pending.

**Password pop-up "Allow administrator access for a script started by bash".**
macOS's generic warning for unsigned scripts. It's expected **only right after you clicked a menu
item** that needs admin (on/off/priority run `sudo`). If it appears unexpectedly, click *Don't Allow*.

**Job shows "another repo / Triggered by: unknown".**
The job came from a repo not listed in `WATCH_REPOS`, or `gh` isn't logged in (`gh auth status`).

## Disk

The runner's home (`/Users/ci-runner`) grows with each build: working copies, CocoaPods specs, npm
caches. Check it with `sudo du -sh /Users/ci-runner`.
