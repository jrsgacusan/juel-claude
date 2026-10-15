import { expect, test } from "@playwright/test"
import { noHorizontalScroll, openApp } from "./helpers"
test("opens a row's step log and goes to Needs you", async ({ page }) => {
  await openApp(page, "/sphere-app/progress")
  await page.getByText("Remove the old export modal").click()
  const dialog = page.getByRole("dialog")
  await expect(dialog).toContainText("feat/sph-9-remove-export-modal")
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
