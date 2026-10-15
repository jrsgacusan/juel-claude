import { expect, test } from "@playwright/test"
import { noHorizontalScroll, openApp } from "./helpers"
test("edits and sends a draft", async ({ page }) => {
  await openApp(page, "/sphere-app/slack")
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
  await page.getByRole("button", { name: "Skip" }).click()
  await expect(
    page.getByText("Skipped. The watcher will not raise it again.")
  ).toBeVisible()
  await page
    .getByRole("region", { name: "Messages" })
    .getByText("which PR fixes the invoice time zone?")
    .click()
  await page.getByRole("button", { name: "Shorter" }).click()
  await expect(page.getByText('STAR is rewriting it: "shorter".')).toBeVisible()
  await page
    .getByRole("region", { name: "Messages" })
    .getByText("who owns the staging deploy this week?")
    .click()
  await page.getByRole("combobox", { name: "Project" }).click()
  await page.getByRole("option", { name: "sphere-api" }).click()
  await page.getByRole("button", { name: "Route it" }).click()
  await expect(
    page.getByText("Routed. That STAR drafts a reply on its next tick.")
  ).toBeVisible()
  await noHorizontalScroll(page)
})
test("says when Slack isn't connected", async ({ page }) => {
  await openApp(page, "/sphere-app/slack", "slack-off")
  await expect(page.getByText("Slack isn't connected")).toBeVisible()
  await noHorizontalScroll(page)
})
