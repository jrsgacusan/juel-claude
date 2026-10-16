import { defineConfig, devices } from "@playwright/test"

// The STAR dashboard's real stack with no mock layer (integration brief D1): global-setup.ts runs skills/star/dashboard.sh under a temp HOME and every spec drives the built web app. One worker: the specs share one server and one STAR folder, and some write to it. The 15 s expect timeout outlasts the server's 5 s file-poll fallback, which the live specs may wait on.
export default defineConfig({
  testDir: "./e2e-real",
  globalSetup: "./e2e-real/global-setup.ts",
  forbidOnly: true,
  workers: 1,
  retries: 0,
  timeout: 60_000,
  expect: { timeout: 15_000 },
  reporter: [["list"]],
  use: { trace: "retain-on-failure" },
  projects: [
    {
      name: "chromium",
      use: {
        ...devices["Desktop Chrome"],
        viewport: { width: 1280, height: 800 },
        colorScheme: "light",
      },
    },
  ],
})
