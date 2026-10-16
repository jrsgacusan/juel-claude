import { readdirSync } from "node:fs"
import { join } from "node:path"
import { e2e, expect, openApp, starFile, test } from "./helpers.js"

test("the watcher's status shows, a message routes, and a draft edit saves", async ({ page }) => {
  await openApp(page, "/sample/slack")
  await expect(page.getByText(/Watching Acme with Haiku/)).toBeVisible()
  await page.getByRole("button", { name: /Ria .*Is the CSV export landing today\?/ }).click()
  const reply = page.getByRole("region", { name: "Reply" })
  await expect(reply.getByRole("combobox", { name: "Project" })).toContainText("sample")
  await reply.getByRole("button", { name: "Route it" }).click()
  await expect
    .poll(() => readdirSync(join(e2e().star, "inbox")).filter((n) => /-slack-[0-9a-f]{4}\.md$/.test(n)).length)
    .toBe(1)
  await page.getByRole("button", { name: /Ria .*Routed/ }).click()
  const box = reply.getByRole("textbox", { name: "Your reply" })
  await expect(box).toHaveValue("Yes, the CSV export lands today after the review.")
  await box.fill("Yes, it lands today after the review, around 5 pm.")
  await box.blur()
  await expect
    .poll(() => starFile("drafts/2026-10-16-sample-slack-C0E2E-1760000000.000100.md"))
    .toBe("to: slack C0E2E 1760000000.000100\nYes, it lands today after the review, around 5 pm.\n")
})
