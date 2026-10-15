#!/bin/bash
# One-time setup of an isolated GitHub Actions iOS runner under a separate,
# non-admin macOS user. Run from this folder:  sudo ./setup.sh <registration-token>
# Safe to re-run (e.g. with a fresh token to re-register).
set -euo pipefail
KIT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$KIT_DIR/lib.sh"

[ "$(id -u)" = 0 ] || { echo "Run with sudo:  sudo ./setup.sh <registration-token>"; exit 1; }
TOKEN="${1:?usage: sudo ./setup.sh <registration-token>}"
ME="${SUDO_USER:?Run with sudo from your own account, not as root}"
ME_HOME=$(dscl . -read "/Users/$ME" NFSHomeDirectory | awk '{print $2}')
ME_UID=$(id -u "$ME")
DEV="$XCODE_APP/Contents/Developer"

echo "== 0. Checks"
[ "$(uname -m)" = arm64 ] || { echo "This kit needs an Apple Silicon Mac."; exit 1; }
[ -d "$XCODE_APP" ] || { echo "Missing $XCODE_APP (README step 2)."; exit 1; }
for t in pod fastlane; do
  [ -x "/opt/homebrew/bin/$t" ] || { echo "Missing $t (README step 1: brew install cocoapods fastlane)."; exit 1; }
done
for v in GITHUB_URL RUNNER_NAME RUNNER_LABELS; do
  [ -n "${!v:-}" ] || { echo "Set $v in config.env."; exit 1; }
done
case "$GITHUB_URL$RUNNER_NAME" in *your-*) echo "config.env still has placeholder values."; exit 1 ;; esac

echo "== 1. Standard (non-admin) user '$RUNNER_USER', hidden from the login screen"
if ! id "$RUNNER_USER" >/dev/null 2>&1; then
  # Random password nobody needs: the user never logs in, launchd starts the runner as it.
  sysadminctl -addUser "$RUNNER_USER" -fullName "CI Runner" -password "$(openssl rand -base64 24)" -home "/Users/$RUNNER_USER"
  createhomedir -c -u "$RUNNER_USER" >/dev/null
  dscl . create "/Users/$RUNNER_USER" IsHidden 1
fi
chmod 700 "/Users/$RUNNER_USER"

echo "== 2. Lock your home folder so other users (the runner) cannot read it"
chmod 700 "$ME_HOME"

echo "== 3. Xcode: licence, first-launch components, iOS platform, Apple WWDR G3 certificate"
DEVELOPER_DIR="$DEV" xcodebuild -license accept
DEVELOPER_DIR="$DEV" xcodebuild -runFirstLaunch
# Xcode 26+ ships without the iOS platform; archives fail with "iOS xx is not installed" without it.
DEVELOPER_DIR="$DEV" xcodebuild -downloadPlatform iOS
# Without this intermediate, EAS reports the distribution certificate as "not imported".
security add-certificates -k /Library/Keychains/System.keychain "$KIT_DIR/certs/AppleWWDRCAG3.cer" 2>/dev/null || true

echo "== 4. Log folder you can read"
mkdir -p "$LOGDIR"; chown "$RUNNER_USER":staff "$LOGDIR"; chmod 755 "$LOGDIR"

echo "== 5. Install + register the runner as '$RUNNER_USER'"
cd /tmp   # the runner user can't enter your (now locked) home folder
GROUP_ARG=""
case "$GITHUB_URL" in https://github.com/*/*) ;; *) GROUP_ARG="--runnergroup ${RUNNER_GROUP:-Default}" ;; esac
sudo -u "$RUNNER_USER" -H bash -c "
  set -euo pipefail
  mkdir -p ~/actions-runner && cd ~/actions-runner
  if [ ! -x ./config.sh ]; then
    curl -fsSLO https://github.com/actions/runner/releases/download/v$RUNNER_VERSION/actions-runner-osx-arm64-$RUNNER_VERSION.tar.gz
    tar xzf actions-runner-osx-arm64-$RUNNER_VERSION.tar.gz && rm actions-runner-osx-arm64-$RUNNER_VERSION.tar.gz
  fi
  ./config.sh --unattended --replace --url '$GITHUB_URL' --token '$TOKEN' \
    --name '$RUNNER_NAME' --labels '$RUNNER_LABELS' $GROUP_ARG
  # Environment for every job: the runner's Xcode only (yours stays untouched), Homebrew tools, UTF-8 for CocoaPods.
  cat > .env <<ENV
DEVELOPER_DIR=$DEV
PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin
LANG=en_US.UTF-8
LC_ALL=en_US.UTF-8
ENV
  /opt/homebrew/bin/pod repo update || true
"

echo "== 6. Background service (installed but OFF; turn on with ./runnerctl on)"
cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>UserName</key><string>$RUNNER_USER</string>
  <key>GroupName</key><string>staff</string>
  <key>WorkingDirectory</key><string>/Users/$RUNNER_USER/actions-runner</string>
  <key>ProgramArguments</key><array><string>/Users/$RUNNER_USER/actions-runner/run.sh</string></array>
  <key>EnvironmentVariables</key><dict>
    <key>HOME</key><string>/Users/$RUNNER_USER</string>
    <key>PATH</key><string>/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>SessionCreate</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Standard</string>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict></plist>
PL
chown root:wheel "$PLIST"; chmod 644 "$PLIST"
launchctl bootout system/$LABEL 2>/dev/null || true
launchctl disable system/$LABEL

echo "== 7. Notifications + menu bar for '$ME'"
LA="$ME_HOME/Library/LaunchAgents/$NOTIFY_LABEL.plist"
sudo -u "$ME" mkdir -p "$ME_HOME/Library/LaunchAgents" "$STATE" "$KIT_DIR/logs"
cat > "$LA" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$NOTIFY_LABEL</string>
  <key>ProgramArguments</key><array><string>$KIT_DIR/notify.sh</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict></plist>
PL
chown "$ME":staff "$LA"
launchctl bootout "gui/$ME_UID/$NOTIFY_LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$ME_UID" "$LA" || echo "   (notifier starts at your next login)"
sudo -u "$ME" defaults write com.ameba.SwiftBar PluginDirectory "$KIT_DIR/menubar"

echo
echo "Done. Turn the runner on with:  ./runnerctl on"
