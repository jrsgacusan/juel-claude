const e = encodeURIComponent
const project = (p: string) => `/api/projects/${e(p)}`

export const paths = {
  projects: () => "/api/projects",
  overview: (p: string) => `${project(p)}/overview`,
  allLoops: () => "/api/loops",
  loops: (p: string) => `${project(p)}/loops`,
  answer: (p: string, id: string) => `${project(p)}/loops/${e(id)}/answer`,
  items: (p: string) => `${project(p)}/items`,
  item: (p: string, item: string) => `${project(p)}/items/${e(item)}`,
  evidence: (p: string) => `${project(p)}/evidence`,
  evidenceItem: (p: string, item: string) =>
    `${project(p)}/evidence/${e(item)}`,
  file: (p: string, path: string) => `${project(p)}/file?path=${e(path)}`,
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
  accounts: () => "/api/accounts",
}
