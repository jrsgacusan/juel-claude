#!/bin/sh
# Runs one command while holding the machine-wide heavy-gate lock, so unattended workers never
# run full test suites or builds at the same time.
#
# Usage: sh gate-lock.sh [--holder <label>] [--wait-max <seconds>] -- <command> [args...]
#
# Run it with the Bash tool's run_in_background: true and wait for the completion notification
# (like codex exec): waiting for the lock plus running the gate can take longer than the tool's
# 600 s foreground cap.
#
# The lock is a directory, <git-common-dir>/juel/gate.lock (JUEL_GATE_LOCK overrides it); mkdir
# is atomic. The holder file is "<label> <wrapper pid> <command process group> <token>". The
# command runs in its own process group, so the lock stays held while any process of that group
# lives, even if this wrapper is SIGKILLed, and a TERM, INT or HUP to the wrapper stops the whole
# group. A lock is stale when neither the wrapper nor the group is alive; a lock directory whose
# holder file is missing, empty or unreadable (an interrupted acquisition) is stale once older
# than JUEL_GATE_LOCK_INCOMPLETE_SECONDS (default 60). Stale locks are reclaimed by an atomic
# rename, so only one waiter wins. A wrapper removes the lock only while it still owns it.
#
# Exit status: the command's own; 75 when the lock stayed busy for --wait-max seconds
# (default 3600); 64 on bad usage; 1 outside a git repo without JUEL_GATE_LOCK.
set -u

holder=gate
wait_max=3600
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
  gcd=$(git rev-parse --git-common-dir 2>/dev/null) || { echo "gate-lock.sh: not in a git repo" >&2; exit 1; }
  common=$(cd "$gcd" && pwd -P) || exit 1
  lock="$common/juel/gate.lock"
fi
mkdir -p "$(dirname "$lock")" || exit 1
poll=${JUEL_GATE_LOCK_POLL:-30}
incomplete=${JUEL_GATE_LOCK_INCOMPLETE_SECONDS:-60}
token="$$.$(date +%s).${RANDOM:-0}"

mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }

stale() {
  line=$(cat "$lock/holder" 2>/dev/null)
  wpid=$(printf '%s\n' "$line" | awk '{print $2}')
  pgid=$(printf '%s\n' "$line" | awk '{print $3}')
  case "$wpid" in
    ''|*[!0-9]*) [ $(( $(date +%s) - $(mtime "$lock") )) -ge "$incomplete" ]; return ;;
  esac
  kill -0 "$wpid" 2>/dev/null && return 1
  case "$pgid" in ''|*[!0-9]*) return 0 ;; esac
  ! kill -0 -"$pgid" 2>/dev/null
}

# sleep for the smaller of the poll interval and what is left of the wait budget
nap() {
  left=$(( wait_max - ($(date +%s) - start) ))
  [ "$left" -le 0 ] && return 1
  awk -v p="$poll" -v l="$left" 'BEGIN { if (p + 0 < l + 0) print p; else print l }' | { read -r s; sleep "$s"; }
}

start=$(date +%s)
while ! mkdir "$lock" 2>/dev/null; do
  if [ -d "$lock" ] && stale; then
    if mv "$lock" "$lock.stale.$$" 2>/dev/null; then
      echo "gate-lock.sh: reclaimed stale lock ($(cat "$lock.stale.$$/holder" 2>/dev/null || echo 'no holder'))" >&2
      rm -rf "$lock.stale.$$"
    fi
    continue
  fi
  if ! nap; then
    echo "gate-lock.sh: busy, held by $(cat "$lock/holder" 2>/dev/null || echo 'an unfinished acquisition')" >&2
    exit 75
  fi
done

owned() { [ "$(awk '{print $4}' "$lock/holder" 2>/dev/null)" = "$token" ]; }
release() { owned && rm -rf "$lock"; }

child=
stop() {
  [ -n "$child" ] && kill -TERM -"$child" 2>/dev/null
  release
  exit "$1"
}
trap 'release' EXIT
trap 'stop 143' TERM
trap 'stop 130' INT
trap 'stop 129' HUP

# Its own process group: job control makes the background job a group leader (pgid = its pid).
printf '%s %s %s %s\n' "$holder" "$$" "$$" "$token" > "$lock/holder"
set -m
"$@" &
child=$!
set +m
printf '%s %s %s %s\n' "$holder" "$$" "$child" "$token" > "$lock/holder"
wait "$child"
rc=$?
# the group may still hold children of the command; wait for them before releasing
while kill -0 -"$child" 2>/dev/null; do sleep 1; done
exit "$rc"
