import { expect, openApp, test } from "./helpers.js"

test("⌘K returns grouped results and opens an item", async ({ page }) => {
  await openApp(page)
  // The app opens search on Meta+K or Control+K (src/components/app-layout.tsx).
  await page.keyboard.press("Control+k")
  await page.getByRole("dialog").getByRole("combobox").fill("invoice")
  const suggestions = page.getByRole("listbox", { name: "Suggestions" })
  await expect(suggestions.getByRole("group", { name: "Items" })).toBeVisible()
  await expect(
    suggestions.getByRole("option", { name: /Export invoices as CSV/ })
  ).toBeVisible()
  await suggestions
    .getByRole("option", { name: /Export invoices as CSV/ })
    .click()
  await expect(page).toHaveURL(/\/sample\/progress\?item=invoice-export$/)
  await expect(
    page
      .getByRole("dialog")
      .getByRole("heading", { name: "Export invoices as CSV" })
  ).toBeVisible()
})

test.describe("on a phone", () => {
  test.use({
    viewport: { width: 390, height: 844 },
    hasTouch: true,
    isMobile: true,
  })
  test("the switch sits above the results and the input does not zoom", async ({
    page,
  }) => {
    await openApp(page)
    await page.getByRole("button", { name: "Search (⌘K)" }).click()
    const dialog = page.getByRole("dialog")
    const input = dialog.getByRole("combobox")
    await expect(input).toHaveCSS("font-size", "16px")
    await input.fill("invoice")
    const option = dialog.getByRole("option", {
      name: /Export invoices as CSV/,
    })
    await expect(option).toBeVisible()
    const toggle = await dialog
      .getByRole("switch", { name: "Search every project" })
      .boundingBox()
    const result = await option.boundingBox()
    expect(toggle && result && toggle.y < result.y).toBe(true)
    expect((toggle?.y ?? 844) + (toggle?.height ?? 0)).toBeLessThan(422)
  })
})
