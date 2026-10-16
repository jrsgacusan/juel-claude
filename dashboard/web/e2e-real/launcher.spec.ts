import { spawnSync } from "node:child_process"
import { readFileSync } from "node:fs"
import { join } from "node:path"
import { e2e, expect, fakeLog, launchEnv, openApp, REPO_ROOT, test } from "./helpers.js"

const conf = () => JSON.parse(readFileSync(join(e2e().home, ".juel", "dashboard.json"), "utf8")) as { pid: number; port: number; token: string }
const log = () => readFileSync(join(e2e().home, ".juel", "dashboard.log"), "utf8")

test("the launcher started one server on 127.0.0.1 and opened its URL with the token", () => {
  const { url, origin } = e2e()
  const c = conf()
  expect(url).toBe(`http://127.0.0.1:${c.port}/?t=${c.token}`)
  expect(origin).toBe(`http://127.0.0.1:${c.port}`)
  expect(() => process.kill(c.pid, 0)).not.toThrow()
  expect(fakeLog("open.log").trim().split("\n")[0]).toBe(url)
  // A first run that builds also prints npm's own output, so only the last line is pinned.
  const out = readFileSync(join(e2e().root, "launch-1.out"), "utf8").trim().split("\n")
  expect(out.at(-1)).toBe(`STAR dashboard: ${url}`)
  expect(log().match(/started on 127\.0\.0\.1:\d+/g)).toHaveLength(1)
})

test("the URL opens the page, and the API refuses a request without the token", async ({ page }) => {
  await openApp(page)
  await expect(page.getByRole("link", { name: /^sample/ }).first()).toBeVisible()
  const res = await fetch(`${e2e().origin}/api/projects`)
  expect(res.status).toBe(401)
})

test("the server loads both modules and logs no module error", async () => {
  await expect.poll(log).toMatch(/\[slack\] slack check: 1 found/)
  const text = log()
  expect(text).toContain("module briefing loaded")
  expect(text).toContain("module slack loaded")
  expect(text).not.toMatch(/module \S+ skipped|uncaught|unhandled rejection|could not start|slack check failed/i)
})

test("a second run only opens the URL", () => {
  const before = conf()
  const r = spawnSync("sh", [join(REPO_ROOT, "skills/star/dashboard.sh")], { cwd: REPO_ROOT, env: launchEnv(), encoding: "utf8", timeout: 120_000 })
  expect(r.status).toBe(0)
  expect(r.stdout).toContain(`STAR dashboard: ${e2e().url}`)
  expect(r.stdout).not.toMatch(/building dashboard\/web/)
  expect(conf().pid).toBe(before.pid)
  expect(fakeLog("open.log").trim().split("\n")).toEqual([e2e().url, e2e().url])
  expect(log().match(/started on 127\.0\.0\.1:\d+/g)).toHaveLength(1)
})
