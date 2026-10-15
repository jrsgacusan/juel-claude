import { expect, test } from "@playwright/test"
import { noHorizontalScroll, openApp } from "./helpers"

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
  ).toBeHidden({ timeout: 6000 })
  await noHorizontalScroll(page)
})
