import { expect, test } from "@playwright/test"
import { isPhone, noHorizontalScroll, openApp } from "./helpers.js"
test("opens a row's step log and goes to Needs you", async ({ page }) => {
  await openApp(page, "/sphere-app/progress")
  await page.getByRole("tab", { name: /^Blocked/ }).click()
  await page.getByText("Remove the old export modal").click()
  const dialog = page.getByRole("dialog")
  await expect(dialog).toContainText(".worktrees/sphere-app/sph-9")
  await expect(dialog).toContainText("#213")
  await expect(dialog).toContainText(
    "Asked: widen the scope to the public API?"
  )
  await dialog.getByRole("link", { name: "Answer in Needs you" }).click()
  await expect(page).toHaveURL(/\/needs\?project=sphere-app&loop=N-43$/)
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
  // The Merged today list sits under the table, so the rows are looked up inside the table or the cards.
  const rows = isPhone(page)
    ? page.getByRole("list", { name: "Items" })
    : page.getByRole("table")
  await expect(rows.getByText("Export reports as CSV")).toBeVisible()
  await expect(rows.getByText("Fix invoice rounding")).toHaveCount(0)
  await page.getByRole("tab", { name: /^All/ }).click()
  const pages = page.getByRole("navigation", { name: "Item pages" })
  await expect(pages).toContainText("Page 1 of 2")
  await expect(rows.getByText("Reports page filters")).toHaveCount(0)
  await pages.getByRole("button", { name: "Next page" }).click()
  await expect(pages).toContainText("Page 2 of 2")
  await expect(rows.getByText("Reports page filters")).toBeVisible()
  await noHorizontalScroll(page)
})

test("shows one summary line, and Merged today under the table", async ({
  page,
}) => {
  await openApp(page, "/sphere-app/progress")
  await expect(page.getByRole("img", { name: "3 of 3 busy" })).toBeVisible()
  await expect(page.getByText("3 of 3 build slots busy.")).toBeVisible()
  await expect(page.getByText("1 in review, 2 merged today.")).toBeVisible()
  await expect(page.getByRole("region", { name: "Summary" })).toHaveCount(0)
  const merged = page.getByRole("list", { name: "Merged today" })
  await expect(merged.getByRole("listitem")).toHaveCount(2)
  await expect(merged).toContainText("Fix invoice rounding")
  await page.getByRole("tab", { name: /^Merged/ }).click()
  await expect(merged).toHaveCount(0)
})

test("a phone gets cards, a bottom sheet and tabs that scroll", async ({
  page,
}) => {
  test.skip(!isPhone(page), "phone layout only")
  await openApp(page, "/sphere-app/progress")
  await expect(page.getByRole("table")).toHaveCount(0)
  const cards = page.getByRole("list", { name: "Items" }).getByRole("listitem")
  await expect(cards).toHaveCount(6)
  const overflow = await page
    .getByRole("tablist")
    .locator("..")
    .evaluate((el) => getComputedStyle(el).overflowX)
  expect(overflow).toBe("auto")
  await page
    .getByRole("button", { name: /^SPH-11 Export reports as CSV$/ })
    .click()
  const dialog = page.getByRole("dialog")
  await expect(dialog).toContainText(".worktrees/sphere-app/sph-11")
  await expect(dialog).toHaveAttribute("data-side", "bottom")
  await noHorizontalScroll(page)
})
