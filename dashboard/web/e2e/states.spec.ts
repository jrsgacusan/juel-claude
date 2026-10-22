import { expect, test } from "@playwright/test"
import type { Locator } from "@playwright/test"
import {
  isPhone,
  noHorizontalScroll,
  openApp,
  type Scenario,
} from "./helpers.js"
for (const pageName of [
  "needs",
  "progress",
  "slack",
  "briefing",
  "evidence",
] as const)
  for (const scenario of ["loading", "empty", "error"] as const)
    test(`${pageName} ${scenario}`, async ({ page }) => {
      // A project's Needs page redirects to the combined one; go there directly, as the redirect can win the race with goInApp's wait.
      const path =
        pageName === "needs" ? "/needs?project=sphere-app" : `/sphere-app/${pageName}`
      await openApp(page, path, scenario as Scenario)
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
            "When STAR waits on one of your steps, a draft or a Slack reply, it shows here.",
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

test("on a touch screen the shell's controls are at least 44 px", async ({
  page,
}) => {
  test.skip(!isPhone(page), "touch sizes apply on the phone projects")
  await openApp(page, "/sphere-app/progress?item=SPH-11")
  test.skip(
    !(await page.evaluate(() => matchMedia("(pointer: coarse)").matches)),
    "this browser reports no coarse pointer"
  )
  const atLeast44 = async (locator: Locator, both = true) => {
    const box = await locator.boundingBox()
    expect(box?.height ?? 0).toBeGreaterThanOrEqual(44)
    if (both) expect(box?.width ?? 0).toBeGreaterThanOrEqual(44)
  }
  await atLeast44(
    page.getByRole("dialog").getByRole("button", { name: "Close" })
  )
  await page.keyboard.press("Escape")
  await atLeast44(page.getByRole("tab").first(), false)
  await atLeast44(page.getByRole("button", { name: "Switch project, now sphere-app" }), false)
  await atLeast44(page.getByRole("button", { name: "Search (⌘K)" }))
  const bar = page.getByRole("navigation", { name: "Pages" })
  for (const link of await bar.getByRole("link").all()) await atLeast44(link, false)
  await bar.getByRole("link", { name: "More" }).click()
  await expect(page.getByRole("navigation", { name: "Projects" })).toContainText("sphere-api")
  await atLeast44(
    page.getByRole("navigation", { name: "Projects" }).getByRole("link").first(),
    false
  )
})
