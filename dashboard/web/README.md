# STAR dashboard web app

The page the dashboard server serves (`dashboard/server/`). Vite, React, TypeScript, Tailwind CSS v4
and shadcn/ui; data through TanStack Query from the server's API, typed in `src/api/types.ts`.

    npm ci
    npm run dev          # http://localhost:5173/?t=dev, with the MSW mock layer (src/mocks/)
    VITE_MOCK=off npm run dev   # against a running dashboard server (STAR_DASHBOARD_PORT, default 4767)
    npm test             # Vitest + Testing Library
    npm run e2e          # Playwright against the mock layer, desktop and 390 px, light and dark
    npm run build        # tsc -b, vite build, then a check that no mock code reached dist/

Mock scenarios for a dev session: set `localStorage['star-mock']` to `empty`, `error`, `loading`,
`conflict`, `stopped` or `slack-off` and reload.
