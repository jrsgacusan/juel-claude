#!/bin/sh
# The STAR dashboard server's own suite (node --test over dashboard/server, feature modules
# included), run from the repo root so the usual `for t in tests/*/*.test.sh` loop runs it too.
# Node 24 reads `node --test <folder>` as a file, so the folder is given as a glob.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT" || exit 1
if node --test 'dashboard/server/**/*.test.ts'; then
  echo "all passed"
else
  echo "FAIL node --test 'dashboard/server/**/*.test.ts'"
  exit 1
fi
