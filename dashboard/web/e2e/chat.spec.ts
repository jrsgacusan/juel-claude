import { expect, test, type Page } from "@playwright/test"
import { isPhone, noHorizontalScroll, openApp } from "./helpers.js"

/** Sends `text` the way this device does: Enter on a fine pointer, Send on a touch screen. */
async function send(page: Page, text: string) {
  const input = page.getByLabel("Message STAR")
  await input.fill(text)
  const coarse = await page.evaluate(() => matchMedia("(pointer: coarse)").matches)
  expect(coarse, "touch emulation gives phones a coarse pointer").toBe(isPhone(page))
  await input.press("Enter")
  if (coarse) {
    await expect(input).toHaveValue(`${text}\n`)
    await page.getByRole("button", { name: "Send" }).click()
  }
}

test("shows STAR's next note and its replies in Markdown without widening the page", async ({ page }) => {
  await openApp(page, "/sphere-app/chat")
  await expect(page.getByRole("region", { name: "STAR's next step" })).toContainText("Next tick in 3 min")
  await expect(page.getByRole("table")).toBeVisible()
  await expect(page.getByText("keep **SPH-12** as is")).toBeVisible()
  await noHorizontalScroll(page)
})

test("sends a message, shows STAR is reading, then the reply, and the page itself never scrolls", async ({ page }) => {
  await openApp(page, "/sphere-app/chat")
  if (isPhone(page)) await expect(page.getByLabel("Message STAR")).toHaveCSS("font-size", "16px")
  await send(page, "how's it going?")
  await expect(page.getByText("STAR is reading…")).toBeVisible()
  await expect(page.getByText("Two workers are building:")).toBeVisible({ timeout: 5000 })
  await expect(page.getByText("STAR is reading…")).toHaveCount(0)
  expect(await page.evaluate(() => window.scrollY)).toBe(0)
  await noHorizontalScroll(page)
})

test("a message to a stopped STAR waits in its inbox", async ({ page }) => {
  await openApp(page, "/juel-claude/chat")
  await expect(page.getByText("STAR isn't running. Your message waits in its inbox.")).toBeVisible()
  await send(page, "are you there?")
  // The sidebar's away switch carries the same note; this one sits under the sent message.
  await expect(
    page.locator('li[data-who="me"]', { hasText: "are you there?" }).getByText("Waits for STAR's next start")
  ).toBeVisible()
  await noHorizontalScroll(page)
})
