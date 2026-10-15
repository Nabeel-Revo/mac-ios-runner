#!/bin/bash
# Watches the runner log: notifications, who triggered each job, network usage, and a monthly job log.
# Keeps the Mac awake while a job runs. Started at login by a LaunchAgent (installed by setup.sh).
KIT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$KIT_DIR/lib.sh"

# "<workflow>\t<user>" for the job this runner is running, looked up in WATCH_REPOS.
who() {
  local repo run try
  if [ -z "${WATCH_REPOS:-}" ] || ! command -v gh >/dev/null; then printf "unknown\tunknown\n"; return; fi
  for try in 1 2 3 4 5 6; do   # GitHub links the job to the runner a few seconds after it starts
    for repo in $WATCH_REPOS; do
      # re-runs stay listed as "queued" for a while after their job starts, so check both
      for run in $(gh api "repos/$repo/actions/runs?status=in_progress" -q '.workflow_runs[].id' 2>/dev/null) \
                 $(gh api "repos/$repo/actions/runs?status=queued" -q '.workflow_runs[].id' 2>/dev/null); do
        if gh api "repos/$repo/actions/runs/$run/jobs" \
             -q ".jobs[]|select(.runner_name==\"$RUNNER_NAME\" and .status==\"in_progress\")|.id" 2>/dev/null | grep -q .; then
          gh api "repos/$repo/actions/runs/$run" -q '"\(.name)\t\(.triggering_actor.login)"'; return
        fi
      done
    done
    sleep 10
  done
  printf "another repo\tunknown\n"
}

# "<bytes in> <bytes out>" of the Mac's main network interface since boot.
# shortcut: counts ALL traffic on this Mac during the job (yours too); use pf accounting if exact per-runner numbers matter.
iface() { route -n get default 2>/dev/null | awk '/interface:/{print $2}'; }
netbytes() { netstat -ibI "$1" 2>/dev/null | awk '/Link/{print $7, $10; exit}'; }

# Keep the screen on until the job's worker exits, if the user turned that on.
keep_screen() {
  local w; w=$(pgrep -u "$RUNNER_USER" -f Runner.Worker | head -1)
  { [ -f "$STATE/keep-screen-on" ] && [ -n "$w" ] && caffeinate -d -w "$w"; } >/dev/null 2>&1 &
}

until [ -r "$LOG" ]; do sleep 30; done
mkdir -p "$KIT_DIR/logs" "$STATE"
CAF=""; JOB=""; WF=""; BY=""

# Resume a job that was already running when the notifier (re)started, so its log row stays complete.
if [ -f "$STATE/current-job" ] && pgrep -u "$RUNNER_USER" -f Runner.Worker >/dev/null; then
  { read -r JOB; read -r WF; read -r BY; read -r IF; read -r IN0; read -r OUT0; } < "$STATE/current-job"
  START_S=$(stat -f %m "$STATE/current-job"); START=$(date -r "$START_S" '+%F %T')
  caffeinate -i -t 7200 & CAF=$!
  keep_screen
fi

tail -n0 -F "$LOG" 2>/dev/null | while IFS= read -r line; do
  case "$line" in
    *"Listening for Jobs"*)
      notify "Online" "Waiting for iOS jobs" ;;

    *"Running job:"*)
      JOB="${line#*Running job: }"; START=$(date '+%F %T'); START_S=$(date +%s)
      IF=$(iface); read -r IN0 OUT0 < <(netbytes "$IF")
      caffeinate -i -t 7200 & CAF=$!
      keep_screen
      IFS=$'\t' read -r WF BY < <(who)
      printf "%s\n%s\n%s\n%s\n%s\n%s\n" "$JOB" "$WF" "$BY" "$IF" "$IN0" "$OUT0" > "$STATE/current-job"
      notify "Job started" "$JOB · $WF · Triggered by: $BY" ;;

    *"completed with result:"*)
      [ -n "$CAF" ] && kill "$CAF" 2>/dev/null
      read -r IN1 OUT1 < <(netbytes "$IF")
      # no start reading (notifier restarted mid-job without state) -> 0
      IN=$(( (${IN1:-0} - ${IN0:-${IN1:-0}}) / 1048576 )); OUT=$(( (${OUT1:-0} - ${OUT0:-${OUT1:-0}}) / 1048576 ))
      RESULT="${line##*result: }"
      F="$KIT_DIR/logs/$(date +%Y-%m).tsv"
      [ -f "$F" ] || printf "started\tfinished\tminutes\tjob\tworkflow\ttriggered_by\tMB_down\tMB_up\tresult\n" > "$F"
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "${START:-?}" "$(date '+%F %T')" \
        "$(( ($(date +%s) - ${START_S:-$(date +%s)}) / 60 ))" "${JOB:-?}" "${WF:-?}" "${BY:-?}" "$IN" "$OUT" "$RESULT" >> "$F"
      rm -f "$STATE/current-job"
      notify "Job finished" "$RESULT · ${IN} MB down / ${OUT} MB up"
      CAF=""; START="" ;;
  esac
done
