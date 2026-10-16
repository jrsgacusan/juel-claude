import { expect, test } from "@playwright/test"
import { noHorizontalScroll, openApp, MOD } from "./helpers.js"
test("⌘K from Needs you: grouped, highlighted, arrows and Enter", async ({
  page,
}) => {
  await openApp(page)
  // The shortcut listener lives in the app shell: wait until the shell is on screen.
  await expect(page.getByRole("button", { name: "Search (⌘K)" })).toBeVisible()
  await page.keyboard.press(`${MOD}+k`)
  const input = page.getByPlaceholder(
    "Search items, decisions, Slack, briefings and evidence"
  )
  await input.fill("csv")
  const dialog = page.getByRole("dialog")
  for (const group of [
    "Items",
    "Needs you",
    "Decisions",
    "Slack",
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
  await expect(page).toHaveURL(/\/sphere-app\/needs\?loop=N-41$/)
  await noHorizontalScroll(page)
})
test("Ctrl+K from Progress with Every project on", async ({ page }) => {
  await openApp(page, "/sphere-app/progress")
  // The shortcut listener lives in the app shell: wait until the shell is on screen.
  await expect(page.getByRole("button", { name: "Search (⌘K)" })).toBeVisible()
  await page.keyboard.press("Control+k")
  await page
    .getByPlaceholder("Search items, decisions, Slack, briefings and evidence")
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
      "Search items, decisions, Slack, briefings and evidence"
    )
  ).toBeVisible()
  await noHorizontalScroll(page)
})
