import { expect, test } from "@playwright/test"
import { noHorizontalScroll, openApp, type Scenario } from "./helpers.js"
for (const pageName of [
  "needs",
  "progress",
  "slack",
  "briefing",
  "evidence",
] as const)
  for (const scenario of ["loading", "empty", "error"] as const)
    test(`${pageName} ${scenario}`, async ({ page }) => {
      await openApp(page, `/sphere-app/${pageName}`, scenario as Scenario)
      await expect(
        page.getByTestId(
          scenario === "loading"
            ? "page-loading"
            : scenario === "empty"
              ? "page-empty"
              : "page-error"
        )
      ).toBeVisible({ timeout: scenario === "error" ? 10_000 : 5_000 })
      if (scenario === "empty") {
        const body = {
          needs:
            "When STAR waits on an answer, a go or one of your steps, it shows here.",
          progress:
            "Items show here once STAR takes work: type /juel:star <brief> in the project.",
          slack:
            "When someone asks you something on Slack, the watcher brings it here with a drafted reply.",
          briefing:
            "Start one to shape a piece of work with the briefing agent; it ends in a ticket STAR picks up.",
          evidence:
            "After STAR merges an item, its screenshots, recordings and test output show here.",
        } as const
        await expect(page.getByTestId("page-empty")).toContainText(
          body[pageName]
        )
      }
      if (scenario === "error")
        await expect(page.getByTestId("page-error")).toContainText(
          "Couldn't load"
        )
      await noHorizontalScroll(page)
    })
