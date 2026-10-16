import { expect, test } from "@playwright/test"
import { isPhone, noHorizontalScroll, openApp, MOD } from "./helpers.js"
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
  if (isPhone(page))
    await page.getByRole("button", { name: "Back to Needs you" }).click()
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
test("on a phone, an item opens on its own and Back returns to the list", async ({
  page,
}) => {
  test.skip(!isPhone(page), "the phone layout only")
  await openApp(page)
  const list = page.getByRole("region", { name: "Open loops" })
  await list
    .getByRole("button", { name: /Start building SPH-11, SPH-12 and SPH-14/ })
    .click()
  await expect(page).toHaveURL(/\/sphere-app\/needs\?loop=N-41$/)
  const answer = page.getByRole("region", { name: "Answer" })
  await expect(
    answer.getByRole("heading", {
      name: "Start building SPH-11, SPH-12 and SPH-14",
    })
  ).toBeVisible()
  await expect(list).toBeHidden()
  const coarse = await page.evaluate(
    () => matchMedia("(pointer: coarse)").matches
  )
  if (coarse) {
    await expect(answer.getByText("⌘↵")).toBeHidden()
    const box = await answer
      .getByRole("button", { name: /Send to STAR/ })
      .boundingBox()
    expect(box?.height ?? 0).toBeGreaterThanOrEqual(44)
  }
  await page.goBack()
  await expect(list).toBeVisible()
  await expect(page).toHaveURL(/\/sphere-app\/needs$/)
  await list
    .getByRole("button", { name: /The merge gate failed twice/ })
    .click()
  await answer.getByRole("button", { name: "Back to Needs you" }).click()
  await expect(list).toBeVisible()
  await noHorizontalScroll(page)
})
