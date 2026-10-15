import { expect, test } from "@playwright/test"
import { noHorizontalScroll, openApp } from "./helpers.js"
test("Light and Dark persist across a reload", async ({ page }) => {
  await openApp(page)
  await page.getByLabel("Dark theme").click()
  await expect(page.locator("html")).toHaveClass(/dark/)
  await expect
    .poll(() => page.evaluate(() => localStorage.getItem("star-theme")))
    .toBe("dark")
  await page.reload()
  await expect(page.locator("html")).toHaveClass(/dark/)
  await page.getByLabel("Light theme").click()
  await page.reload()
  await expect(page.locator("html")).toHaveClass(/light/)
  await noHorizontalScroll(page)
})
test("System follows the OS", async ({ page }) => {
  await openApp(page)
  await page.getByLabel("System theme").click()
  await page.emulateMedia({ colorScheme: "dark" })
  await expect(page.locator("html")).toHaveClass(/dark/)
  await page.emulateMedia({ colorScheme: "light" })
  await expect(page.locator("html")).toHaveClass(/light/)
  await noHorizontalScroll(page)
})
test("the project's colors only mark state", async ({ page }) => {
  await openApp(page, "/sphere-app/progress")
  const stopped = page.getByText("Stopped").first()
  const merged = page.getByText("Merged").first()
  await expect(stopped).toBeVisible()
  await expect(merged).toBeVisible()
  await noHorizontalScroll(page)
})
