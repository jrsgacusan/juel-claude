import { expect, test } from "@playwright/test"
import { noHorizontalScroll, openApp } from "./helpers"
test("chats, streams the reply, answers the tracker question and creates a ticket", async ({
  page,
}) => {
  await openApp(page, "/sphere-app/briefing")
  const input = page.getByLabel("Message the briefing agent")
  await input.fill("Also log who paused it")
  await input.press("Enter")
  await expect(page.getByTestId("agent-streaming")).toBeVisible()
  await expect(page.getByText("Noted: Also log who paused it.")).toBeVisible({
    timeout: 5000,
  })
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
