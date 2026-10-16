# STAR dashboard web app

The page the dashboard server serves (`dashboard/server/`). Vite, React, TypeScript, Tailwind CSS v4
and shadcn/ui; data through TanStack Query from the server's API, typed in `src/api/types.ts`.

    npm ci
    npm run dev          # http://localhost:5173/?t=dev, with the MSW mock layer (src/mocks/)
    npm test             # Vitest + Testing Library
    npm run lint
    npm run typecheck
    npx playwright install chromium
    npm run e2e          # Playwright against the mock layer, desktop and 390 px, light and dark
    npm run e2e:real     # Playwright against the real stack: dashboard.sh, the server and the built app (e2e-real/)
    npm run build        # tsc -b, vite build, then a check that no mock code reached dist/

Against a running dashboard server: run `VITE_MOCK=off npm run dev`, adding
`STAR_DASHBOARD_PORT=<port>` when the port in `~/.juel/dashboard.json` is not 4767, and open
`/?t=<the token in that file>`. Without `VITE_MOCK=off` the mock layer answers instead
(`src/main.tsx:15`, `vite.config.ts:17-20`).

`npm run e2e:real` (and `sh tests/star/dashboard-e2e.test.sh` from the repo root, which the
regression gate runs) copies `e2e-real/fixture/star` into a temp folder, runs
`skills/star/dashboard.sh` with a temp `HOME` and fake `orca`, `claude`, `gh` and `open` first on
`PATH`, and never reads your `~/.juel`; `STAR_E2E_KEEP=1` keeps the temp folder.

Mock scenarios for a dev session: set `localStorage['star-mock']` to `empty`, `error`, `loading`,
`conflict`, `stopped` or `slack-off` and reload.
