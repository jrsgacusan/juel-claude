import { expect, openApp, test } from "./helpers.js"

test("a merged item's files show, and an image and a text file open", async ({ page }) => {
  await openApp(page, "/sample/evidence")
  await page.getByRole("button", { name: /seat-pause.*Pause a member's seat.*3 files/ }).click()
  const detail = page.getByRole("region", { name: "Evidence detail" })
  await expect(detail.getByRole("heading", { name: "Pause a member's seat" })).toBeVisible()
  for (const text of ["go for seat-pause and csv-import", "2, last SAFE", "all passed", "Ria"]) {
    await expect(detail.getByText(text, { exact: true })).toBeVisible()
  }
  await expect(detail.getByRole("link", { name: "PR #41" })).toBeVisible()
  await detail.getByRole("button", { name: "Open 2026-10-16-pause-a-seat/screenshots/seat-paused.png" }).click()
  const image = page.getByRole("dialog")
  await expect
    .poll(() => image.locator("img").evaluate((i: HTMLImageElement) => i.naturalWidth))
    .toBe(64)
  await page.keyboard.press("Escape")
  await detail.getByRole("button", { name: "Open 2026-10-16-pause-a-seat/notes.txt" }).click()
  await expect(page.getByRole("dialog")).toHaveText(/Paused seats keep read-only access\./)
})
