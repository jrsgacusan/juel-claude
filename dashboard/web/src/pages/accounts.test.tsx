import { screen, within } from "@testing-library/react"
import { http, HttpResponse } from "msw/http"
import { afterEach, describe, expect, it, vi } from "vitest"
import { autoText, isSkipped, leftOf, resetText } from "@/api/accounts"
import type { Account, AccountsState } from "@/api/types"
import { accountsFixture } from "@/mocks/accounts"
import { server } from "@/mocks/node"
import { renderApp } from "@/test/render"

const NOW = new Date(2026, 9, 17, 2, 0) // Sat Oct 17 2026, 02:00 local
const DAY = 86_400_000
const freeze = () => {
  vi.useFakeTimers({ toFake: ["Date"] })
  vi.setSystemTime(NOW)
}
const serve = (state: () => AccountsState) =>
  server.use(http.get("*/api/accounts", () => HttpResponse.json(state())))
const patched = (alias: string, patch: Partial<Account>) => () => {
  const s = accountsFixture()
  s.accounts = s.accounts.map((a) => (a.alias === alias ? { ...a, ...patch } : a))
  return s
}
const card = (name: string) => screen.getByRole("article", { name })

afterEach(() => vi.useRealTimers())

describe("the Accounts page", () => {
  it("shows one card per account: the week left, every limit, pace and login", async () => {
    freeze()
    renderApp("/sphere-app/accounts")
    expect(await screen.findByRole("heading", { level: 1, name: "Claude accounts" })).toBeInTheDocument()
    expect(
      await screen.findByText("From cswap · auto-switch on (cswap auto), moves at 90% · refreshed 1 min ago")
    ).toBeInTheDocument()
    const main = card("main")
    for (const text of ["Active", "main@example.com", "54%", "of the week left", "resets Fri Oct 23, 01:59",
      "95% left · resets in 3h 59m", "Fable", "58% left", "Login good until Nov 13",
      "Ahead of pace. At this rate it runs out around Sun 06:31, before the reset."])
      expect(within(main).getByText(text)).toBeInTheDocument()
    expect(within(main).getByRole("meter", { name: "Week" }).querySelector("[data-slot=pace-tick]")).not.toBeNull()
    const work = card("work")
    expect(within(work).getByText("2%")).toHaveClass("text-stop-fg")
    for (const text of ["resets in 20h 49m", "100% left", "47% left", "Login good until Nov 10",
      "Nearly out. Auto-switch skips it until the reset."])
      expect(within(work).getByText(text)).toBeInTheDocument()
    expect(within(work).queryByText(/Ahead of pace/)).not.toBeInTheDocument()
    expect(within(work).queryByText("Active")).not.toBeInTheDocument()
    const personal = card("personal")
    for (const text of ["resets Tue Oct 20, 02:59", "97% left", "27% left"])
      expect(within(personal).getByText(text)).toBeInTheDocument()
  })

  it("marks a disabled account, an expired login and a stale reading", async () => {
    freeze()
    const loginExpiresAt = new Date(NOW.getTime() - 2 * DAY).toISOString()
    serve(patched("personal", { isDisabled: true, loginExpiresAt, isStale: true, usageAgeSeconds: 720 }))
    renderApp("/sphere-app/accounts")
    const personal = await screen.findByRole("article", { name: "personal" })
    expect(within(personal).getByText("Disabled")).toBeInTheDocument()
    expect(within(personal).getByText("Login expired Oct 15")).toHaveClass("text-stop-fg")
    expect(within(personal).getByText("Last good reading, 12 min ago")).toBeInTheDocument()
  })

  it("says so when an account has no week reading", async () => {
    serve(patched("main", { sevenDay: null, status: "unavailable" }))
    renderApp("/sphere-app/accounts")
    const main = await screen.findByRole("article", { name: "main" })
    expect(within(main).getByText("No reading")).toBeInTheDocument()
    expect(within(main).getByText("Usage reading: unavailable")).toBeInTheDocument()
    expect(within(main).queryByRole("meter", { name: "Week" })).not.toBeInTheDocument()
  })

  it("keeps the last reading and says why the read failed", async () => {
    const fetchedAt = new Date(Date.now() - 12 * 60_000).toISOString()
    serve(() => ({ ...accountsFixture(), fetchedAt, problem: "cswap: timed out after 20 s" }))
    renderApp("/sphere-app/accounts")
    expect(
      await screen.findByText("The last read failed: cswap: timed out after 20 s. Showing the reading from 12 min ago.")
    ).toBeInTheDocument()
    expect(screen.getAllByRole("article")).toHaveLength(3)
  })

  it("says when cswap is missing or lists no accounts", async () => {
    const empty = { auto: { state: "off" as const, via: "" }, fetchedAt: null, problem: "", accounts: [] }
    serve(() => ({ installed: false, ...empty }))
    const first = renderApp("/sphere-app/accounts")
    expect(await screen.findByText("cswap is not installed on this Mac.")).toBeInTheDocument()
    expect(screen.getByText("The dashboard reads your Claude accounts from cswap (claude-swap). Install it to see them here.")).toBeInTheDocument()
    first.unmount()
    serve(() => ({ installed: true, ...empty }))
    renderApp("/sphere-app/accounts")
    expect(await screen.findByText("cswap lists no accounts.")).toBeInTheDocument()
    expect(screen.getByText("Accounts you add to cswap show here.")).toBeInTheDocument()
  })

  it("says it could not load the accounts", async () => {
    server.use(http.get("*/api/accounts", () => HttpResponse.json({ error: "cswap list --json printed no JSON" }, { status: 502 })))
    renderApp("/sphere-app/accounts")
    expect(await screen.findByText("Couldn't load the accounts.")).toBeInTheDocument()
    expect(screen.getByText("cswap list --json printed no JSON")).toBeInTheDocument()
  })
})

describe("account readings", () => {
  const [main, work] = accountsFixture(NOW.getTime()).accounts as [Account, Account, Account]
  const week = main.sevenDay!

  it("names the auto-switch state", () => {
    expect(autoText({ state: "on", via: "menu bar" })).toBe("on (menu bar)")
    expect(autoText({ state: "dry run", via: "cswap auto" })).toBe("in dry run (cswap auto)")
    expect(autoText({ state: "off", via: "" })).toBe("off")
  })

  it("counts what is left, and skips an account at 90% of either window", () => {
    expect(accountsFixture(NOW.getTime()).accounts.map((a) => leftOf(a.sevenDay))).toEqual([54, 2, 4])
    expect(leftOf(null)).toBeNull()
    expect(leftOf({ ...week, usedPct: 100.4 })).toBe(0)
    expect(isSkipped(main)).toBe(false)
    expect(isSkipped(work)).toBe(true)
    expect(isSkipped({ ...main, sevenDay: { ...week, usedPct: 89 } })).toBe(false)
    expect(isSkipped({ ...main, fiveHour: { ...week, usedPct: 90 } })).toBe(true)
  })

  it("says when a window resets: a countdown under a day, else the day and time", () => {
    const now = NOW.getTime()
    expect(resetText(week, now)).toBe("resets Fri Oct 23, 01:59")
    expect(resetText(work.sevenDay!, now)).toBe("resets in 20h 49m")
    expect(resetText({ ...week, resetsAt: null }, now)).toBe("resets in 5d 23h")
    expect(resetText({ ...week, resetsAt: null, countdown: null }, now)).toBe("")
  })
})
