# Instructions for Claude: guiding a developer through this setup

You're helping a developer turn their MacBook into an isolated GitHub Actions iOS runner using
this repo. `README.md` is the source of truth for the steps; `TROUBLESHOOTING.md` has known
failures and fixes. Read both before starting.

## How to guide

- **One step at a time.** Give the command(s) for the current step, explain in one or two
  sentences what they do, then **stop and wait** for the user to run them and report back. Don't
  dump the whole guide.
- **Check before moving on.** Each README step has a check (e.g. `xcodebuild -version`, the
  "Online" notification). Confirm it passed; if not, look in `TROUBLESHOOTING.md` first.
- **Commands needing `sudo` or a password: the user runs them**, not you. That covers
  `setup.sh`, `uninstall.sh`, `runnerctl on/off/priority`, `sudo mv`, `xcodebuild -downloadPlatform`.
  You may run read-only checks yourself (`pgrep`, `ls`, `xcodebuild -version`, `gh run view`).
- **Tokens:** the registration token goes only into `sudo ./setup.sh <TOKEN>`, typed by the user.
  Don't ask them to paste it to you, and never write it to a file. It expires about 1 hour after
  the admin opens the page, so have them request it right before step 5.
- **Long downloads** (Xcode `.xip`, iOS platform ~8 GB): tell them to expect it, and wait.
- **Explain trade-offs in plain words** when they ask (isolation, priority, disk), using the
  README's security table rather than inventing claims.

## Before step 1, find out

1. Apple Silicon? (`uname -m` → `arm64`). If not, stop: this kit is arm64-only.
2. Free disk (`df -h /`): need ~20 GB.
3. Which **Xcode version** their iOS builds expect, and which **labels** the iOS jobs use
   (`runs-on:` in the workflows, e.g. `[self-hosted, macos, arm64, ios-build]`). If they have the
   app repo locally, read its `.github/workflows/*` to find these.
4. The **org URL** and a name for their runner (for `config.env`).

## Things that commonly go wrong (see TROUBLESHOOTING.md)

- Missing Apple **WWDR G3** certificate → "distribution certificate hasn't been imported".
- Missing **iOS platform** → "iOS xx is not installed".
- **Low priority** → very slow builds; default is Standard.
- **Lid closed on battery** → "runner lost communication".
- No notifications → Script Editor notification permission / alert style.
- No menu bar icon → SwiftBar not running / not in Login Items.

## Don't

- Don't edit files outside this repo except what the README steps do.
- Don't commit `config.env`, `logs/` or `state/` (they're gitignored).
- Don't turn the runner on, or restart it, while a job is running unless the user asks: restarts
  cancel the running job.
