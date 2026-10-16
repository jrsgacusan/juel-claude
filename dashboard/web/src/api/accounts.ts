import { useQuery } from "@tanstack/react-query"
import { agoText, clock, isValidTime } from "@/lib/format"
import { apiJson } from "./client"
import { paths } from "./paths"
import { keys } from "./queries"
import type { Account, AccountsState, AccountWindow } from "./types"

/** The share of a window at which cswap's auto-switch skips an account (hooks/cswap.ts). */
export const NEAR_LIMIT = 90

const DAY = 86_400_000

export const useAccounts = () =>
  useQuery({
    queryKey: keys.accounts,
    queryFn: () => apiJson<AccountsState>(paths.accounts()),
    refetchInterval: 60_000,
  })

export function leftOf(w: AccountWindow | null): number | null {
  if (!w) return null
  return Math.min(100, Math.max(0, Math.round(100 - w.usedPct)))
}

export const isSkipped = (a: Account): boolean =>
  (a.sevenDay?.usedPct ?? 0) >= NEAR_LIMIT ||
  (a.fiveHour?.usedPct ?? 0) >= NEAR_LIMIT

export const activeOf = (s: AccountsState): Account | null =>
  s.accounts.find((a) => a.isActive) ?? null

export function autoText(auto: AccountsState["auto"]): string {
  const via = auto.via ? ` (${auto.via})` : ""
  if (auto.state === "on") return `on${via}`
  if (auto.state === "dry run") return `in dry run${via}`
  return "off"
}

const monthDay = (d: Date) =>
  new Intl.DateTimeFormat("en-US", { month: "short", day: "numeric" }).format(d)
const weekday = (d: Date) =>
  new Intl.DateTimeFormat("en-US", { weekday: "short" }).format(d)

export function resetText(w: AccountWindow, now = Date.now()): string {
  if (isValidTime(w.resetsAt) && Date.parse(w.resetsAt) - now >= DAY) {
    const d = new Date(w.resetsAt)
    return `resets ${weekday(d)} ${monthDay(d)}, ${clock(w.resetsAt)}`
  }
  return w.countdown ? `resets in ${w.countdown}` : ""
}

export const fiveHourText = (w: AccountWindow): string =>
  `${leftOf(w)}% left${w.countdown ? ` · resets in ${w.countdown}` : ""}`

export function popoverLine(a: Account): string {
  const parts: string[] = []
  if (a.sevenDay?.countdown) parts.push(`Week resets in ${a.sevenDay.countdown}`)
  if (isSkipped(a)) parts.push("auto-switch skips it")
  else if (a.fiveHour) parts.push(`5-hour window ${leftOf(a.fiveHour)}% left`)
  return parts.join(" · ")
}

export function paceNote(a: Account): string | null {
  const w = a.sevenDay
  if (
    !w ||
    !w.aheadOfPace ||
    w.willLastToReset !== false ||
    !isValidTime(w.projectedExhaustionAt)
  )
    return null
  const d = new Date(w.projectedExhaustionAt)
  return `Ahead of pace. At this rate it runs out around ${weekday(d)} ${clock(w.projectedExhaustionAt)}, before the reset.`
}

export function loginText(
  a: Account,
  now = Date.now()
): { text: string; expired: boolean } | null {
  if (!isValidTime(a.loginExpiresAt)) return null
  const expired = Date.parse(a.loginExpiresAt) <= now
  const day = monthDay(new Date(a.loginExpiresAt))
  return {
    text: expired ? `Login expired ${day}` : `Login good until ${day}`,
    expired,
  }
}

export function problemText(s: AccountsState): string | null {
  if (!s.problem) return null
  const shown = s.fetchedAt
    ? ` Showing the reading from ${agoText(s.fetchedAt)}.`
    : ""
  return `The last read failed: ${s.problem}.${shown}`
}
