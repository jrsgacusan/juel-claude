const e = encodeURIComponent
const project = (p: string) => `/api/projects/${e(p)}`

export const paths = {
  projects: () => "/api/projects",
  overview: (p: string) => `${project(p)}/overview`,
  loops: (p: string) => `${project(p)}/loops`,
  answer: (p: string, id: string) => `${project(p)}/loops/${e(id)}/answer`,
  items: (p: string) => `${project(p)}/items`,
  item: (p: string, item: string) => `${project(p)}/items/${e(item)}`,
  evidence: (p: string) => `${project(p)}/evidence`,
  evidenceItem: (p: string, item: string) =>
    `${project(p)}/evidence/${e(item)}`,
  file: (p: string, path: string) => `${project(p)}/file?path=${e(path)}`,
  draft: (p: string, name: string) => `${project(p)}/drafts/${e(name)}`,
  search: ({
    q,
    project: p,
    all,
  }: {
    q: string
    project: string
    all: boolean
  }) => {
    const params = new URLSearchParams({ q, project: p })
    if (all) params.set("all", "1")
    return `/api/search?${params.toString()}`
  },
  events: () => "/api/events",
  slack: () => "/api/slack",
  slackRoute: (id: string) => `/api/slack/${e(id)}/route`,
  slackCheck: () => "/api/slack/check",
  slackPaused: () => "/api/slack/paused",
  briefings: (p: string) => `${project(p)}/briefings`,
  briefing: (p: string, id: string) => `${project(p)}/briefings/${e(id)}`,
  briefingMessages: (p: string, id: string) =>
    `${project(p)}/briefings/${e(id)}/messages`,
  briefingCreate: (p: string, id: string) =>
    `${project(p)}/briefings/${e(id)}/create`,
  tracker: (p: string) => `${project(p)}/tracker`,
  chat: (p: string, before?: string) =>
    `${project(p)}/chat${before === undefined ? "" : `?before=${e(before)}`}`,
  away: (p: string) => `${project(p)}/away`,
  slackRedraft: (p: string) => `${project(p)}/slack/redraft`,
  accounts: () => "/api/accounts",
}
