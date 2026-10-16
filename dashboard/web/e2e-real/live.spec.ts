import { appendFileSync } from "node:fs"
import { execFileSync } from "node:child_process"
import { join } from "node:path"
import { e2e, expect, openApp, REPO_ROOT, test } from "./helpers.js"

const markNoReload = (page: Parameters<typeof openApp>[0]) =>
  page.evaluate(() => {
    ;(window as Window & { __e2eNoReload?: boolean }).__e2eNoReload = true
  })

test("a progress line reaches the open sheet", async ({ page }) => {
  await openApp(page, "/sample/progress?item=csv-import")
  await expect(page.getByRole("dialog")).toContainText("waiting for the hosted review")
  await markNoReload(page)
  appendFileSync(
    join(e2e().star, "progress/csv-import.log"),
    `${new Date().toISOString().replace(/\.\d+Z$/, "Z")} live-check e2e live step appended\n`,
  )
  await expect(page.getByRole("dialog")).toContainText("e2e live step appended")
  await expect(page).toHaveURL(/\/sample\/progress\?item=csv-import$/)
  await expect
    .poll(() => page.evaluate(() => (window as Window & { __e2eNoReload?: boolean }).__e2eNoReload))
    .toBe(true)
})

test("a loop STAR adds reaches Needs you", async ({ page }) => {
  await openApp(page)
  await markNoReload(page)
  execFileSync("sh", [join(REPO_ROOT, "skills/star/loops.sh"), "--file", join(e2e().star, "open-loops.md"), "add", "--kind", "question", "--project", "sample", "--item", "csv-import", "--title", "Ship the importer behind a flag?"])
  await expect(page.getByRole("button", { name: /Ship the importer behind a flag\?/ })).toBeVisible()
  await expect
    .poll(() => page.evaluate(() => (window as Window & { __e2eNoReload?: boolean }).__e2eNoReload))
    .toBe(true)
})
