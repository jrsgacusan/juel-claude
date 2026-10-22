export const PAGES = [
  "needs",
  "progress",
  "chat",
  "briefing",
  "evidence",
  "accounts",
  "more",
] as const
export type Page = (typeof PAGES)[number]
export const PAGE_LABELS: Record<Page, string> = {
  needs: "Needs you",
  progress: "Progress",
  chat: "Chat",
  briefing: "Briefing",
  evidence: "Evidence",
  accounts: "Accounts",
  more: "More",
}
export const isPage = (value: unknown): value is Page =>
  typeof value === "string" && (PAGES as readonly string[]).includes(value)
export function projectPath(
  project: string,
  page: Page,
  search?: Record<string, string>
): string {
  const query = search ? new URLSearchParams(search).toString() : ""
  return `/${encodeURIComponent(project)}/${page}${query ? `?${query}` : ""}`
}

/** The combined Needs you page, filtered to one project when given, and opened on one loop. */
export function needsPath(project?: string, loop?: string): string {
  const q = new URLSearchParams()
  if (project) q.set("project", project)
  if (loop) q.set("loop", loop)
  const query = q.toString()
  return `/needs${query ? `?${query}` : ""}`
}
