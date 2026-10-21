import { expect, openApp, test } from "./helpers.js"

test("items are named by their ledger name, with a tracker ref only beside it", async ({
  page,
}) => {
  await openApp(page, "/sample/progress")
  await page.getByRole("tab", { name: /^All\s*4$/ }).click()
  await expect(
    page.getByRole("button", {
      name: /^invoice-export Export invoices as CSV$/,
    })
  ).toBeVisible()
  await expect(
    page.getByRole("button", {
      name: /^seat-pause · SPH-7 Pause a member's seat$/,
    })
  ).toBeVisible()
  await expect(
    page
      .getByRole("button", { name: /^seat-pause · SPH-7 / })
      .getByText("seat-pause · SPH-7", { exact: true })
  ).toBeVisible()
  await expect(
    page.getByRole("button", { name: /^csv-import Import customers from CSV$/ })
  ).toBeVisible()
  await expect(
    page.getByRole("button", {
      name: /^audit-log · AUD-3 Keep an audit log of admin actions$/,
    })
  ).toBeVisible()
  await expect(page.getByText(/\/Users\/owner\/star\/items/)).toHaveCount(0)
})

test("a row opens its step log", async ({ page }) => {
  await openApp(page, "/sample/progress")
  await page.getByRole("tab", { name: /^All\s*4$/ }).click()
  await page
    .getByRole("button", { name: /^invoice-export Export invoices as CSV$/ })
    .click()
  const sheet = page.getByRole("dialog")
  await expect(
    sheet.getByRole("heading", { name: "Export invoices as CSV" })
  ).toBeVisible()
  await expect(sheet.getByText("invoice-export", { exact: true })).toBeVisible()
  await expect(sheet.getByText("reading the brief")).toBeVisible()
  await expect(sheet.getByText("running the plan")).toBeVisible()
  await expect(
    sheet.getByText("invoices page renders the export button")
  ).toBeVisible()
  await expect(
    sheet.getByText(
      "A CSV of the month's invoices downloads from the invoices page."
    )
  ).toBeVisible()
  await expect(sheet.getByText(/\/Users\/owner\/star\/items/)).toHaveCount(0)
  await expect(page).toHaveURL(/\/sample\/progress\?item=invoice-export$/)
})

test("Progress opens on Running", async ({ page }) => {
  await openApp(page, "/sample/progress")
  // Earlier specs on this shared stack move items between states, so the spec checks the tab, not
  // which item happens to be running: Running is selected and lists exactly as many rows as its badge.
  const running = page.getByRole("tab", { name: /^Running\s*\d+$/ })
  await expect(running).toHaveAttribute("aria-selected", "true")
  const count = Number((await running.textContent())?.match(/\d+/)?.[0] ?? "0")
  // with nothing running the table holds only its empty state and its one button
  if (count === 0)
    await expect(page.getByRole("button", { name: "Show all items" })).toBeVisible()
  else await expect(page.getByRole("table").getByRole("button")).toHaveCount(count)
  await expect(
    page.getByRole("button", { name: /^invoice-export / })
  ).toHaveCount(0)
  await expect(
    page.getByRole("navigation", { name: "Item pages" })
  ).toHaveCount(0)
  await page.getByRole("tab", { name: /^All\s*4$/ }).click()
  await expect(
    page.getByRole("button", {
      name: /^invoice-export Export invoices as CSV$/,
    })
  ).toBeVisible()
})
