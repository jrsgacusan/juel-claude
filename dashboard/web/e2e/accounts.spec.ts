import { expect, test } from "@playwright/test"
import { isPhone, noHorizontalScroll, openApp } from "./helpers.js"

test("the header chip shows the active account and opens every account", async ({ page }) => {
  await openApp(page)
  const chip = page.getByRole("button", { name: "Claude accounts: main, 54% of the week left" })
  await expect(chip).toBeVisible()
  if (isPhone(page)) await expect(chip).toHaveText("54%", { useInnerText: true })
  else await expect(chip).toHaveText(/main\s*54% left/, { useInnerText: true })
  await chip.click()
  const pop = page.getByRole("dialog", { name: "Claude accounts" })
  await expect(pop).toContainText("auto on (cswap auto)")
  await expect(pop.getByRole("listitem")).toHaveCount(3)
  await expect(pop.getByText("main · active")).toBeVisible()
  await expect(pop.getByText(/auto-switch skips it$/)).toHaveCount(2)
  const box = await pop.boundingBox()
  expect(box && box.x >= 0 && box.x + box.width <= (page.viewportSize()?.width ?? 0)).toBe(true)
  await noHorizontalScroll(page)
  await pop.getByRole("link", { name: "See every limit" }).click()
  await expect(page).toHaveURL(/\/sphere-app\/accounts$/)
  await expect(pop).toBeHidden()
})

test("the accounts page shows every limit for every account", async ({ page }) => {
  await openApp(page, "/sphere-app/accounts")
  await expect(page.getByRole("heading", { level: 1, name: "Claude accounts" })).toBeVisible()
  await expect(page.getByRole("article")).toHaveCount(3)
  const main = page.getByRole("article", { name: "main", exact: true })
  await expect(main).toContainText("Active")
  await expect(main).toContainText("of the week left")
  await expect(main).toContainText("Ahead of pace. At this rate it runs out around")
  await expect(page.getByText("Nearly out. Auto-switch skips it until the reset.")).toHaveCount(2)
  if (isPhone(page)) {
    const [a, b] = await Promise.all([main.boundingBox(), page.getByRole("article", { name: "work", exact: true }).boundingBox()])
    expect((b?.y ?? 0) >= (a?.y ?? 0) + (a?.height ?? 0) - 1).toBe(true) // one column
  }
  await noHorizontalScroll(page)
})
