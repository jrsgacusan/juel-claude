import { execFileSync } from "node:child_process"
import { appendFileSync } from "node:fs"
import { join } from "node:path"
import type { Page } from "@playwright/test"
import { e2e, expect, launchEnv, openApp, REPO_ROOT, test } from "./helpers.js"

declare global {
  interface Window {
    __e2eNoReload?: boolean
  }
}

const markNoReload = (page: Page) =>
  page.evaluate(() => {
    window.__e2eNoReload = true
  })

test("a progress line reaches the open sheet", async ({ page }) => {
  const lost: string[] = []
  page.on("console", (message) => {
    if (message.text().includes("[events] lost the stream"))
      lost.push(message.text())
  })
  await openApp(page, "/sample/progress?item=csv-import")
  await expect(page.getByRole("dialog")).toContainText(
    "waiting for the hosted review"
  )
  await markNoReload(page)
  appendFileSync(
    join(e2e().star, "progress/csv-import.log"),
    `${new Date().toISOString().replace(/\.\d+Z$/, "Z")} live-check e2e live step appended\n`
  )
  await expect(page.getByRole("dialog")).toContainText("e2e live step appended")
  await expect(page).toHaveURL(/\/sample\/progress\?item=csv-import$/)
  expect(await page.evaluate(() => window.__e2eNoReload)).toBe(true)
  expect(lost).toEqual([])
})

test("a loop STAR adds reaches Needs you", async ({ page }) => {
  const lost: string[] = []
  page.on("console", (message) => {
    if (message.text().includes("[events] lost the stream"))
      lost.push(message.text())
  })
  await openApp(page)
  await markNoReload(page)
  execFileSync(
    "sh",
    [
      join(REPO_ROOT, "skills/star/loops.sh"),
      "--file",
      join(e2e().star, "open-loops.md"),
      "add",
      "--kind",
      "question",
      "--project",
      "sample",
      "--item",
      "csv-import",
      "--title",
      "Ship the importer behind a flag?",
    ],
    { env: launchEnv(), cwd: e2e().repo }
  )
  await expect(
    page.getByRole("button", { name: /Ship the importer behind a flag\?/ })
  ).toBeVisible()
  expect(await page.evaluate(() => window.__e2eNoReload)).toBe(true)
  expect(lost).toEqual([])
})

test("coming back to the page refetches without a reload or a second stream", async ({
  page,
}) => {
  await openApp(page)
  await markNoReload(page)
  const streams: string[] = []
  page.on("request", (request) => {
    if (new URL(request.url()).pathname === "/api/events")
      streams.push(request.url())
  })
  const refetch = page.waitForRequest(
    (request) =>
      new URL(request.url()).pathname === "/api/loops"
  )
  await page.evaluate(() =>
    document.dispatchEvent(new Event("visibilitychange"))
  )
  await refetch
  expect(streams).toEqual([])
  expect(await page.evaluate(() => window.__e2eNoReload)).toBe(true)
})
