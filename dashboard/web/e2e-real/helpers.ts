import { expect as baseExpect, test as baseTest, type Page } from "@playwright/test"
import { readFileSync } from "node:fs"
import { join, resolve } from "node:path"

const errors = new WeakMap<Page, string[]>()

export const test = baseTest.extend<{ page: Page }>({
  page: async ({ page }, provide) => {
    const messages: string[] = []
    errors.set(page, messages)
    page.on("console", (message) => {
      if (message.type() === "error") messages.push(`console: ${message.text()}`)
    })
    page.on("pageerror", (error) => messages.push(`pageerror: ${error.message}`))
    await provide(page)
    baseExpect(messages, "console errors").toEqual([])
  },
})
export const expect = baseExpect

export const REPO_ROOT = resolve(import.meta.dirname, "../../..")

export function e2e(): {
  root: string
  url: string
  origin: string
  token: string
  home: string
  star: string
  fakes: string
  bin: string
  repo: string
} {
  const required = (name: string): string => {
    const value = process.env[name]
    if (!value) throw new Error(`missing ${name}`)
    return value
  }
  const root = required("STAR_E2E_ROOT")
  return {
    root,
    url: required("STAR_E2E_URL"),
    origin: required("STAR_E2E_ORIGIN"),
    token: required("STAR_E2E_TOKEN"),
    home: join(root, "home"),
    star: join(root, "star"),
    fakes: join(root, "fakes"),
    bin: join(root, "bin"),
    repo: join(root, "repo"),
  }
}

export function launchEnv(): NodeJS.ProcessEnv {
  const { home, bin, fakes } = e2e()
  return {
    ...process.env,
    HOME: home,
    PATH: `${bin}:${process.env.PATH ?? ""}`,
    FAKE_ORCA_DIR: fakes,
    STAR_E2E_FAKES: fakes,
  }
}

export const starFile = (rel: string): string =>
  readFileSync(join(e2e().star, rel), "utf8")

export function fakeLog(name: string): string {
  try {
    return readFileSync(join(e2e().fakes, name), "utf8")
  } catch {
    return ""
  }
}

export async function openApp(page: Page, path = "/sample/needs"): Promise<void> {
  await page.goto(e2e().url)
  await expect(page).toHaveURL(/\/sample\/needs$/)
  if (path !== "/sample/needs") await page.goto(e2e().origin + path)
}

export const SEARCH_KEY = "Control+k"
