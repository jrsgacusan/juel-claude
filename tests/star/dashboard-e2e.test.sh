#!/bin/sh
# The STAR dashboard's real-stack suite (dashboard/web/e2e-real): dashboard.sh under a temp HOME builds dashboard/web when it is stale and starts the server, and Playwright drives every page with fake orca, claude, gh and open.
# It lives under tests/ so the gate's tests/*/*.test.sh loop runs it. The first run needs network (npm ci, the Chromium download).
# Below dashboard.sh's free-memory minimum a stale dist/ is not rebuilt, and the suite fails rather than test the old build.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT/dashboard/web" || { echo "FAIL cd dashboard/web"; exit 1; }
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
