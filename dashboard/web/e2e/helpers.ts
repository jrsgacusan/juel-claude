import { expect, type Page } from "@playwright/test"

export type Scenario =
  | "default"
  | "empty"
  | "error"
  | "loading"
  | "conflict"
  | "stopped"
  | "slack-off"

/** Sets the mock scenario before load, opens /?t=test-token like the launcher, checks the redirect to /sphere-app/needs, then moves to `path` inside the app (goInApp). */
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
  if (path !== "/sphere-app/needs") await goInApp(page, path)
}

/**
 * Moves to `path` inside the app, the way a link does, without loading a new document.
 * React Router's browser router follows popstate. A full page.goto can hang in development:
 * MSW's worker sends the navigation request to the page being left, and waits for an answer
 * that never comes once that page has unloaded.
 */
export async function goInApp(page: Page, path: string) {
  await page.evaluate((to) => {
    window.history.pushState(null, "", to)
    window.dispatchEvent(new PopStateEvent("popstate", { state: null }))
  }, path)
  await expect
    .poll(() => {
      const url = new URL(page.url())
      return url.pathname + url.search
    })
    .toBe(path)
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
