// The dashboard server's API, kept by hand (spec D9): the Core API in star-dashboard-server.md,
// the briefing routes in star-dashboard-briefing.md and the Slack routes in star-dashboard-slack.md.
// Field names are the specs' own. Where a spec names a response only in words, the shape is spec
// D18's. A server that settles a shape differently is fixed here, and the fixtures that stop
// type-checking show what else moves.

export type ProjectState = "running" | "idle" | "stopped"
export type Project = {
  name: string
  repo: string
  state: ProjectState
  terminal: string | null
  lastTick: string | null
  needsYou: number
}
export type Overview = {
  resume: {
    state: string
    pools: string
    next: string
    lastTick: string | null
  }
  counts: Record<string, number>
  workers: {
    brief: [number, number]
    build: [number, number]
    babysit: [number, number]
  }
  gateDown: null | { since: string; why: string }
  away: string | boolean | null
  quietHours: string | null
}
export type LoopOption = { label: string; answer: string; recommended: boolean }
export type Loop = {
  id: string
  kind: string
  item: string
  title: string
  body: string[]
  options: LoopOption[]
  suggestion: string | null
  answer: string | null
  askedAt: string
}
export type AnswerRequest = { text: string }
export type AnswerResponse = { recorded: true; nudged: boolean }
export type ItemStatus =
  | "needs-you"
  | "stopped"
  | "building"
  | "in-review"
  | "briefing"
  | "queued"
  | "merged"
  | "dropped"
export type ItemRow = {
  item: string
  ref?: string | null
  state: string
  stage: string
  worktree: string
  pr: string
  head?: string | null
  branch?: string | null
  updated?: string | null
  title: string
  status: ItemStatus
  step: string | null
  prUrl: string | null
}
export type ProgressLine = { time: string; text: string }
export type ItemDetail = {
  row: ItemRow
  progress: ProgressLine[]
  criteria: string[]
  decisions: string[]
}
export type EvidenceSummary = {
  item: string
  title: string
  pr: string | null
  sha: string | null
  mergedAt: string
  goAt: string | null
  files: number
}
export type FileKind = "image" | "video" | "text"
export type EvidenceFile = { name: string; kind: FileKind; url: string }
export type EvidenceGroup = { criterion: string; files: EvidenceFile[] }
export type EvidenceDetail = {
  item: string
  title: string
  pr: string | null
  sha: string | null
  mergedAt: string
  goAt: string | null
  record: Record<string, string>
  groups: EvidenceGroup[]
}
export type DraftRequest = { text: string }
export type SearchResult = {
  group: string
  title: string
  sub: string
  ref: string
  project: string
  route: string
}
export type ChangeWhat =
  | "loops"
  | "ledger"
  | "progress"
  | "evidence"
  | "drafts"
  | "slack"
  | "briefings"
export type ChangeEvent = { type: "change"; project?: string; what: ChangeWhat }
export type BriefingTurn = {
  who: "me" | "agent"
  text: string
  files?: string[]
  done?: boolean
}
export type BriefingEvent = {
  type: "briefing"
  project: string
  id: string
  turn?: BriefingTurn
  error?: string
}
export type StarEvent = ChangeEvent | BriefingEvent
export type SlackStatus = {
  connected: boolean
  lastCheck: string | null
  error: string | null
  model: string | null
}
export type RoutedMessage = {
  id: string
  project: string
  from: string
  channel: string
  text: string
  permalink: string
  thread: string[]
  draftPath: string | null
  loopId: string | null
}
export type UnroutedMessage = {
  id: string
  from: string
  channel: string
  text: string
  permalink: string
}
export type SlackState = {
  status: SlackStatus
  routed: RoutedMessage[]
  unrouted: UnroutedMessage[]
}
export type RouteRequest = { project: string }
export type BriefingSummary = {
  id: string
  title: string
  updatedAt: string
  ref: string | null
}
export type TicketDraft = {
  title: string
  description: string
  criteria: string[]
  outOfScope: string[]
}
export type Briefing = {
  turns: BriefingTurn[]
  draft: TicketDraft | null
  busy: boolean
}
export type NewBriefingResponse = { id: string }
export type MessageRequest = { text: string }
export type Tracker = "synapse" | "linear" | "jira" | "github" | "none"
export type TrackerInfo = {
  tracker: Tracker | null
  connected?: Partial<Record<Tracker, boolean>>
}
export type CreateRequest = { tracker: Tracker }
export type CreateResponse = {
  ref?: string
  specPath?: string
  url: string | null
}
export type ApiErrorBody = { error?: string; message?: string }
