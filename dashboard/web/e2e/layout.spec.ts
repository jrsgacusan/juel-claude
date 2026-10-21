import { expect, test } from "@playwright/test"
import { goInApp, isPhone, noHorizontalScroll, openApp, openNav } from "./helpers.js"
test("every page fits the width", async ({ page }) => {
  await openApp(page)
  for (const path of [
    "/needs",
    "/sphere-app/progress?item=SPH-11",
    "/sphere-app/slack",
    "/sphere-app/briefing",
    "/sphere-app/evidence?item=SPH-4",
    "/sphere-app/accounts",
    "/needs?project=juel-claude",
  ]) {
    await goInApp(page, path)
    if (isPhone(page) && path.endsWith("/briefing")) {
      // On a phone Briefing swaps its Chat and Draft panes behind tabs and shows no heading, to keep the height.
      await expect(page.getByRole("tab", { name: "Chat", exact: true })).toBeVisible()
      await expect(page.getByRole("tab", { name: "Draft", exact: true })).toBeVisible()
    } else {
      // A detail on a phone hides the list's heading, so the check wants a heading that is shown.
      await expect(page.locator("h1:visible, h2:visible").first()).toBeVisible()
    }
    await noHorizontalScroll(page)
  }
})
test("the project switcher lists every project with its state", async ({
  page,
}) => {
  await openApp(page, "/sphere-app/progress")
  await openNav(page)
  const list = page.getByRole("list", { name: "Projects" })
  await expect(list).toContainText("sphere-app")
  await expect(list).toContainText("Running")
  await expect(list).toContainText("sphere-api")
  await expect(list).toContainText("Idle")
  await expect(list).toContainText("juel-claude")
  await expect(list).toContainText("Stopped")
  await list.getByText("sphere-api").click()
  await expect(page).toHaveURL(/\/sphere-api\/progress$/)
  await noHorizontalScroll(page)
})
test("makes no request outside its own origin", async ({ page, baseURL }) => {
  const urls: string[] = []
  page.on("request", (r) => urls.push(r.url()))
  await openApp(page)
  for (const path of [
    "/needs",
    "/sphere-app/progress",
    "/sphere-app/slack",
    "/sphere-app/briefing",
    "/sphere-app/evidence",
    "/sphere-app/accounts",
  ])
    await goInApp(page, path)
  const offOrigin = urls.filter(
    (url) =>
      !url.startsWith(baseURL ?? "") &&
      !url.startsWith("blob:") &&
      !url.startsWith("data:")
  )
  expect(offOrigin).toEqual([])
  await noHorizontalScroll(page)
})
test("the header shows the breadcrumb, the ⌘K hint and the theme switch", async ({
  page,
}) => {
  await openApp(page)
  await expect(
    page.getByRole("navigation", { name: "breadcrumb" })
  ).toContainText("sphere-app")
  await expect(
    page.getByRole("navigation", { name: "breadcrumb" })
  ).toContainText("Progress")
  await expect(page.getByRole("button", { name: "Search (⌘K)" })).toBeVisible()
  await expect(page.getByLabel("System theme")).toBeVisible()
  if (isPhone(page))
    await expect(
      page.getByRole("button", { name: "Open the menu" })
    ).toBeVisible()
  await noHorizontalScroll(page)
})

test("the sidebar lists Chat between Progress and Slack replies", async ({ page }) => {
  await openApp(page)
  await openNav(page)
  const sections = page.getByRole("list", { name: "Sections" })
  await expect(sections.getByRole("link"))
    .toHaveText(["Progress", "Chat", "Slack replies", "Briefing", "Evidence"])
  await sections.getByRole("link", { name: "Chat", exact: true }).click()
  await expect(page).toHaveURL(/\/sphere-app\/chat$/)
})

test("the Workers card shows a square per slot, and away waits for STAR", async ({ page }) => {
  await openApp(page)
  await openNav(page)
  await expect(page.getByText("5 busy")).toBeVisible()
  await expect(page.getByRole("meter", { name: "Building" })).toHaveAttribute("aria-valuetext", "3 of 3 busy")
  await expect(page.getByText("Next tick in 3 min")).toHaveCount(0)
  const away = page.getByRole("switch", { name: "Away" })
  await expect(away).toHaveAttribute("aria-checked", "false")
  if (isPhone(page)) {
    const row = await page.locator("[data-slot=away-row]").boundingBox()
    expect(row?.height ?? 0).toBeGreaterThanOrEqual(44)
  }
  await away.click()
  await expect(page.getByText("Waiting for STAR to mark you away")).toBeVisible()
  await expect(page.getByText("STAR running · you're away")).toBeVisible({ timeout: 10_000 })
  await expect(away).toHaveAttribute("aria-checked", "true")
  await noHorizontalScroll(page)
})

test("on a phone the header stays on screen while the page scrolls", async ({ page }) => {
  test.skip(!isPhone(page), "the header is sticky below md only")
  await openApp(page, "/sphere-app/progress")
  // Scroll only once the items have loaded: while the page shows its loading state it is shorter than the screen.
  await expect(page.getByRole("tab", { name: /^Running/ })).toBeVisible()
  await expect
    .poll(() => page.evaluate(() => document.documentElement.scrollHeight > window.innerHeight))
    .toBe(true)
  await page.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight))
  await expect.poll(() => page.evaluate(() => window.scrollY)).toBeGreaterThan(0)
  await expect(page.getByRole("button", { name: "Search (⌘K)" })).toBeInViewport()
  const header = await page.locator("header").first().boundingBox()
  expect(header?.y ?? 99).toBeLessThanOrEqual(1)
  await expect(page.getByRole("navigation", { name: "breadcrumb" })).toContainText("Progress")
  await noHorizontalScroll(page)
})
