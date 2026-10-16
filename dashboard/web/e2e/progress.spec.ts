import { expect, test } from "@playwright/test"
import { isPhone, noHorizontalScroll, openApp } from "./helpers.js"
test("opens a row's step log and goes to Needs you", async ({ page }) => {
  await openApp(page, "/sphere-app/progress")
  await page.getByRole("tab", { name: /^Needs you/ }).click()
  await page.getByText("Remove the old export modal").click()
  const dialog = page.getByRole("dialog")
  await expect(dialog).toContainText(".worktrees/sphere-app/sph-9")
  await expect(dialog).toContainText("#213")
  await expect(dialog).toContainText(
    "Asked: widen the scope to the public API?"
  )
  await dialog.getByRole("link", { name: "Answer in Needs you" }).click()
  await expect(page).toHaveURL(/\/sphere-app\/needs\?loop=N-43$/)
  await expect(
    page.getByRole("heading", {
      name: "Removing the old export needs a public API change. Widen the scope?",
    })
  ).toBeVisible()
  await noHorizontalScroll(page)
})
test("goes from a merged item to its evidence", async ({ page }) => {
  await openApp(page, "/sphere-app/progress")
  await page.getByRole("tab", { name: /^Merged/ }).click()
  await page.getByText("Fix invoice rounding").click()
  await page
    .getByRole("dialog")
    .getByRole("link", { name: /Evidence/ })
    .click()
  await expect(page).toHaveURL(/\/sphere-app\/evidence\?item=SPH-8$/)
  await expect(
    page.getByRole("heading", { name: "Fix invoice rounding" })
  ).toBeVisible()
  await noHorizontalScroll(page)
})

test("opens on Running and pages All ten rows at a time", async ({ page }) => {
  await openApp(page, "/sphere-app/progress")
  await expect(page.getByRole("tab", { name: /^Running/ })).toHaveAttribute(
    "aria-selected",
    "true"
  )
  await expect(page.getByText("Export reports as CSV")).toBeVisible()
  await expect(page.getByText("Fix invoice rounding")).toHaveCount(0)
  await page.getByRole("tab", { name: /^All/ }).click()
  const pages = page.getByRole("navigation", { name: "Item pages" })
  await expect(pages).toContainText("Page 1 of 2")
  await expect(page.getByText("Reports page filters")).toHaveCount(0)
  await pages.getByRole("button", { name: "Next page" }).click()
  await expect(pages).toContainText("Page 2 of 2")
  await expect(page.getByText("Reports page filters")).toBeVisible()
  await noHorizontalScroll(page)
})

test("a phone gets cards, two-column stats and tabs that scroll", async ({
  page,
}) => {
  test.skip(!isPhone(page), "phone layout only")
  await openApp(page, "/sphere-app/progress")
  await expect(page.getByRole("table")).toHaveCount(0)
  const cards = page.getByRole("list", { name: "Items" }).getByRole("listitem")
  await expect(cards).toHaveCount(6)
  const columns = await page
    .getByRole("region", { name: "Summary" })
    .evaluate(
      (el) => getComputedStyle(el).gridTemplateColumns.split(" ").length
    )
  expect(columns).toBe(2)
  const overflow = await page
    .getByRole("tablist")
    .locator("..")
    .evaluate((el) => getComputedStyle(el).overflowX)
  expect(overflow).toBe("auto")
  await page
    .getByRole("button", { name: /^SPH-11 Export reports as CSV$/ })
    .click()
  await expect(page.getByRole("dialog")).toContainText(
    ".worktrees/sphere-app/sph-11"
  )
  await noHorizontalScroll(page)
})
