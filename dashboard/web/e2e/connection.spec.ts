import { expect, test } from "@playwright/test"
import { isPhone, noHorizontalScroll, openApp } from "./helpers.js"

declare global {
  interface Window {
    __starMock?: { events: { drop(): void; restore(): void } }
  }
}
test("shows the banner when the stream drops and reconnects within 5 seconds", async ({
  page,
}) => {
  await openApp(page)
  await page.locator("h1, h2").first().waitFor()
  await page.evaluate(() => window.__starMock?.events.drop())
  await expect(
    page.getByText("Lost the connection to the dashboard server")
  ).toBeVisible()
  await page.evaluate(() => window.__starMock?.events.restore())
  await expect(
    page.getByText("Lost the connection to the dashboard server")
  ).toBeHidden({ timeout: 5500 })
  await noHorizontalScroll(page)
})

test("a page opened without the token asks for it, and the pasted line opens the dashboard", async ({
  page,
}) => {
  await page.goto("/sphere-app/needs")
  const field = page.getByLabel("Dashboard token")
  await expect(field).toBeVisible()
  await expect(field).toHaveCSS("font-size", isPhone(page) ? "16px" : "14px")
  await expect(
    page.getByText(
      "On your Mac, run /juel:star dashboard. It prints a link that ends in ?t= and the token."
    )
  ).toBeVisible()
  await field.fill("STAR dashboard: http://127.0.0.1:4767/?t=test-token")
  await page.getByRole("button", { name: "Use this token" }).click()
  await expect(page.getByRole("heading", { name: "Needs you" })).toBeVisible()
  await expect(field).toBeHidden()
  expect(await page.evaluate(() => localStorage.getItem("star-token"))).toBe(
    "test-token"
  )
  await noHorizontalScroll(page)
})
test("coming back to the page after the stream dropped reconnects without the 5 second wait", async ({
  page,
}) => {
  await openApp(page)
  await page.locator("h1, h2").first().waitFor()
  await page.evaluate(() => window.__starMock?.events.drop())
  const lost = page.getByText("Lost the connection to the dashboard server")
  await expect(lost).toBeVisible()
  await page.evaluate(() => window.__starMock?.events.restore())
  await page.evaluate(() =>
    document.dispatchEvent(new Event("visibilitychange"))
  )
  await expect(lost).toBeHidden({ timeout: 2_000 })
})
