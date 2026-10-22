import { expect, test, type Page } from "@playwright/test"
import { isPhone, noHorizontalScroll, openApp } from "./helpers.js"

/** Sends `text` the way this device does: Enter on a fine pointer, Send on a touch screen. */
async function send(page: Page, text: string) {
  const input = page.getByLabel("Message the briefing agent")
  await input.fill(text)
  await input.press("Enter")
  if (isPhone(page)) await page.getByRole("button", { name: "Send" }).click()
}

test("chats, streams the reply, answers the tracker question and creates a ticket", async ({
  page,
}) => {
  await openApp(page, "/sphere-app/briefing")
  await send(page, "Also log who paused it")
  await expect(page.getByTestId("agent-streaming")).toBeVisible()
  await expect(page.getByText("Noted: Also log who paused it.")).toBeVisible({
    timeout: 5000,
  })
  expect(await page.evaluate(() => window.scrollY)).toBe(0)
  if (isPhone(page)) await page.getByRole("tab", { name: "Draft" }).click()
  const draft = page.getByRole("region", { name: "Ticket draft" })
  await draft.getByRole("combobox", { name: "Tracker" }).click()
  await page.getByRole("option", { name: "Synapse" }).click()
  await expect(draft).toContainText("Synapse isn't connected yet.")
  await draft.getByRole("combobox", { name: "Tracker" }).click()
  await page.getByRole("option", { name: "GitHub Issues" }).click()
  await draft
    .getByRole("button", { name: "Create in GitHub Issues and hand to STAR" })
    .click()
  await expect(
    page.getByText("#88 created in GitHub Issues. STAR is briefing it now.")
  ).toBeVisible()
  await noHorizontalScroll(page)
})

test("deletes a briefing after asking in the page, never in a browser dialog", async ({ page }) => {
  let dialogs = 0
  page.on("dialog", (dialog) => {
    dialogs += 1
    void dialog.dismiss()
  })
  await openApp(page, "/sphere-app/briefing?briefing=b0")
  const chat = page.getByRole("region", { name: "Conversation" })
  await chat.getByRole("button", { name: "More actions" }).click()
  await page.getByRole("menuitem", { name: "Delete briefing" }).click()
  await expect(chat.getByRole("group", { name: "Delete this briefing" })).toContainText(
    'Delete "Export reports as CSV"? This removes its chat and draft.'
  )
  await chat.getByRole("button", { name: "Delete briefing" }).click()
  await expect(page.getByText('Deleted "Export reports as CSV".')).toBeVisible()
  await expect(page.getByRole("combobox", { name: "Briefing" })).toContainText("Pause a member's seat")
  expect(dialogs).toBe(0)
  await noHorizontalScroll(page)
})

test("on a phone, Chat and Draft are tabs", async ({ page }) => {
  test.skip(!isPhone(page), "the tabs are for phones")
  await openApp(page, "/sphere-app/briefing")
  const draft = page.getByRole("region", { name: "Ticket draft" })
  await expect(draft).toBeHidden()
  await page.getByRole("tab", { name: "Draft" }).click()
  await expect(draft).toBeVisible()
  await expect(page.getByRole("region", { name: "Conversation" })).toBeHidden()
  await page.getByRole("tab", { name: "Chat" }).click()
  await expect(page.getByLabel("Message the briefing agent")).toHaveCSS("font-size", "16px")
  await noHorizontalScroll(page)
})
