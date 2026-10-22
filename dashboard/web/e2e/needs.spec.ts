import { expect, test } from "@playwright/test"
import { isPhone, noHorizontalScroll, openApp, MOD } from "./helpers.js"
test("answers a loop with the recommended option and ⌘Enter", async ({
  page,
}) => {
  await openApp(page, "/needs")
  await page
    .getByRole("button", { name: /Log in to the Stripe dashboard/ })
    .click()
  const answer = page.getByRole("region", { name: "Answer" })
  await expect(
    answer.locator("label").filter({ hasText: "Recommended" }).first()
  ).toContainText("Done")
  await answer.getByRole("radio").first().check()
  await expect(answer.getByRole("radio").first()).toBeChecked()
  await page.keyboard.press(`${MOD}+Enter`)
  await expect(
    page.getByText('Sent to STAR: "done". It acts on it now.')
  ).toBeVisible()
  await expect(page.getByText('Sent "done". STAR picked it up.')).toBeVisible()
  if (isPhone(page))
    await page.getByRole("button", { name: "Back to Needs you" }).click()
  await expect(
    page.getByRole("region", { name: "Open loops" }).getByText("Sent to STAR")
  ).toBeVisible()
  await noHorizontalScroll(page)
})
test("shows the conflict banner on a 409", async ({ page }) => {
  await openApp(page, "/needs?project=sphere-app&loop=N-41", "conflict")
  const answer = page.getByRole("region", { name: "Answer" })
  await expect(
    answer.locator("label").filter({ hasText: "Recommended" }).first()
  ).toContainText("Done")
  await answer.getByRole("radio").first().check()
  await expect(answer.getByRole("radio").first()).toBeChecked()
  await answer.getByRole("button", { name: /Send to STAR/ }).click()
  await expect(
    page.getByText(
      "open-loops.md in sphere-app has conflict markers. Resolve them, then answer here."
    )
  ).toBeVisible()
  await noHorizontalScroll(page)
})
test("shows the stopped banner for a stopped project", async ({ page }) => {
  await openApp(page, "/juel-claude/progress")
  await expect(
    page.getByText(
      "STAR is stopped for juel-claude. Start it with /juel:star in that project. Your answers wait in its queue."
    )
  ).toBeVisible()
  await noHorizontalScroll(page)
})
test("on a phone, an item opens on its own and Back returns to the list", async ({
  page,
}) => {
  test.skip(!isPhone(page), "the phone layout only")
  await openApp(page, "/needs")
  const list = page.getByRole("region", { name: "Open loops" })
  await expect(list.locator("[aria-current]")).toHaveCount(0)
  await list
    .getByRole("button", { name: /Log in to the Stripe dashboard/ })
    .click()
  await expect(page).toHaveURL(/\/needs\?loop=sphere-app%2FN-41$/)
  const answer = page.getByRole("region", { name: "Answer" })
  await expect(
    answer.getByRole("heading", {
      name: "Log in to the Stripe dashboard and enable test mode",
    })
  ).toBeVisible()
  await expect(list).toBeHidden()
  const coarse = await page.evaluate(
    () => matchMedia("(pointer: coarse)").matches
  )
  await expect(answer.getByText("⌘↵")).toHaveCount(0)
  const dock = answer.locator("[data-slot='answer-dock']")
  const send = dock.getByRole("button", { name: /Send to STAR/ })
  await expect(send).toBeVisible()
  const box = await send.boundingBox()
  // a fractional layout offset can make a 44px box measure 43.9999…
  expect(Math.round(box?.height ?? 0)).toBeGreaterThanOrEqual(44)
  if (!coarse) expect(box?.height ?? 0).toBeGreaterThan(0)
  await page.goBack()
  await expect(list).toBeVisible()
  await expect(page).toHaveURL(/\/needs$/)
  await list
    .getByRole("button", { name: /The merge gate failed twice/ })
    .click()
  await answer.getByRole("button", { name: "Back to Needs you" }).click()
  await expect(list).toBeVisible()
  await noHorizontalScroll(page)
})
test("on a phone, Done holds the answer with an Undo toast, then sends it", async ({
  page,
}) => {
  test.skip(!isPhone(page), "the phone layout only")
  await openApp(page, "/needs")
  const row = page
    .getByRole("region", { name: "Open loops" })
    .getByRole("listitem")
    .filter({ hasText: /Log in to the Stripe dashboard/ })
  await row.getByRole("button", { name: "Done" }).click()
  await expect(
    page.getByText('"Done" goes to STAR in 5 seconds.')
  ).toBeVisible()
  await expect(row.getByText("Sending…")).toBeVisible()
  await expect(row.getByText("Sent to STAR")).toBeVisible({ timeout: 15_000 })
  await noHorizontalScroll(page)
})
test("on a phone, Undo leaves the row unanswered", async ({ page }) => {
  test.skip(!isPhone(page), "the phone layout only")
  await openApp(page, "/needs")
  const row = page
    .getByRole("region", { name: "Open loops" })
    .getByRole("listitem")
    .filter({ hasText: /Log in to the Stripe dashboard/ })
  await row.getByRole("button", { name: "Done" }).click()
  await page
    .locator("[data-sonner-toast]")
    .getByRole("button", { name: "Undo" })
    .click()
  await page.waitForTimeout(6000)
  await expect(row.getByRole("button", { name: "Done" })).toBeVisible()
  await expect(row.getByText("Sent to STAR")).toHaveCount(0)
})
test("items from two projects show on /needs, and answering one marks it Sent to STAR", async ({
  page,
}) => {
  await openApp(page, "/needs")
  const list = page.getByRole("region", { name: "Open loops" })
  await expect(list.getByText("sphere-app").first()).toBeVisible()
  await expect(list.getByText("juel-claude").first()).toBeVisible()
  await list
    .getByRole("button", { name: /star-dashboard-server set aside/ })
    .click()
  const answer = page.getByRole("region", { name: "Answer" })
  await answer.getByRole("radio").first().check()
  await answer.getByRole("button", { name: /Send to STAR/ }).click()
  await expect(
    page.getByText(/^Sent to STAR: "try again"/).first()
  ).toBeVisible()
  if (isPhone(page))
    await page.getByRole("button", { name: "Back to Needs you" }).click()
  await expect(
    page.getByRole("region", { name: "Open loops" }).getByText("Sent to STAR")
  ).toBeVisible()
  await noHorizontalScroll(page)
})
