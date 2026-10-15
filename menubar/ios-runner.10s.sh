#!/bin/bash
# SwiftBar plugin: runner state in the menu bar (refreshes every 10s).
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$KIT_DIR/lib.sh"
CTL="$KIT_DIR/runnerctl"

if pgrep -u "$RUNNER_USER" -f Runner.Worker >/dev/null; then
  echo ":hammer.fill: | sfcolor=#FF9500"
  echo "---"
  { read -r JOB; read -r WF; read -r BY; read -r IF; read -r IN0; read -r OUT0; } < "$STATE/current-job" 2>/dev/null
  read -r IN1 OUT1 < <(netstat -ibI "${IF:-en0}" 2>/dev/null | awk '/Link/{print $7, $10; exit}')
  IN=$(( (${IN1:-0} - ${IN0:-${IN1:-0}}) / 1048576 )); OUT=$(( (${OUT1:-0} - ${OUT0:-${OUT1:-0}}) / 1048576 ))
  echo "Building: ${JOB:-iOS job}"
  echo "${WF:-unknown workflow}"
  echo "Triggered by: ${BY:-unknown}"
  echo "Data so far: ${IN:-0} MB down / ${OUT:-0} MB up"
elif pgrep -u "$RUNNER_USER" -f Runner.Listener >/dev/null; then
  echo ":iphone: | sfcolor=#34C759"
  echo "---"
  echo "Runner on — waiting for jobs"
else
  echo ":iphone.slash: | sfcolor=#8E8E93"
  echo "---"
  echo "Runner off"
fi
awk -F'\t' 'NR>1 {n++; d+=$7+$8} END {printf "This month: %d jobs, %.1f GB\n", n, d/1024}' \
  "$KIT_DIR/logs/$(date +%Y-%m).tsv" 2>/dev/null || echo "This month: 0 jobs"

# Priority: LIVE = what the runner process has now (macOS "background" = pri 4); SAVED = what applies after a restart.
PRI=$(ps -o pri= -p "$(pgrep -u "$RUNNER_USER" -f Runner.Listener | head -1)" 2>/dev/null | tr -d ' ')
[ "$(plutil -extract ProcessType raw "$PLIST" 2>/dev/null)" = Background ] && SAVED=Low || SAVED=Standard
if [ -z "$PRI" ]; then LIVE=$SAVED; elif [ "$PRI" -le 4 ]; then LIVE=Low; else LIVE=Standard; fi
if [ "$LIVE" = "$SAVED" ]; then P_TITLE="Priority: $LIVE"
elif pgrep -u root -f mac-ios-runner-restart-waiter >/dev/null; then P_TITLE="Priority: $LIVE → $SAVED after this job"
else P_TITLE="Priority: $LIVE ($SAVED saved — click it again to apply)"; fi
echo "---"
# no-op action: SwiftBar disables rows without one, and a disabled row's submenu can't open
echo "$P_TITLE | bash=/usr/bin/true terminal=false"
echo "--Low: slower builds, Mac stays smooth | bash=$CTL param1=priority param2=low terminal=true refresh=true checked=$([ "$SAVED" = Low ] && echo true || echo false)"
echo "--Standard: faster builds, Mac gets busier | bash=$CTL param1=priority param2=standard terminal=true refresh=true checked=$([ "$SAVED" = Standard ] && echo true || echo false)"
echo "---"
if pgrep -u "$RUNNER_USER" -f Runner.Listener >/dev/null; then
  echo "Turn off | bash=$CTL param1=off terminal=true refresh=true"
else
  echo "Turn on | bash=$CTL param1=on terminal=true refresh=true"
fi
if [ -f "$STATE/keep-screen-on" ]; then
  echo "Keep screen on during jobs | bash=$CTL param1=screen param2=off terminal=false refresh=true checked=true"
else
  echo "Keep screen on during jobs | bash=$CTL param1=screen param2=on terminal=false refresh=true checked=false"
fi
echo "Open log | bash=/usr/bin/open param1=-a param2=Console param3=$LOG terminal=false"
echo "Job logs (by month) | bash=$CTL param1=logs terminal=false"
