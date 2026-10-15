import { expect, test } from "@playwright/test"
import { isPhone, noHorizontalScroll, openApp, openNav } from "./helpers.js"
test("every page fits the width", async ({ page }) => {
  await openApp(page)
  for (const path of [
    "/sphere-app/needs",
    "/sphere-app/progress?item=SPH-11",
    "/sphere-app/slack",
    "/sphere-app/briefing",
    "/sphere-app/evidence?item=SPH-4",
    "/juel-claude/needs",
  ]) {
    await page.goto(path)
    await expect(page.locator("h1, h2").first()).toBeVisible()
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
    "/sphere-app/needs",
    "/sphere-app/progress",
    "/sphere-app/slack",
    "/sphere-app/briefing",
    "/sphere-app/evidence",
  ])
    await page.goto(path)
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
  ).toContainText("Needs you")
  await expect(page.getByRole("button", { name: "Search (⌘K)" })).toBeVisible()
  await expect(page.getByLabel("System theme")).toBeVisible()
  if (isPhone(page))
    await expect(
      page.getByRole("button", { name: "Open the menu" })
    ).toBeVisible()
  await noHorizontalScroll(page)
})
