import { expect, test } from "@playwright/test"
import { noHorizontalScroll, openApp, MOD } from "./helpers.js"
test("answers a loop with the recommended option and ⌘Enter", async ({
  page,
}) => {
  await openApp(page)
  await page
    .getByRole("button", { name: /Start building SPH-11, SPH-12 and SPH-14/ })
    .click()
  const answer = page.getByRole("region", { name: "Answer" })
  await expect(
    answer.locator("label").filter({ hasText: "Recommended" }).first()
  ).toContainText("Go")
  await answer.getByRole("radio").first().check()
  await expect(answer.getByRole("radio").first()).toBeChecked()
  await page.keyboard.press(`${MOD}+Enter`)
  await expect(
    page.getByText('Sent to STAR: "go". It acts on it now.')
  ).toBeVisible()
  await expect(page.getByText('Sent "go". STAR picked it up.')).toBeVisible()
  await expect(
    page.getByRole("region", { name: "Open loops" }).getByText("Sent to STAR")
  ).toBeVisible()
  await noHorizontalScroll(page)
})
test("shows the conflict banner on a 409", async ({ page }) => {
  await openApp(page, "/sphere-app/needs?loop=N-41", "conflict")
  const answer = page.getByRole("region", { name: "Answer" })
  await expect(
    answer.locator("label").filter({ hasText: "Recommended" }).first()
  ).toContainText("Go")
  await answer.getByRole("radio").first().check()
  await expect(answer.getByRole("radio").first()).toBeChecked()
  await answer.getByRole("button", { name: /Send to STAR/ }).click()
  await expect(
    page.getByText(
      "open-loops.md has conflict markers. Resolve them, then answer here."
    )
  ).toBeVisible()
  await noHorizontalScroll(page)
})
test("shows the stopped banner for a stopped project", async ({ page }) => {
  await openApp(page, "/juel-claude/needs")
  await expect(
    page.getByText(
      "STAR is stopped for juel-claude. Start it with /juel:star in that project. Your answers wait in its queue."
    )
  ).toBeVisible()
  await noHorizontalScroll(page)
})
