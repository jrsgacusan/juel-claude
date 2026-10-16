import { expect, fakeLog, openApp, starFile, test } from "./helpers.js"

test("answering a loop writes the answer through loops.sh and nudges STAR", async ({
  page,
}) => {
  await openApp(page)
  await page
    .getByRole("button", { name: /Keep the old audit format for a week\?/ })
    .click()
  const answer = page.getByRole("region", { name: "Answer" })
  const radio = answer.getByRole("radio", { name: /^keep it/ })
  await radio.check()
  await expect(radio).toBeChecked()
  const sendCalls = () =>
    fakeLog("orca-calls.log")
      .split("\n")
      .filter((line) =>
        line.includes(
          "terminal send --terminal term_e2e_star --text inbox --enter --json"
        )
      ).length
  const before = sendCalls()
  await answer.getByRole("button", { name: /Send to STAR/ }).click()
  await expect(page.getByText(/Sent "keep it"/)).toBeVisible()
  await expect(
    answer.getByText('Sent "keep it". STAR picked it up.')
  ).toBeVisible()
  await expect.poll(sendCalls).toBe(before + 1)
  await expect
    .poll(() => starFile("open-loops.md"))
    .toMatch(
      /### N-1 · sample · audit-log · [^\n]*\nkind: question\noptions: [^\n]*\nAnswer: keep it\n/
    )
})

test("a go-batch names its items by their ledger name", async ({ page }) => {
  await openApp(page, "/sample/needs?loop=N-2")
  const answer = page.getByRole("region", { name: "Answer" })
  await expect(
    answer.getByRole("heading", { name: "Go for batch 1" })
  ).toBeVisible()
  await expect(
    answer.getByText("invoice-export", { exact: true })
  ).toBeVisible()
  await expect(
    answer.getByText("Export invoices as CSV", { exact: true })
  ).toBeVisible()
  await expect(answer.getByText(/\/Users\/owner\/star\/items/)).toHaveCount(0)
})
