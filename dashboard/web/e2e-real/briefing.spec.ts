import { existsSync, readdirSync, writeFileSync } from "node:fs"
import { join } from "node:path"
import { e2e, expect, openApp, starFile, test } from "./helpers.js"

test("a message gets a streamed reply, and create writes the spec and the inbox file", async ({
  page,
}) => {
  await openApp(page, "/sample/briefing")
  await page.getByRole("button", { name: "New briefing" }).first().click()
  await page
    .getByRole("textbox", { name: "Message the briefing agent" })
    .fill("Remind owners when an invoice is overdue.")
  await page.getByRole("button", { name: "Send" }).click()
  const conversation = page.getByRole("region", { name: "Conversation" })
  const draft = page.getByRole("region", { name: "Ticket draft" })
  await expect(
    conversation.getByText("I read the invoices module")
  ).toBeVisible()
  await expect(
    draft.getByRole("heading", { name: "Remind owners about unpaid invoices" })
  ).toHaveCount(0)
  writeFileSync(join(e2e().fakes, "turn.release"), "")
  await expect(
    draft.getByRole("heading", { name: "Remind owners about unpaid invoices" })
  ).toBeVisible()
  await expect(conversation.getByText("Here is the ticket.")).toBeVisible()
  await expect(
    conversation.getByText("I read the invoices module")
  ).toBeVisible()
  await draft.getByRole("combobox", { name: "Tracker" }).click()
  await page
    .getByRole("option", { name: "No tracker, a spec file STAR keeps" })
    .click()
  await draft
    .getByRole("button", { name: "Save as a spec and hand to STAR" })
    .click()
  await expect(draft.getByRole("button", { name: /^Created / })).toBeVisible()
  await expect
    .poll(() =>
      existsSync(
        join(e2e().star, "items/sample/remind-owners-about-unpaid-invoices.md")
      )
    )
    .toBe(true)
  expect(
    starFile("items/sample/remind-owners-about-unpaid-invoices.md")
  ).toContain("Remind owners about unpaid invoices")
  await expect
    .poll(() =>
      readdirSync(join(e2e().star, "inbox"))
        .map((n) => starFile(`inbox/${n}`))
        .some((t) =>
          t.includes("items/sample/remind-owners-about-unpaid-invoices.md")
        )
    )
    .toBe(true)
  const id = new URL(page.url()).searchParams.get("briefing")
  expect(id).toBeTruthy()
  await conversation.getByRole("button", { name: "More actions" }).click()
  await page.getByRole("menuitem", { name: "Delete briefing" }).click()
  await conversation.getByRole("button", { name: "Delete briefing" }).click()
  await expect(page.getByText('Deleted "Remind owners about unpaid invoices".')).toBeVisible()
  await expect.poll(() => existsSync(join(e2e().star, "briefings", id!))).toBe(false)
  expect(starFile("items/sample/remind-owners-about-unpaid-invoices.md")).toContain(
    "Remind owners about unpaid invoices"
  )
  expect(
    readdirSync(join(e2e().star, "inbox")).some((n) =>
      starFile(`inbox/${n}`).includes("items/sample/remind-owners-about-unpaid-invoices.md")
    )
  ).toBe(true)
})
