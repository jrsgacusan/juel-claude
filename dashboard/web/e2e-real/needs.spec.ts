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

test("a person step shows its title and what it is for", async ({ page }) => {
  await openApp(page, "/needs?project=sample&loop=N-2")
  const answer = page.getByRole("region", { name: "Answer" })
  await expect(
    answer.getByRole("heading", {
      name: "Add the webhook secret to .env.local",
    })
  ).toBeVisible()
  await expect(answer.getByText("Your step", { exact: true })).toBeVisible()
  await expect(answer.getByText("kind: secret")).toBeVisible()
  await expect(answer.getByRole("radio", { name: /^done/ })).toBeVisible()
  await expect(answer.getByText("STAR recommends")).toHaveCount(0)
})

test.describe("on a phone", () => {
  test.use({
    viewport: { width: 390, height: 844 },
    isMobile: true,
    hasTouch: true,
  })

  test("an item opens on its own and Back returns to the list", async ({
    page,
  }) => {
    await openApp(page)
    const list = page.getByRole("region", { name: "Open loops" })
    await list.getByRole("button", { name: /Add the webhook secret/ }).click()
    await expect(
      page
        .getByRole("region", { name: "Answer" })
        .getByRole("heading", { name: "Add the webhook secret to .env.local" })
    ).toBeVisible()
    await expect(list).toBeHidden()
    await page.goBack()
    await expect(list).toBeVisible()
  })
})
