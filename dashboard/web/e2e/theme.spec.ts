import { expect, type Page, test } from "@playwright/test"
import { isPhone, noHorizontalScroll, openApp, openNav } from "./helpers.js"
/** Picks a theme the way this device offers it: the header menu on a desktop, the radios on More on a phone. */
async function chooseTheme(page: Page, name: "System" | "Light" | "Dark") {
  if (isPhone(page)) {
    if (!/\/more$/.test(new URL(page.url()).pathname)) await openNav(page)
    await page.getByRole("radio", { name: `${name} theme` }).click()
  } else {
    await page.getByRole("button", { name: /^Theme:/ }).click()
    await page.getByRole("menuitemradio", { name }).click()
  }
}
test("Light and Dark persist across a reload", async ({ page }) => {
  await openApp(page)
  await chooseTheme(page, "Dark")
  await expect(page.locator("html")).toHaveClass(/dark/)
  await expect
    .poll(() => page.evaluate(() => localStorage.getItem("star-theme")))
    .toBe("dark")
  await page.reload()
  await expect(page.locator("html")).toHaveClass(/dark/)
  await chooseTheme(page, "Light")
  await page.reload()
  await expect(page.locator("html")).toHaveClass(/light/)
  await noHorizontalScroll(page)
})
test("System follows the OS", async ({ page }) => {
  await openApp(page)
  // System is the default; pick Dark first so choosing System is a change that gets stored.
  await chooseTheme(page, "Dark")
  await chooseTheme(page, "System")
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
test("the page background carries no chroma", async ({ page }) => {
  await openApp(page, "/sphere-app/progress")
  const body = await page.evaluate(
    () => getComputedStyle(document.body).backgroundColor
  )
  // A neutral color has no chroma: rgb(n, n, n), or oklch(L 0 H) as Chromium reports it.
  expect(body).toMatch(
    /^rgb\((\d+), \1, \1\)$|^oklch\([\d.]+ 0(?: [\d.]+| none)?\)$/
  )
  await noHorizontalScroll(page)
})
test("the selected theme stands out", async ({ page }) => {
  await openApp(page)
  await chooseTheme(page, "Dark")
  if (isPhone(page)) {
    // The pointer rests on the item just clicked; move it away so hover does not color it.
    await page.mouse.move(0, 0)
    const background = (label: string) =>
      page
        .getByLabel(label)
        .evaluate((element) => getComputedStyle(element).backgroundColor)
    const light = await background("Light theme")
    await expect.poll(() => background("Dark theme")).not.toBe(light)
  } else {
    await page.getByRole("button", { name: "Theme: Dark" }).click()
    await expect(page.getByRole("menuitemradio", { name: "Dark" })).toHaveAttribute("aria-checked", "true")
    await expect(page.getByRole("menuitemradio", { name: "Light" })).toHaveAttribute("aria-checked", "false")
  }
  await noHorizontalScroll(page)
})
