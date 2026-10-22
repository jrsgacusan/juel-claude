# STAR dashboard web app

The page the dashboard server serves (`dashboard/server/`). Vite, React, TypeScript, Tailwind CSS v4
and shadcn/ui; data through TanStack Query from the server's API, typed in `src/api/types.ts`.

## On your iPhone's home screen

Open the tailnet link in Safari, tap Share, then Add to Home Screen. The STAR icon appears and opens
the dashboard full screen, signed in: the page links `/manifest.webmanifest?t=<token>` (`src/lib/manifest-link.ts`),
and the server answers it with a `start_url` that carries the token, because a home-screen app keeps
its own storage, separate from Safari's.

The icons are in `app-public/icons/`: `star.svg` is the source (the favicon's four-point star, light
on `#171717`), rendered to `star-180.png`, `star-192.png`, `star-512.png` and `star-512-maskable.png`
(the star at 50% of the side, so a circle mask keeps it) by loading the SVG at each size in
Playwright's Chromium and screenshotting the square. Only `app-public/` reaches `dist/` (see
`publicDir` in `vite.config.ts`); the dev server serves no icons.

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
(`enableMocking` in `src/main.tsx`, and the `server.proxy` block in `vite.config.ts`).

`npm run e2e:real` (and `sh tests/star/dashboard-e2e.test.sh` from the repo root, which the
regression gate runs) copies `e2e-real/fixture/star` into a temp folder, runs
`skills/star/dashboard.sh` with a temp `HOME` and fake `orca`, `claude`, `gh` and `open` first on
`PATH`, and never reads your `~/.juel`. A stale `dist/` is rebuilt by the suite's own launcher run
(`npm ci`, then `npm run build`), and with too little free memory the suite fails instead of
testing the old build. The temp folder is `$TMPDIR/star-e2e-*`, kept with `STAR_E2E_KEEP=1`; a
failed launch names it.

Mock scenarios for a dev session: set `localStorage['star-mock']` to `empty`, `error`, `loading`,
`conflict` or `stopped` and reload.
