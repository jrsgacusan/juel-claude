export const PAGES = [
  "needs",
  "progress",
  "chat",
  "slack",
  "briefing",
  "evidence",
  "accounts",
] as const
export type Page = (typeof PAGES)[number]
export const PAGE_LABELS: Record<Page, string> = {
  needs: "Needs you",
  progress: "Progress",
  chat: "Chat",
  slack: "Slack replies",
  briefing: "Briefing",
  evidence: "Evidence",
  accounts: "Accounts",
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
