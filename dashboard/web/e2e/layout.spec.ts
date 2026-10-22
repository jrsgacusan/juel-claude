import { expect, test } from "@playwright/test"
import { goInApp, isPhone, noHorizontalScroll, openApp, openNav } from "./helpers.js"
test("every page fits the width", async ({ page }) => {
  await openApp(page)
  for (const path of [
    "/needs",
    "/sphere-app/progress?item=SPH-11",
    "/sphere-app/briefing",
    "/sphere-app/evidence?item=SPH-4",
    "/sphere-app/accounts",
    "/sphere-app/more",
    "/needs?project=juel-claude",
    "/needs?loop=sphere-app%2FN-41",
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
  if (isPhone(page)) {
    await page.getByRole("button", { name: "Switch project, now sphere-app" }).click()
    const sheet = page.getByRole("dialog")
    await expect(sheet).toContainText("All projects")
    await expect(sheet).toContainText("sphere-api")
    await expect(sheet).toContainText("Stopped")
    await sheet.getByRole("link", { name: /sphere-api/ }).click()
  } else {
    const list = page.getByRole("list", { name: "Projects" })
    await expect(list).toContainText("sphere-app")
    await expect(list).toContainText("sphere-api")
    await expect(list).toContainText("Idle")
    await expect(list).toContainText("juel-claude")
    await expect(list).toContainText("Stopped")
    await list.getByText("sphere-api").click()
  }
  await expect(page).toHaveURL(/\/sphere-api\/progress$/)
  await noHorizontalScroll(page)
})
test("More lists the projects with their state", async ({ page }) => {
  test.skip(!isPhone(page), "More is the phone's project list")
  await openApp(page, "/sphere-app/progress")
  await openNav(page)
  const list = page.getByRole("navigation", { name: "Projects" })
  await expect(list).toContainText("sphere-app")
  await expect(list).toContainText("Running")
  await expect(list).toContainText("Idle")
  await expect(list).toContainText("Stopped")
  await list.getByText("sphere-api").click()
  await expect(page).toHaveURL(/\/sphere-api\/more$/)
  await noHorizontalScroll(page)
})
test("makes no request outside its own origin", async ({ page, baseURL }) => {
  const urls: string[] = []
  page.on("request", (r) => urls.push(r.url()))
  await openApp(page)
  for (const path of [
    "/needs",
    "/sphere-app/progress",
    "/sphere-app/briefing",
    "/sphere-app/evidence",
    "/sphere-app/accounts",
    "/sphere-app/more",
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
test("on a desktop the header shows the breadcrumb, the ⌘K hint and the theme button", async ({
  page,
}) => {
  test.skip(isPhone(page), "the desktop header")
  await openApp(page)
  const crumbs = page.getByRole("navigation", { name: "breadcrumb" })
  await expect(crumbs).toContainText("sphere-app")
  await expect(crumbs).toContainText("Progress")
  await expect(page.getByRole("button", { name: "Search (⌘K)" })).toBeVisible()
  await expect(page.getByRole("button", { name: "Theme: System" })).toBeVisible()
  await noHorizontalScroll(page)
})

test("on a phone the header has the switcher and Search, no breadcrumb, menu button or theme control", async ({
  page,
}) => {
  test.skip(!isPhone(page), "the phone header")
  await openApp(page)
  const switcher = page.getByRole("button", { name: "Switch project, now sphere-app" })
  await expect(switcher).toContainText("STAR running")
  await expect(page.getByRole("button", { name: "Search (⌘K)" })).toBeVisible()
  await expect(page.getByRole("navigation", { name: "breadcrumb" })).toHaveCount(0)
  await expect(page.getByRole("button", { name: "Open the menu" })).toHaveCount(0)
  await expect(page.getByRole("button", { name: /^Theme/ })).toHaveCount(0)
  await noHorizontalScroll(page)
})

test("on a desktop the sidebar lists Chat between Progress and Briefing, and keeps the last project's pages on Needs you", async ({
  page,
}) => {
  test.skip(isPhone(page), "the phone has the tab bar instead")
  await openApp(page)
  const sections = page.getByRole("list", { name: "Sections" })
  await expect(sections.getByRole("link"))
    .toHaveText(["Progress", "Chat", "Briefing", "Evidence"])
  await goInApp(page, "/needs")
  await expect(page.getByRole("heading", { name: "sphere-app" })).toBeVisible()
  await expect(sections.getByRole("link")).toHaveCount(4)
  await sections.getByRole("link", { name: "Chat", exact: true }).click()
  await expect(page).toHaveURL(/\/sphere-app\/chat$/)
})

test("on a phone the tab bar shows on Needs you and hides on a detail", async ({ page }) => {
  test.skip(!isPhone(page), "the phone tab bar")
  await openApp(page, "/needs")
  const bar = page.getByRole("navigation", { name: "Pages" })
  await expect(bar.getByRole("link")).toHaveText([/Needs you/, "Progress", "Chat", "More"])
  await expect(bar.getByRole("link", { name: /Needs you/ })).toHaveAttribute("aria-current", "page")
  await noHorizontalScroll(page)
})

// Needs lane H: ListDetail calls setDetailOpen (I-10); the bar stays until that lane is merged.
test("on a phone the tab bar hides while Needs you shows a detail", async ({ page }) => {
  test.skip(!isPhone(page), "the phone tab bar")
  await openApp(page, "/needs")
  const bar = page.getByRole("navigation", { name: "Pages" })
  await goInApp(page, "/needs?loop=sphere-app%2FN-41")
  await expect(bar).toBeHidden()
  await goInApp(page, "/needs")
  await expect(bar).toBeVisible()
  await noHorizontalScroll(page)
})

test("on a phone Chat's composer sits above the tab bar", async ({ page }) => {
  test.skip(!isPhone(page), "the phone tab bar")
  await openApp(page, "/sphere-app/chat")
  const bar = await page.getByRole("navigation", { name: "Pages" }).boundingBox()
  const composer = await page.getByLabel("Message STAR").boundingBox()
  expect(bar).not.toBeNull()
  expect(composer).not.toBeNull()
  expect((composer?.y ?? 0) + (composer?.height ?? 0)).toBeLessThanOrEqual(bar?.y ?? 0)
  await noHorizontalScroll(page)
})

test("the Workers card shows a square per slot, and away waits for STAR", async ({ page }) => {
  await openApp(page)
  await openNav(page)
  await expect(page.getByText("5 busy")).toBeVisible()
  await expect(page.getByText("1 of 4", { exact: true })).toBeVisible()
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
  await expect(page.getByRole("button", { name: "Switch project, now sphere-app" })).toBeInViewport()
  await noHorizontalScroll(page)
})
