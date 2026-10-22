import { expect, test } from "@playwright/test"
import { isPhone, noHorizontalScroll, openApp, MOD } from "./helpers.js"
test("⌘K from Needs you: grouped, highlighted, arrows and Enter", async ({
  page,
}) => {
  await openApp(page)
  // The shortcut listener lives in the app shell: wait until the shell is on screen.
  await expect(page.getByRole("button", { name: "Search (⌘K)" })).toBeVisible()
  await page.keyboard.press(`${MOD}+k`)
  const input = page.getByPlaceholder(
    "Search items, decisions, briefings and evidence"
  )
  await input.fill("csv")
  const dialog = page.getByRole("dialog")
  for (const group of [
    "Items",
    "Needs you",
    "Decisions",
    "Briefings",
    "Evidence",
  ])
    await expect(
      dialog.locator("[cmdk-group-heading]").filter({ hasText: group })
    ).toBeVisible()
  await expect.poll(() => page.locator("mark").count()).toBeGreaterThan(3)
  await expect(dialog.getByRole("option").first()).toHaveAttribute(
    "aria-selected",
    "true"
  )
  await page.keyboard.press("ArrowDown")
  await page.keyboard.press("Enter")
  await expect(page).toHaveURL(/\/needs\?project=sphere-app&loop=N-41$/)
  await noHorizontalScroll(page)
})
test("Ctrl+K from Progress with Every project on", async ({ page }) => {
  await openApp(page, "/sphere-app/progress")
  // The shortcut listener lives in the app shell: wait until the shell is on screen.
  await expect(page.getByRole("button", { name: "Search (⌘K)" })).toBeVisible()
  await page.keyboard.press("Control+k")
  await page
    .getByPlaceholder("Search items, decisions, briefings and evidence")
    .fill("csv")
  await page.getByRole("switch", { name: "Search every project" }).click()
  const dialog = page.getByRole("dialog")
  await dialog.getByText("juel-claude, building").click()
  await expect(page).toHaveURL(
    /\/juel-claude\/progress\?item=star-dashboard-web$/
  )
  await noHorizontalScroll(page)
})
test("the search button opens it too", async ({ page }) => {
  await openApp(page)
  await page.getByRole("button", { name: "Search (⌘K)" }).click()
  await expect(
    page.getByPlaceholder(
      "Search items, decisions, briefings and evidence"
    )
  ).toBeVisible()
  await noHorizontalScroll(page)
})

test("on a phone the switch sits above the results and nothing hides under the keyboard", async ({
  page,
}) => {
  test.skip(!isPhone(page), "the phone layout")
  await openApp(page)
  await page.getByRole("button", { name: "Search (⌘K)" }).click()
  const input = page.getByPlaceholder(
    "Search items, decisions, briefings and evidence"
  )
  await expect(input).toHaveCSS("font-size", "16px")
  await input.fill("csv")
  const dialog = page.getByRole("dialog")
  const first = dialog.getByRole("option").first()
  await expect(first).toBeVisible()
  const height = page.viewportSize()?.height ?? 844
  const toggle = await dialog
    .getByRole("switch", { name: "Search every project" })
    .boundingBox()
  const option = await first.boundingBox()
  const list = await dialog.locator("[cmdk-list]").boundingBox()
  expect(toggle && option && toggle.y < option.y).toBe(true)
  expect((toggle?.y ?? height) + (toggle?.height ?? 0)).toBeLessThan(height / 2)
  expect((list?.y ?? height) + (list?.height ?? 0)).toBeLessThanOrEqual(
    height * 0.6
  )
  if (await page.evaluate(() => matchMedia("(pointer: coarse)").matches))
    await expect(dialog.getByText("Move")).toBeHidden()
  await noHorizontalScroll(page)
})
