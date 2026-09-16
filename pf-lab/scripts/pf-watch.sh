#!/usr/bin/env bash
# Watch N pf runs, logging progress until they go idle or the budget expires.
#
#   WATCH_PANES="w1:p4G w1:p4H" WATCH_RUNS=2 ./pf-watch.sh /path/to/log
#
# Environment:
#   WATCH_PANES   pane IDs to sample (space-separated). Empty is fine — the run
#                 finding counts and container status still get logged.
#   WATCH_RUNS    how many runs to count findings for          (default 5)
#   WATCH_MINUTES overall budget in minutes                    (default 30)
#   PF_RUNS_ROOT  where run workdirs live                      (default ~/pf-runs)
#
# Pane sampling needs `herdr` (a terminal agent-orchestration tool), which is only
# used when WATCH_PANES is set. Without it this is a plain run/finding poller.
set -uo pipefail

LOG="${1:-./pf-watch.log}"
read -r -a PANES <<<"${WATCH_PANES:-}"
RUNS="${WATCH_RUNS:-5}"
BUDGET_MIN="${WATCH_MINUTES:-30}"
RUNS_ROOT="${PF_RUNS_ROOT:-$HOME/pf-runs}"
deadline=$(( $(date +%s) + BUDGET_MIN * 60 ))
idle_streak=0

# Last non-empty lines only. `herdr pane read` returns full scrollback, which keeps
# stale "agent running…" strings forever — grepping the whole buffer (the previous
# bug) can therefore never observe an idle pane.
pane_tail() {
  herdr pane read "$1" 2>/dev/null \
    | sed -e 's/\x1b\[[0-9;?]*[a-zA-Z]//g' | grep -av '^[[:space:]]*$' \
    | tail -n "${2:-3}"
}

# BUSY = the status bar says a turn is in flight, or the pane is parked on a modal.
# A modal is a stalled run, not a finished one, so it must never read as idle.
#
# The ask_user modal's footer is "↑↓ navigate · 1-9 jump · Enter select · Esc cancel"
# — note "Esc cancel", not "Esc to cancel". Matching only the latter made a stalled
# run look finished, which is exactly the failure this watcher exists to catch.
pane_busy() {
  pane_tail "$1" 3 | grep -qE "Esc to? cancel|agent running|Max steps|Continue or stop|Permission requested|navigate|Enter select"
}

snapshot() {
  echo "===== $(date +%H:%M:%S) ====="
  docker ps --filter "name=^pf-" --format '  {{.Names}}  {{.Status}}'
  local i n
  for i in $(seq 1 "$RUNS"); do
    n=$(find "${RUNS_ROOT}/run$i/findings" -name '*.md' 2>/dev/null | wc -l)
    echo "  run$i: $n finding(s)"
    find "${RUNS_ROOT}/run$i/findings" -name '*.md' 2>/dev/null | sort | sed 's|.*/|    - |'
  done
  local p
  for p in ${PANES[@]+"${PANES[@]}"}; do
    echo "  --- $p ---"
    pane_tail "$p" 3 | sed 's/^/    /'
  done
}

while :; do
  snapshot >>"$LOG" 2>&1

  # With no panes to sample, a run is "active" precisely while its container lives.
  active=0
  for p in ${PANES[@]+"${PANES[@]}"}; do pane_busy "$p" && active=$((active + 1)); done
  if [ "${#PANES[@]}" -eq 0 ]; then
    running=$(docker ps -q --filter "name=^pf-" | wc -l)
    [ "$running" -gt 0 ] && active=$running
  fi

  if [ "$active" -eq 0 ]; then
    idle_streak=$((idle_streak + 1))
    [ "$idle_streak" -ge 3 ] && { echo "ALL IDLE $(date +%H:%M:%S)" >>"$LOG"; break; }
  else
    idle_streak=0
  fi

  if [ "$(date +%s)" -gt "$deadline" ]; then
    echo "WATCH BUDGET EXHAUSTED after ${BUDGET_MIN}m $(date +%H:%M:%S)" >>"$LOG"; break
  fi

  sleep 90
done

echo "watcher done; log=$LOG"
grep -c "^=====" "$LOG" 2>/dev/null | sed 's/^/samples: /'
