import { defineConfig, devices } from "@playwright/test"

// The real stack, with no mock layer (brief D1); one worker against one server (spec S4).
export default defineConfig({
  testDir: "./e2e-real",
  globalSetup: "./e2e-real/global-setup.ts",
  fullyParallel: false,
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
