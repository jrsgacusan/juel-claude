import { expect, test } from "@playwright/test"
import { noHorizontalScroll, openApp } from "./helpers.js"

// The project's color scheme (light or dark) comes from the Playwright project, so this runs in both.
test("the stage rail colors only mark state", async ({ page }) => {
  await openApp(page, "/sphere-app/progress")
  const segment = (tone: string) =>
    page.locator(`[data-slot="stage-segment"][data-tone="${tone}"]`).first()
  const color = (tone: string) =>
    segment(tone).evaluate((el) => getComputedStyle(el).backgroundColor)

  // Running: the items at work show a run segment.
  const run = await color("run")
  await page.getByRole("tab", { name: /^Blocked/ }).click()
  // Blocked: a stopped (red) or waiting (amber) segment.
  const blocked = page.locator(
    '[data-slot="stage-segment"][data-tone="stop"], [data-slot="stage-segment"][data-tone="wait"]'
  )
  await expect(blocked.first()).toBeVisible()
  const stopOrWait = await blocked
    .first()
    .evaluate((el) => getComputedStyle(el).backgroundColor)
  expect(stopOrWait).not.toBe(run)

  // Merged: every merged row has five done segments.
  await page.getByRole("tab", { name: /^Merged/ }).click()
  const rails = page.getByRole("img", { name: "Merged" })
  await expect(rails.first()).toBeVisible()
  for (const rail of await rails.all())
    await expect(
      rail.locator('[data-slot="stage-segment"][data-state="done"]')
    ).toHaveCount(5)
  await noHorizontalScroll(page)
})
