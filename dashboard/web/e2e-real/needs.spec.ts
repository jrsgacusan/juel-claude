import { expect, fakeLog, openApp, starFile, test } from "./helpers.js"

test("answering a loop writes the answer through loops.sh and nudges STAR", async ({ page }) => {
  await openApp(page)
  await page.getByRole("button", { name: /Keep the old audit format for a week\?/ }).click()
  const answer = page.getByRole("region", { name: "Answer" })
  await expect(answer.getByRole("radio", { name: /^keep it/ })).toBeChecked()
  await answer.getByRole("button", { name: /Send to STAR/ }).click()
  await expect(page.getByText(/Sent "keep it"/)).toBeVisible()
  await expect
    .poll(() => starFile("open-loops.md"))
    .toMatch(/### N-1 · sample · audit-log · [^\n]*\nkind: question\noptions: [^\n]*\nAnswer: keep it\n/)
  await expect
    .poll(() => fakeLog("orca-calls.log"))
    .toContain("terminal send --terminal term_e2e_star --text inbox --enter --json")
})
