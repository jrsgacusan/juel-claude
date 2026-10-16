import { expect, test } from "@playwright/test"
import { noHorizontalScroll, openApp } from "./helpers.js"
test("opens an image, a video and a text file full size", async ({ page }) => {
  await openApp(page, "/sphere-app/evidence?item=SPH-4")
  const detail = page.getByRole("region", { name: "Evidence detail" })
  await detail.getByRole("button", { name: "Open filters-in-url.png" }).click()
  let dialog = page.getByRole("dialog", { name: "filters-in-url.png" })
  await expect
    .poll(() =>
      dialog
        .getByRole("img", { name: "filters-in-url.png" })
        .evaluate((img: HTMLImageElement) => img.naturalWidth)
    )
    .toBeGreaterThan(0)
  await page.keyboard.press("Escape")
  await detail.getByRole("button", { name: "Open clear-all.webm" }).click()
  dialog = page.getByRole("dialog", { name: "clear-all.webm" })
  const video = dialog.getByLabel("clear-all.webm")
  await expect
    .poll(() => video.evaluate((v: HTMLVideoElement) => v.readyState))
    .toBeGreaterThan(0)
  await expect
    .poll(() => video.evaluate((v: HTMLVideoElement) => v.duration))
    .toBeGreaterThan(1)
  await page.keyboard.press("Escape")
  await detail
    .getByRole("button", { name: "Open reports-filters.spec.txt" })
    .click()
  dialog = page.getByRole("dialog", { name: "reports-filters.spec.txt" })
  await expect(dialog.locator("pre")).toContainText("6 passed")
  await expect(dialog.locator("pre")).toHaveCSS("font-family", /Geist Mono/)
  await noHorizontalScroll(page)
})
