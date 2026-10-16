import { expect, test as baseTest, type Page } from "@playwright/test"
import { readFileSync } from "node:fs"
import { join } from "node:path"
import * as stack from "./stack.js"
import type { StackPaths } from "./stack.js"

// Fails a test on any console error or page error (spec S5); warnings such as "[events] lost the stream" are not errors.
export const test = baseTest.extend<{ page: Page }>({
  page: async ({ page }, provide) => {
    const messages: string[] = []
    page.on("console", (message) => {
      if (message.type() === "error")
        messages.push(`console: ${message.text()}`)
    })
    page.on("pageerror", (error) =>
      messages.push(`pageerror: ${error.message}`)
    )
    await provide(page)
    expect(messages, "console errors").toEqual([])
  },
})
export { expect }
export { REPO_ROOT } from "./stack.js"

export function e2e(): StackPaths & { url: string; origin: string } {
  const required = (name: string): string => {
    const value = process.env[name]
    if (!value) throw new Error(`missing ${name}`)
    return value
  }
  const root = required("STAR_E2E_ROOT")
  const url = required("STAR_E2E_URL")
  return { ...stack.paths(root), url, origin: new URL(url).origin }
}

export function launchEnv(): NodeJS.ProcessEnv {
  return stack.launchEnv(e2e().root)
}

export const starFile = (rel: string): string =>
  readFileSync(join(e2e().star, rel), "utf8")

export function fakeLog(name: string): string {
  const { fakes } = e2e()
  try {
    return readFileSync(join(fakes, name), "utf8")
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return ""
    throw error
  }
}

export async function openApp(
  page: Page,
  path = "/sample/needs"
): Promise<void> {
  // The first load hands ?t= to localStorage (src/api/token.ts captureToken); later loads and new pages in this browser read it there.
  await page.goto(e2e().url)
  await expect(page).toHaveURL(/\/sample\/needs$/)
  if (path !== "/sample/needs") await page.goto(e2e().origin + path)
}
