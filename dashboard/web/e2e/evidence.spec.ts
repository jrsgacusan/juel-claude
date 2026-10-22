import { expect, test } from "@playwright/test"
import { isPhone, noHorizontalScroll, openApp } from "./helpers.js"
test("opens an image, a video and a text file full size", async ({ page }) => {
  const webm: string[] = []
  page.on("request", (r) => {
    if (r.url().includes("clear-all.webm")) webm.push(r.url())
  })
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
  expect(webm).toEqual([])
  await detail.getByRole("button", { name: "Open clear-all.webm" }).click()
  dialog = page.getByRole("dialog", { name: "clear-all.webm" })
  const video = dialog.getByLabel("clear-all.webm")
  await expect(video).toHaveAttribute("playsinline", "")
  expect(webm.length).toBeGreaterThan(0)
  await expect
    .poll(() => video.evaluate((v: HTMLVideoElement) => v.readyState))
    .toBeGreaterThan(0)
  await expect
    .poll(() => video.evaluate((v: HTMLVideoElement) => v.duration))
    .toBeGreaterThan(1)
  await page.keyboard.press("Escape")
  await detail.getByRole("switch", { name: "Show files" }).click()
  await detail
    .getByRole("button", { name: "Open reports-filters.spec.txt" })
    .click()
  dialog = page.getByRole("dialog", { name: "reports-filters.spec.txt" })
  await expect(dialog.locator("pre")).toContainText("6 passed")
  await expect(dialog.locator("pre")).toHaveCSS("font-family", /ui-monospace|SFMono-Regular|Menlo/)
  await noHorizontalScroll(page)
})
test("pages the merged items and a big file grid, and keeps the page on a phone", async ({
  page,
}) => {
  await openApp(page, "/sphere-api/evidence")
  const list = page.getByRole("region", { name: "Merged items" })
  const pages = list.getByRole("navigation", { name: "Evidence pages" })
  await expect(pages).toContainText("Page 1 of 3")
  await pages.getByRole("button", { name: "Next page" }).click()
  await pages.getByRole("button", { name: "Next page" }).click()
  await expect(pages).toContainText("Page 3 of 3")
  await list.getByRole("button", { name: /^API-2\b/ }).click()
  const detail = page.getByRole("region", { name: "Evidence detail" })
  await expect(
    detail.getByRole("heading", { name: "Rate limit change 2" })
  ).toBeVisible()
  if (isPhone(page)) {
    await expect(list).toBeHidden()
    await detail.getByRole("button", { name: "Back to Evidence" }).click()
    await expect(list).toBeVisible()
    await expect(pages).toContainText("Page 3 of 3")
  }
  await pages.getByRole("button", { name: "Previous page" }).click()
  await pages.getByRole("button", { name: "Previous page" }).click()
  await list.getByRole("button", { name: /^API-25\b/ }).click()
  const files = detail.getByRole("navigation", { name: "Pages of files" })
  await expect(files).toContainText("Page 1 of 3")
  await files.getByRole("button", { name: "Next page" }).click()
  await expect(
    detail.getByRole("button", { name: "Open shot-13.png" })
  ).toBeVisible()
  await noHorizontalScroll(page)
})
