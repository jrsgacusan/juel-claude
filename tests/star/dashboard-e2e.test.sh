#!/bin/sh
# The real-stack suite (brief D2), run from the repo root so the tests/*/*.test.sh loop runs it.
# It needs node 24, network for the first npm ci and Chromium download, and dashboard.sh's 3 GB to build.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT/dashboard/web" || exit 1
if [ ! -d node_modules ]; then
  npm ci || { echo "FAIL npm ci in dashboard/web"; exit 1; }
fi
npx playwright install chromium || { echo "FAIL npx playwright install chromium"; exit 1; }
if npm run e2e:real; then
  echo "all passed"
else
  echo "FAIL npm run e2e:real"
  exit 1
fi
