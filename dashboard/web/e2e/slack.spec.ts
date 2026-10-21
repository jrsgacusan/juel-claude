import { expect, test, type Page } from "@playwright/test"
import { isPhone, noHorizontalScroll, openApp } from "./helpers.js"
const RIA =
  "hey, is the CSV export landing today? sales wants to demo it tomorrow"
/** Picks a message from the list; on a phone, from the list a Back away. */
async function openMessage(page: Page, text: string) {
  const back = page.getByRole("button", { name: "Back to Slack replies" })
  if (isPhone(page) && (await back.isVisible())) await back.click()
  await page.getByRole("region", { name: "Messages" }).getByText(text).click()
}
test("edits and sends a draft", async ({ page }) => {
  await openApp(page, "/sphere-app/slack")
  await openMessage(page, RIA)
  const box = page.getByLabel("Your reply")
  await expect(box).toHaveValue(/Not today\./)
  await box.fill("Not today, it lands tomorrow morning.")
  const put = page.waitForRequest(
    (r) => r.method() === "PUT" && r.url().includes("/drafts/")
  )
  await box.press("Tab")
  await put
  await expect(page.getByText("Saved")).toBeVisible()
  await page.getByRole("button", { name: "Send reply" }).click()
  await expect(
    page.getByText("Sent. STAR posts it to #sphere-eng as you.")
  ).toBeVisible()
  await noHorizontalScroll(page)
})
test("skips one, rewrites one with a chip and routes an unrouted one", async ({
  page,
}) => {
  await openApp(page, "/sphere-app/slack")
  await openMessage(page, RIA)
  await page.getByRole("button", { name: "Skip" }).click()
  await expect(
    page.getByText("Skipped. The watcher will not raise it again.")
  ).toBeVisible()
  await openMessage(page, "which PR fixes the invoice time zone?")
  await page.getByRole("button", { name: "Shorter" }).click()
  await expect(page.getByLabel("Ask the drafter to rewrite it")).toHaveValue(
    "shorter"
  )
  await page.getByRole("button", { name: /^Rewrite$/ }).click()
  await expect(page.getByText("Rewriting…")).toBeVisible()
  await expect(page.getByLabel("Your reply")).toHaveValue(
    /^Rewritten \(shorter\): None yet\./
  )
  await openMessage(page, "who owns the staging deploy this week?")
  await page.getByRole("combobox", { name: "Project" }).click()
  await page.getByRole("option", { name: "sphere-api" }).click()
  await page.getByRole("button", { name: "Route it" }).click()
  await expect(page.getByText("Routed to sphere-api.")).toBeVisible()
  await noHorizontalScroll(page)
})
test("says when Slack isn't connected", async ({ page }) => {
  await openApp(page, "/sphere-app/slack", "slack-off")
  await expect(page.getByText("Slack isn't connected")).toBeVisible()
  await noHorizontalScroll(page)
})
test("a thread keeps its bullets and links, and on a phone Back returns to the list", async ({
  page,
}) => {
  await openApp(page, "/sphere-app/slack")
  await openMessage(page, "which PR fixes the invoice time zone?")
  const reply = page.getByRole("region", { name: "Reply" })
  const pr = reply.getByRole("link", {
    name: "https://github.com/example/sphere-app/pull/207",
  })
  await expect(pr).toHaveAttribute("target", "_blank")
  await expect(
    reply.getByRole("link", { name: "release notes" })
  ).toHaveAttribute("href", "https://example.com/notes/invoice-rounding")
  if (isPhone(page)) {
    await expect(page.getByLabel("Your reply")).toHaveCSS("font-size", "16px")
    const coarse = await page.evaluate(
      () => matchMedia("(pointer: coarse)").matches
    )
    if (coarse)
      for (const name of ["Skip", "Send reply", "Shorter"]) {
        const box = await reply.getByRole("button", { name }).boundingBox()
        // a fractional layout offset can make a 44px box measure 43.9999…
        expect(Math.round(box?.height ?? 0)).toBeGreaterThanOrEqual(44)
      }
    await expect(page.getByRole("region", { name: "Messages" })).toBeHidden()
    await page.goBack()
    await expect(page.getByRole("region", { name: "Messages" })).toBeVisible()
  }
  await noHorizontalScroll(page)
})
