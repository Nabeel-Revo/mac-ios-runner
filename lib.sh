# Shared settings for every script in this kit. Sourced, not run; the caller sets KIT_DIR first.
# shellcheck shell=bash
if [ ! -f "$KIT_DIR/config.env" ]; then
  echo "Missing $KIT_DIR/config.env: run  cp config.env.example config.env  and fill it in." >&2
  exit 1
fi
. "$KIT_DIR/config.env"
RUNNER_USER=${RUNNER_USER:-ci-runner}
LABEL=com.mac-ios-runner.runner                 # launchd service that runs the GitHub runner
NOTIFY_LABEL=com.mac-ios-runner.notify          # launchd agent that sends notifications
PLIST=/Library/LaunchDaemons/$LABEL.plist
LOGDIR=/Users/Shared/$RUNNER_USER               # runner output, readable by you (job names only, no secrets)
LOG=$LOGDIR/runner.log
STATE=$KIT_DIR/state
export PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin

# notify "<subtitle>" "<message>"
notify() {
  osascript -e "display notification \"$2\" with title \"iOS runner\" subtitle \"$1\" sound name \"Glass\"" >/dev/null 2>&1 || true
  if [ -n "${NTFY_TOPIC:-}" ]; then curl -s -d "$1 — $2" "https://ntfy.sh/$NTFY_TOPIC" >/dev/null || true; fi
}
