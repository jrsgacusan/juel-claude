import { expect, test } from "@playwright/test"
import { noHorizontalScroll, openApp, type Scenario } from "./helpers"
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
      ).toBeVisible()
      if (scenario === "error")
        await expect(page.getByTestId("page-error")).toContainText(
          "Couldn't load"
        )
      await noHorizontalScroll(page)
    })
