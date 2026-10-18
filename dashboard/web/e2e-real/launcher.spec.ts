import { readFileSync } from "node:fs"
import { dashboardLog, logProblems, readConfig, runLauncher } from "./stack.js"
import { e2e, expect, fakeLog, openApp, test } from "./helpers.js"

test("the launcher started one server on 127.0.0.1 and opened its URL with the token", () => {
  const config = readConfig(e2e().home)
  expect(config).not.toBeNull()
  if (!config) throw new Error("dashboard.json missing")
  const url = `http://127.0.0.1:${config.port}/?t=${config.token}`
  expect(e2e().url).toBe(url)
  expect(() => process.kill(config.pid, 0)).not.toThrow()
  expect(fakeLog("open.log").trim().split("\n")[0]).toBe(url)
  // A first run that builds also prints npm's own output, so only the last line is pinned,
  // past the launcher's own "dashboard.sh: " lines: the fake tailscale serves nothing, so the
  // --tailnet hint follows the URL (#152).
  const out = readFileSync(`${e2e().root}/launch-1.out`, "utf8")
    .trim()
    .split("\n")
  expect(out.filter((line) => !line.startsWith("dashboard.sh: ")).at(-1)).toBe(
    `STAR dashboard: ${url}`
  )
  expect(out).toContain(
    "dashboard.sh: to open it from your phone, run /juel:star dashboard --tailnet (tailscale serve, inside your tailnet only)"
  )
  expect(
    dashboardLog(e2e().home).match(/started on 127\.0\.0\.1:\d+/g)
  ).toHaveLength(1)
})

test("the URL opens the page, and the API refuses a request without the token", async ({
  page,
}) => {
  await openApp(page)
  await expect(
    page.getByRole("link", { name: /^sample/ }).first()
  ).toBeVisible()
  const res = await fetch(`${e2e().origin}/api/projects`)
  expect(res.status).toBe(401)
})

test("the server loads both modules and logs no module error", async () => {
  await expect
    .poll(() => dashboardLog(e2e().home))
    .toMatch(/\[slack\] slack check: 2 found, 1 routed, 1 unrouted/)
  const text = dashboardLog(e2e().home)
  expect(text).toContain("module briefing loaded")
  expect(text).toContain("module slack loaded")
  expect(logProblems(e2e().home)).toEqual([])
})

test("a second run only opens the URL", () => {
  const before = readConfig(e2e().home)
  if (!before) throw new Error("dashboard.json missing")
  const r = runLauncher(e2e().root, 120_000)
  expect(r.status, `${r.stdout}\n${r.stderr}`).toBe(0)
  expect(r.stdout).toContain(`STAR dashboard: ${e2e().url}`)
  expect(r.stdout).not.toMatch(/building dashboard\/web/)
  const after = readConfig(e2e().home)
  expect(after?.pid).toBe(before.pid)
  expect(fakeLog("open.log").trim().split("\n")).toEqual([e2e().url, e2e().url])
  expect(
    dashboardLog(e2e().home).match(/started on 127\.0\.0\.1:\d+/g)
  ).toHaveLength(1)
})

test("a new page keeps the token, and a browser without it can paste it", async ({
  page,
  browser,
}) => {
  await openApp(page)
  const again = await page.context().newPage()
  await again.goto(`${e2e().origin}/sample/needs`)
  await expect(
    again.getByRole("link", { name: /^sample/ }).first()
  ).toBeVisible()
  await expect(again.getByLabel("Dashboard token")).toHaveCount(0)
  await again.close()
  const fresh = await browser.newContext()
  try {
    const other = await fresh.newPage()
    await other.goto(`${e2e().origin}/sample/needs`)
    const field = other.getByLabel("Dashboard token")
    await field.fill("0".repeat(32))
    await other.getByRole("button", { name: "Use this token" }).click()
    await expect(
      other.getByText(
        "The dashboard server refused that token. Paste the whole link /juel:star dashboard printed, so nothing is cut off."
      )
    ).toBeVisible()
    await field.fill(e2e().url)
    await other.getByRole("button", { name: "Use this token" }).click()
    await expect(
      other.getByRole("link", { name: /^sample/ }).first()
    ).toBeVisible()
  } finally {
    await fresh.close()
  }
})
