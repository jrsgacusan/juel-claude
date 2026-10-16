import { existsSync, readdirSync } from "node:fs"
import { join } from "node:path"
import { e2e, expect, openApp, starFile, test } from "./helpers.js"

test("a message gets a streamed reply, and create writes the spec and the inbox file", async ({ page }) => {
  await openApp(page, "/sample/briefing")
  await page.getByRole("button", { name: "New briefing" }).first().click()
  await page.getByRole("textbox", { name: "Message the briefing agent" }).fill("Remind owners when an invoice is overdue.")
  await page.getByRole("button", { name: "Send" }).click()
  const conversation = page.getByRole("region", { name: "Conversation" })
  const draft = page.getByRole("region", { name: "Ticket draft" })
  await expect(conversation.getByText("I read the invoices module")).toBeVisible()
  await expect(draft.getByRole("heading", { name: "Remind owners about unpaid invoices" })).toHaveCount(0)
  await expect(draft.getByRole("heading", { name: "Remind owners about unpaid invoices" })).toBeVisible()
  await draft.getByRole("combobox", { name: "Tracker" }).click()
  await page.getByRole("option", { name: "No tracker, a spec file STAR keeps" }).click()
  await draft.getByRole("button", { name: "Save as a spec and hand to STAR" }).click()
  await expect(draft.getByRole("button", { name: /^Created / })).toBeVisible()
  await expect
    .poll(() => existsSync(join(e2e().star, "items/sample/remind-owners-about-unpaid-invoices.md")))
    .toBe(true)
  await expect
    .poll(() =>
      readdirSync(join(e2e().star, "inbox"))
        .filter((n) => !n.includes("-slack-"))
        .map((n) => starFile(`inbox/${n}`))
        .some((t) => t.includes("items/sample/remind-owners-about-unpaid-invoices.md")),
    )
    .toBe(true)
})
