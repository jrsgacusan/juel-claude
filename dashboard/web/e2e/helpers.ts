import { expect, type Page } from "@playwright/test"

export type Scenario =
  | "default"
  | "empty"
  | "error"
  | "loading"
  | "conflict"
  | "stopped"
  | "slack-off"

/** Opens the app the way the launcher does (/?t=<token>), then goes to `path`. */
export async function openApp(
  page: Page,
  path = "/sphere-app/needs",
  scenario: Scenario = "default"
) {
  await page.addInitScript((s) => {
    try {
      if (s === "default") localStorage.removeItem("star-mock")
      else localStorage.setItem("star-mock", s)
    } catch {
      // storage blocked: the default scenario runs
    }
  }, scenario)
  await page.goto("/?t=test-token")
  await expect(page).toHaveURL(/\/sphere-app\/needs$/)
  if (path !== "/sphere-app/needs") await page.goto(path)
}

export const isPhone = (page: Page) =>
  (page.viewportSize()?.width ?? 1280) < 768

export async function noHorizontalScroll(page: Page) {
  const [scrollWidth, innerWidth] = await page.evaluate(() => [
    document.documentElement.scrollWidth,
    window.innerWidth,
  ])
  expect(scrollWidth, "the page scrolls sideways").toBeLessThanOrEqual(
    innerWidth
  )
}

/** On a phone the sidebar is a sheet behind the menu button. */
export async function openNav(page: Page) {
  if (isPhone(page))
    await page.getByRole("button", { name: "Open the menu" }).click()
}

export const MOD = process.platform === "darwin" ? "Meta" : "Control"
