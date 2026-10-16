import { expect, openApp, test } from "./helpers.js"

test("⌘K returns grouped results and opens an item", async ({ page }) => {
  await openApp(page)
  // The app opens search on Meta+K or Control+K (src/components/app-layout.tsx).
  await page.keyboard.press("Control+k")
  await page.getByRole("dialog").getByRole("combobox").fill("invoice")
  const suggestions = page.getByRole("listbox", { name: "Suggestions" })
  await expect(suggestions.getByRole("group", { name: "Items" })).toBeVisible()
  await expect(suggestions.getByRole("option", { name: /Export invoices as CSV/ })).toBeVisible()
  await suggestions.getByRole("option", { name: /Export invoices as CSV/ }).click()
  await expect(page).toHaveURL(/\/sample\/progress\?item=invoice-export$/)
  await expect(page.getByRole("dialog").getByRole("heading", { name: "Export invoices as CSV" })).toBeVisible()
})
