const MINUTE = 60_000
const HOUR = 60 * MINUTE
const DAY = 24 * HOUR

export const isValidTime = (iso: string | null | undefined): iso is string =>
  typeof iso === "string" && Number.isFinite(Date.parse(iso))

const since = (iso: string | null | undefined, now: number): number | null => {
  if (!iso) return null
  const ms = now - Date.parse(iso)
  return Number.isFinite(ms) ? Math.max(0, ms) : null
}

/** "now", "12m", "2h", "3d" */
export function age(iso: string | null | undefined, now = Date.now()): string {
  const ms = since(iso, now)
  if (ms === null) return ""
  if (ms < MINUTE) return "now"
  if (ms < HOUR) return `${Math.floor(ms / MINUTE)}m`
  if (ms < DAY) return `${Math.floor(ms / HOUR)}h`
  return `${Math.floor(ms / DAY)}d`
}

/** "just now", "12 min ago", "2 h ago", "1 day ago", "3 days ago" */
export function agoText(
  iso: string | null | undefined,
  now = Date.now()
): string {
  const ms = since(iso, now)
  return ms === null ? "" : agoFromMs(ms)
}

/** agoText for an age already in milliseconds: no clock is read, so it is safe in render. */
export function agoFromMs(ms: number): string {
  if (ms < MINUTE) return "just now"
  if (ms < HOUR) return `${Math.floor(ms / MINUTE)} min ago`
  if (ms < DAY) return `${Math.floor(ms / HOUR)} h ago`
  const days = Math.floor(ms / DAY)
  return `${days} ${days === 1 ? "day" : "days"} ago`
}

const startOfDay = (d: Date) =>
  new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()

/** "Today", "Yesterday", else "Oct 14" (local time). */
export function dayLabel(
  iso: string | null | undefined,
  now = new Date()
): string {
  if (!isValidTime(iso)) return ""
  const d = new Date(iso)
  const diff = Math.round((startOfDay(now) - startOfDay(d)) / DAY)
  if (diff === 0) return "Today"
  if (diff === 1) return "Yesterday"
  return new Intl.DateTimeFormat("en-US", {
    month: "short",
    day: "numeric",
  }).format(d)
}

/** "09:12" (local, 24 h) */
export const clock = (iso: string | null | undefined): string => {
  if (!isValidTime(iso)) return ""
  return new Intl.DateTimeFormat("en-GB", {
    hour: "2-digit",
    minute: "2-digit",
  }).format(new Date(iso))
}

/** "Oct 15, 22:40" */
export const dateTime = (iso: string | null | undefined): string => {
  if (!isValidTime(iso)) return ""
  return `${new Intl.DateTimeFormat("en-US", { month: "short", day: "numeric" }).format(new Date(iso))}, ${clock(iso)}`
}

/** The time of a Slack message id "<channelId>-<ts>", or null. */
export function slackTime(id: string): string | null {
  const ts = Number(id.slice(id.lastIndexOf("-") + 1))
  return id.includes("-") && Number.isFinite(ts) && ts > 0
    ? new Date(ts * 1000).toISOString()
    : null
}
