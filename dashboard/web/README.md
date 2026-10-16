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
    npm run build        # tsc -b, vite build, then a check that no mock code reached dist/

Against a running dashboard server: set `STAR_DASHBOARD_PORT` to the port in
`~/.juel/dashboard.json` when it is not 4767, and open `/?t=<the token in that file>`.

Mock scenarios for a dev session: set `localStorage['star-mock']` to `empty`, `error`, `loading`,
`conflict`, `stopped` or `slack-off` and reload.
