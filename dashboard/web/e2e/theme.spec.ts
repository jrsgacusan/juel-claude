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
  // System is the default; pick Dark first so choosing System is a change that gets stored.
  await page.getByLabel("Dark theme").click()
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
  // Progress opens on Running: the stopped item lives under Needs you, the merged ones under Merged.
  const badgeColor = (variant: string) =>
    page
      .locator(`[data-slot="badge"][data-variant="${variant}"]`)
      .first()
      .evaluate((el) => getComputedStyle(el).backgroundColor)
  await page.getByRole("tab", { name: /^Needs you/ }).click()
  await expect(page.getByText("Stopped", { exact: true }).first()).toBeVisible()
  const stopped = await badgeColor("stop")
  await page.getByRole("tab", { name: /^Merged/ }).click()
  await expect(page.getByText("Merged", { exact: true }).first()).toBeVisible()
  const done = await badgeColor("done")
  const body = await page.evaluate(
    () => getComputedStyle(document.body).backgroundColor
  )
  const colors = { body, stopped, done }
  expect(colors.stopped).not.toBe(colors.done)
  expect(colors.stopped).not.toBe(colors.body)
  expect(colors.done).not.toBe(colors.body)
  // A neutral color has no chroma: rgb(n, n, n), or oklch(L 0 H) as Chromium reports it.
  expect(colors.body).toMatch(
    /^rgb\((\d+), \1, \1\)$|^oklch\([\d.]+ 0(?: [\d.]+| none)?\)$/
  )
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
