#!/bin/bash
# Removes the runner service, the runner user (and everything in its home), the notifier and the logs.
# Keeps Xcode, Homebrew tools and SwiftBar. Run from this folder:  sudo ./uninstall.sh
set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$KIT_DIR/lib.sh"
[ "$(id -u)" = 0 ] || { echo "Run with sudo:  sudo ./uninstall.sh"; exit 1; }
ME="${SUDO_USER:?Run with sudo from your own account}"
ME_HOME=$(dscl . -read "/Users/$ME" NFSHomeDirectory | awk '{print $2}')

read -r -p "This deletes the '$RUNNER_USER' user and the runner service. Continue? [y/N] " ok
[ "$ok" = y ] || exit 0

launchctl bootout system/$LABEL 2>/dev/null
launchctl enable system/$LABEL 2>/dev/null
rm -f "$PLIST"
launchctl bootout "gui/$(id -u "$ME")/$NOTIFY_LABEL" 2>/dev/null
rm -f "$ME_HOME/Library/LaunchAgents/$NOTIFY_LABEL.plist"
id "$RUNNER_USER" >/dev/null 2>&1 && sysadminctl -deleteUser "$RUNNER_USER"
rm -rf "$LOGDIR" "$STATE"

echo
echo "Removed. Last step: ask a GitHub admin to delete runner '$RUNNER_NAME' from the runners page"
echo "(Settings → Actions → Runners), or it disappears by itself after ~14 days offline."
