import { expect, test } from "@playwright/test"
import { noHorizontalScroll, openApp } from "./helpers"
test("opens an image, a video and a text file full size", async ({ page }) => {
  await openApp(page, "/sphere-app/evidence?item=SPH-4")
  const detail = page.getByRole("region", { name: "Evidence detail" })
  await detail.getByRole("button", { name: "Open filters-in-url.png" }).click()
  let dialog = page.getByRole("dialog", { name: "filters-in-url.png" })
  await expect(
    dialog.getByRole("img", { name: "filters-in-url.png" })
  ).toBeVisible()
  await page.keyboard.press("Escape")
  await detail.getByRole("button", { name: "Open clear-all.webm" }).click()
  dialog = page.getByRole("dialog", { name: "clear-all.webm" })
  await expect(dialog.getByLabel("clear-all.webm")).toBeVisible()
  await page.keyboard.press("Escape")
  await detail
    .getByRole("button", { name: "Open reports-filters.spec.txt" })
    .click()
  dialog = page.getByRole("dialog", { name: "reports-filters.spec.txt" })
  await expect(dialog.locator("pre")).toContainText("6 passed")
  await noHorizontalScroll(page)
})
