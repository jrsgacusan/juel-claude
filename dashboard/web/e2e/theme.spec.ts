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
  await page.reload()
  await expect
    .poll(() => page.evaluate(() => localStorage.getItem("star-theme")))
    .toBe("system")
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
  const colors = await page.evaluate(() => {
    const body = getComputedStyle(document.body).backgroundColor
    const stopped = getComputedStyle(
      document.querySelector('[data-variant="stop"]') as Element
    ).backgroundColor
    const done = getComputedStyle(
      document.querySelector('[data-variant="done"]') as Element
    ).backgroundColor
    return { body, stopped, done }
  })
  expect(colors.stopped).not.toBe(colors.done)
  expect(colors.stopped).not.toBe(colors.body)
  expect(colors.done).not.toBe(colors.body)
  expect(colors.body).toMatch(/^rgb\((\d+), \1, \1\)$/)
  await noHorizontalScroll(page)
})
test("the selected theme stands out", async ({ page }) => {
  await openApp(page)
  await page.getByLabel("Dark theme").click()
  // The pointer rests on the item just clicked; move it away so hover does not color it.
  await page.mouse.move(0, 0)
  const background = (label: string) =>
    page
      .getByLabel(label)
      .evaluate((element) => getComputedStyle(element).backgroundColor)
  const light = await background("Light theme")
  await expect.poll(() => background("Dark theme")).not.toBe(light)
  await noHorizontalScroll(page)
})
