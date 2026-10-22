import { devices } from "@playwright/test"
import { expect, openApp, e2e, test } from "./helpers.js"

// iPhone emulation Chromium supports (no WebKit project here): the phone's size, touch and user agent.
const iphone = {
  viewport: { width: 390, height: 844 },
  isMobile: true,
  hasTouch: true,
  deviceScaleFactor: 3,
  userAgent: devices["iPhone 13"].userAgent,
}

const token = (): string => {
  const value = new URL(e2e().url).searchParams.get("t")
  if (!value) throw new Error("STAR_E2E_URL has no token")
  return value
}

const PASTE = /Paste that link here/

test("the page links a manifest whose start_url carries the token, with icons that load", async ({
  page,
}) => {
  await openApp(page)
  const href = await page
    .locator('link[rel="manifest"]')
    .getAttribute("href")
  expect(href).toMatch(new RegExp(`\\?t=${encodeURIComponent(token())}$`))
  await expect(page.locator('link[rel="manifest"]')).toHaveCount(1)

  const res = await fetch(new URL(href ?? "", e2e().origin))
  expect(res.status).toBe(200)
  const manifest = (await res.json()) as {
    start_url: string
    display: string
    icons: { src: string }[]
  }
  expect(manifest.start_url).toBe(`/?t=${encodeURIComponent(token())}`)
  expect(manifest.display).toBe("standalone")
  for (const src of [
    ...manifest.icons.map((icon) => icon.src),
    "/icons/star-180.png",
  ]) {
    const icon = await fetch(new URL(src, e2e().origin))
    expect(icon.status, src).toBe(200)
    expect(icon.headers.get("content-type"), src).toContain("image/png")
  }
})

test("a fresh browser context opening start_url is signed in and the address bar drops the token", async ({
  browser,
  page,
}) => {
  await openApp(page)
  const href = await page
    .locator('link[rel="manifest"]')
    .getAttribute("href")
  const manifest = (await (
    await fetch(new URL(href ?? "", e2e().origin))
  ).json()) as { start_url: string }

  const context = await browser.newContext(iphone)
  try {
    const installed = await context.newPage()
    await installed.goto(new URL(manifest.start_url, e2e().origin).href)
    await expect(
      installed.getByRole("link", { name: /^sample/ }).first()
    ).toBeVisible()
    await expect(installed.getByText(PASTE)).toHaveCount(0)
    expect(installed.url()).not.toContain("t=")
  } finally {
    await context.close()
  }
})

test("a fresh browser context opening / with no token shows the token form", async ({
  browser,
}) => {
  const context = await browser.newContext(iphone)
  try {
    const bare = await context.newPage()
    await bare.goto(e2e().origin + "/")
    await expect(bare.getByText(PASTE).first()).toBeVisible()
  } finally {
    await context.close()
  }
})
