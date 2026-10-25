#!/bin/sh
# Reads a plan's tasks marked **Run:** session and, with --ledger, checks the executor's ledger (#158).
#   session-tasks.sh <plan> [--ledger <file>]
# One line per task whose first non-blank line under its "### Task <N>" heading is **Run:** session,
# in plan order:
#   session <N>
# With --ledger, then, unless the ledger is another plan's (foreign, below), which proves nothing about
# this one and prints no ran, until or next line:
#   ran <N>      a session task the ledger marks "Task <N>: complete" without "(session": the
#                executor ran it, so the run failed
#   until <N>    the first session task the ledger does not mark complete: the dispatch stops before it
#   next <N>     the first task of any kind, in plan order, with no "Task <N>: complete" line: where the
#                executor resumes (#196, #203)
#   next none    in its place, when every task is complete
#   foreign <p>  alone after the session lines, when the ledger's first line ("# SDD ledger — plan: <p>") names a plan
#                file whose name differs from this plan's: the ledger is another plan's
# A ledger that does not exist yet is empty. Without --ledger, a plan with no session task prints nothing.
# Exit: 0; 1 when any "ran" line or a "foreign" line was printed; 64 usage or a plan that cannot be read.
exec python3 - "$@" <<'PY'
import os, re, sys

args = sys.argv[1:]
plan = None
ledger = None
i = 0
while i < len(args):
    if args[i] == '--ledger':
        if i + 1 >= len(args):
            sys.exit(64)
        ledger = args[i + 1]
        i += 2
    elif plan is None and not args[i].startswith('--'):
        plan = args[i]
        i += 1
    else:
        sys.exit(64)
if plan is None:
    print('usage: session-tasks.sh <plan> [--ledger <file>]', file=sys.stderr)
    sys.exit(64)
try:
    with open(plan, encoding='utf-8') as f:
        lines = f.read().split('\n')
except OSError as e:
    print(f'session-tasks.sh: cannot read {plan}: {e}', file=sys.stderr)
    sys.exit(64)

heading = re.compile(r'^#{2,4}\s+Task\s+(\d+)\b')
session = []
tasks = []
pending = None
for line in lines:
    m = heading.match(line)
    if m:
        pending = m.group(1)
        if pending not in tasks:
            tasks.append(pending)
        continue
    if pending is not None and line.strip():
        if line.strip().startswith('**Run:** session'):
            session.append(pending)
        pending = None
for n in session:
    print(f'session {n}')

if ledger is None:
    sys.exit(0)
done = {}
named = None
try:
    with open(ledger, encoding='utf-8') as f:
        for k, line in enumerate(f):
            if k == 0:
                h = re.match(r'^# SDD ledger\s+\S+\s+plan:\s*(.+?)\s*$', line)
                named = h.group(1) if h else None
            m = re.match(r'^Task (\d+): complete\b(.*)', line.rstrip('\n'))
            if m:
                done[m.group(1)] = m.group(2).startswith(' (session')
except OSError:
    pass
foreign = named is not None and os.path.basename(named) != os.path.basename(plan)
if foreign:
    print(f'foreign {named}')
    sys.exit(1)
ran = [n for n in session if n in done and not done[n]]
for n in ran:
    print(f'ran {n}')
for n in session:
    if n not in done:
        print(f'until {n}')
        break
left = [n for n in tasks if n not in done]
print(f'next {left[0]}' if left else 'next none')
sys.exit(1 if ran else 0)
PY
