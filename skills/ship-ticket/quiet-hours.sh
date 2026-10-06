#!/bin/sh
# Says whether this moment is inside a quiet window, so no skill does time-zone arithmetic by hand.
#   quiet-hours.sh <window>      ->   inside | outside
# <window> is HH:MM-HH:MM@<IANA time zone> (22:00-07:00@Asia/Manila; it may cross midnight; the
# start minute is inside, the end minute is outside), or the word "always" (the user is away:
# every moment is inside).
# Exit 0 with the answer; 64 with a reason on stderr for a window that cannot be read (bad times,
# an unknown time zone, equal start and end: say "always" for a window that never ends).
# QUIET_NOW (ISO UTC) overrides the clock, for tests.
exec python3 - "$@" <<'PY'
import os
import re
import sys
from datetime import datetime, timezone
from zoneinfo import ZoneInfo


def bad(msg):
    print(f"quiet-hours.sh: {msg}", file=sys.stderr)
    sys.exit(64)


if len(sys.argv) != 2:
    bad("usage: quiet-hours.sh <HH:MM-HH:MM@tz | always>")
window = sys.argv[1].strip()
if window.lower() == "always":
    print("inside")
    sys.exit(0)
m = re.fullmatch(r"(\d{1,2}):(\d\d)-(\d{1,2}):(\d\d)@(\S+)", window)
if not m:
    bad(f"cannot read the window {window!r}; expected HH:MM-HH:MM@tz or always")
h1, m1, h2, m2 = (int(m.group(i)) for i in range(1, 5))
if h1 > 23 or h2 > 23 or m1 > 59 or m2 > 59:
    bad(f"no such time of day in {window!r}")
start, end = h1 * 60 + m1, h2 * 60 + m2
if start == end:
    bad("start and end are the same; say 'always' for a window that never ends")
try:
    tz = ZoneInfo(m.group(5))
except Exception:
    bad(f"unknown time zone {m.group(5)!r}")
try:
    now = (datetime.fromisoformat(os.environ["QUIET_NOW"].replace("Z", "+00:00"))
           if os.environ.get("QUIET_NOW") else datetime.now(timezone.utc))
except ValueError:
    bad("QUIET_NOW is not an ISO time")
local = (now if now.tzinfo else now.replace(tzinfo=timezone.utc)).astimezone(tz)
minute = local.hour * 60 + local.minute
inside = start <= minute < end if start < end else (minute >= start or minute < end)
print("inside" if inside else "outside")
PY
sh tests/ship-ticket/quiet-hours.test.sh | grep -v '^ok'