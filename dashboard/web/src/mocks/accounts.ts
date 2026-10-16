import { http, HttpResponse, type HttpHandler } from "msw/http"
import type { Account, AccountsState, AccountWindow } from "@/api/types"

const MIN = 60_000
const HOUR = 60 * MIN
const DAY = 24 * HOUR

/** Three made-up cswap accounts in the mockup's numbers, built from `now`. */
export function accountsFixture(now = Date.now()): AccountsState {
  const at = (ms: number) => new Date(now + ms).toISOString()
  const win = (usedPct: number, extra: Partial<AccountWindow> = {}): AccountWindow => ({
    usedPct,
    resetsAt: null,
    countdown: null,
    expectedPct: null,
    aheadOfPace: false,
    projectedExhaustionAt: null,
    willLastToReset: null,
    ...extra,
  })
  const account = (a: Partial<Account> & Pick<Account, "number" | "alias" | "email">): Account => ({
    isActive: false,
    isDisabled: false,
    status: "",
    fiveHour: null,
    sevenDay: null,
    scoped: [],
    loginExpiresAt: null,
    usageAgeSeconds: 60,
    isStale: false,
    ...a,
  })
  return {
    installed: true,
    auto: { state: "on", via: "cswap auto" },
    fetchedAt: at(-MIN),
    problem: "",
    accounts: [
      account({
        number: 1,
        alias: "main",
        email: "main@example.com",
        isActive: true,
        sevenDay: win(46, {
          expectedPct: 14.4,
          countdown: "5d 23h",
          resetsAt: at(5 * DAY + 23 * HOUR + 59 * MIN),
          aheadOfPace: true,
          projectedExhaustionAt: at(DAY + 4 * HOUR + 31 * MIN),
          willLastToReset: false,
        }),
        fiveHour: win(5, { countdown: "3h 59m", resetsAt: at(3 * HOUR + 59 * MIN) }),
        scoped: [{ name: "Fable", ...win(42) }],
        loginExpiresAt: at(27 * DAY),
      }),
      account({
        number: 2,
        alias: "work",
        email: "work@example.com",
        sevenDay: win(98, {
          expectedPct: 87.5,
          countdown: "20h 49m",
          resetsAt: at(20 * HOUR + 49 * MIN),
          aheadOfPace: true,
          projectedExhaustionAt: at(2 * HOUR),
          willLastToReset: false,
        }),
        fiveHour: win(0),
        scoped: [{ name: "Fable", ...win(53) }],
        loginExpiresAt: at(24 * DAY),
      }),
      account({
        number: 3,
        alias: "personal",
        email: "personal@example.com",
        sevenDay: win(96, {
          expectedPct: 56.6,
          countdown: "3d 0h",
          resetsAt: at(3 * DAY + 59 * MIN),
          aheadOfPace: true,
          projectedExhaustionAt: at(5 * HOUR),
          willLastToReset: false,
        }),
        fiveHour: win(3),
        scoped: [{ name: "Fable", ...win(73) }],
        loginExpiresAt: at(27 * DAY),
      }),
    ],
  }
}

// Routes added here: GET /api/accounts.
export const accountsHandlers: HttpHandler[] = [
  http.get("*/api/accounts", () => HttpResponse.json(accountsFixture())),
]
