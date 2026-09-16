#!/usr/bin/env bash
# Sample a set of pf runs every INTERVAL seconds.
# Writes a persistent timeline to $LOG and echoes each snapshot to stdout.
#
#   RUNS="1 2" INTERVAL=300 ./pf-monitor.sh
#
# Environment:
#   LOG           timeline file        (default ./pf-monitor.log)
#   INTERVAL      seconds between samples (default 300)
#   RUNS          run indices to count findings for (default "1 2")
#   PF_RUNS_ROOT  where run workdirs live (default ~/pf-runs)
set -uo pipefail

LOG="${LOG:-./pf-monitor.log}"
INTERVAL="${INTERVAL:-300}"
RUNS="${RUNS:-1 2}"
RUNS_ROOT="${PF_RUNS_ROOT:-$HOME/pf-runs}"

snapshot() {
  echo "===== $(date '+%F %T %Z') ====="
  docker ps --filter 'name=^pf-' --format '  {{.Names}}  {{.Status}}' 2>/dev/null || true
  local r d n
  for r in $RUNS; do
    d="${RUNS_ROOT}/run$r/findings"
    n=$(find "$d" -name '*.md' 2>/dev/null | wc -l)
    echo "  run$r: $n finding(s)"
    find "$d" -name '*.md' 2>/dev/null | sort | sed 's|.*/|    - |'
  done
}

while :; do
  s="$(snapshot)"
  printf '%s\n' "$s" >>"$LOG"
  printf '%s\n' "$s"
  sleep "$INTERVAL"
done
