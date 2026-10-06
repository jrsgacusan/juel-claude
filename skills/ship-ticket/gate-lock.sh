#!/bin/sh
# Runs one command while holding the machine-wide heavy-gate lock, so unattended workers never
# run full test suites or builds at the same time.
#
# Usage: sh gate-lock.sh [--holder <label>] [--wait-max <seconds>] -- <command> [args...]
#
# The lock is a directory, <git-common-dir>/juel/gate.lock (JUEL_GATE_LOCK overrides it);
# mkdir is atomic. The holder file records this script's own pid, which lives exactly as long
# as the command, so a holder whose pid is gone is stale and is reclaimed at once. A lock
# directory with no holder file (an acquisition interrupted before it wrote one) is reclaimed
# once it is older than JUEL_GATE_LOCK_INCOMPLETE_SECONDS (default 60).
#
# Exit status: the command's own, or 75 when the lock stayed busy for --wait-max seconds
# (default 540, under the Bash tool's 600 s cap); the caller retries.
set -u

holder=gate
wait_max=540
while [ $# -gt 0 ]; do
  case "$1" in
    --holder) holder=$2; shift 2 ;;
    --wait-max) wait_max=$2; shift 2 ;;
    --) shift; break ;;
    *) echo "gate-lock.sh: unknown argument: $1" >&2; exit 64 ;;
  esac
done
[ $# -gt 0 ] || { echo "gate-lock.sh: no command given after --" >&2; exit 64; }

if [ -n "${JUEL_GATE_LOCK:-}" ]; then
  lock=$JUEL_GATE_LOCK
else
  common=$(cd "$(git rev-parse --git-common-dir)" && pwd -P) || exit 1
  lock="$common/juel/gate.lock"
fi
mkdir -p "$(dirname "$lock")"
poll=${JUEL_GATE_LOCK_POLL:-30}
incomplete=${JUEL_GATE_LOCK_INCOMPLETE_SECONDS:-60}

mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }

stale() {
  if [ -f "$lock/holder" ]; then
    pid=$(awk '{print $2}' "$lock/holder" 2>/dev/null)
    [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null
  else
    [ $(( $(date +%s) - $(mtime "$lock") )) -ge "$incomplete" ]
  fi
}

start=$(date +%s)
while ! mkdir "$lock" 2>/dev/null; do
  if [ -d "$lock" ] && stale; then
    echo "gate-lock.sh: reclaiming stale lock ($(cat "$lock/holder" 2>/dev/null || echo 'no holder'))" >&2
    rm -rf "$lock"
    continue
  fi
  if [ $(( $(date +%s) - start )) -ge "$wait_max" ]; then
    echo "gate-lock.sh: busy, held by $(cat "$lock/holder" 2>/dev/null || echo 'an unfinished acquisition')" >&2
    exit 75
  fi
  sleep "$poll"
done

printf '%s %s %s\n' "$holder" "$$" "$(date +%s)" > "$lock/holder"
# The command runs as a child we wait on, so a TERM or INT to this script is handled at once:
# stop the child, release the lock, exit.
child=
trap 'rm -rf "$lock"' EXIT
trap '[ -n "$child" ] && kill "$child" 2>/dev/null; exit 143' TERM
trap '[ -n "$child" ] && kill "$child" 2>/dev/null; exit 130' INT
"$@" &
child=$!
wait "$child"
