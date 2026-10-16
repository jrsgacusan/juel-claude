// The dashboard server's API, kept by hand: the shape is spec D18's, as amended by STAR's API
// contract of 2026-10-16 and brief D11; once dashboard/server/ is merged, its routes are the source
// of truth.

export type ProjectState = "running" | "idle" | "stopped"
export type Project = {
  name: string
  repo: string
  state: ProjectState
  terminal: string | null
  lastTick: string | null
  needsYou: number | null
}
/** The quiet window, as the server sends it. */
export type QuietHours = { tz: string; start: string; end: string }
export type Overview = {
  resume: {
    state: string | null
    pools: string | null
    next: string | null
    lastTick: string | null
  }
  counts: Record<string, number>
  workers: {
    brief: [number, number]
    build: [number, number]
    babysit: [number, number]
  }
  gateDown: null | { since: string | null; why: string | null }
  away: string | null
  quietHours: QuietHours | null
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
  /** null when the queue item carries no time. */
  askedAt: string | null
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
  updated?: string | null
  title: string | null
  status: ItemStatus
  step: string | null
  prUrl: string | null
}
export type ProgressLine = { time: string | null; text: string }
export type ItemDetail = {
  row: ItemRow
  progress: ProgressLine[]
  criteria: string[]
  decisions: string[]
}
export type EvidenceSummary = {
  item: string
  title: string | null
  /** The release record's PR URL. */
  pr: string | null
  sha: string | null
  mergedAt: string | null
  goAt: string | null
  files: number
}
export type FileKind = "image" | "video" | "text"
export type EvidenceFile = { name: string; kind: FileKind; url: string }
/** The release record's fields the server sends; any of them may be missing. */
export type EvidenceRecord = {
  approval?: string
  ci?: string
  gate?: string
  go?: string
}
/** criterion null: the files are not mapped to criteria, one flat group. */
export type EvidenceGroup = {
  criterion: string | null
  files: EvidenceFile[]
}
export type EvidenceDetail = {
  item: string
  title: string | null
  /** The release record's PR URL. */
  pr: string | null
  sha: string | null
  mergedAt: string | null
  goAt: string | null
  /** go, gate, ci and approval feed the four check cards. */
  record: EvidenceRecord
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
  draft?: TicketDraft | null
}
export type StarEvent = ChangeEvent | BriefingEvent
export type SlackStatus = {
  connected: boolean
  lastCheck: string | null
  error: string | null
  model: string | null
  workspace?: string | null
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
/** GET /api/projects/:p/tracker. The server cannot tell whether a tracker's connector is
 * connected until a create runs (briefing brief D5). */
export type TrackerInfo = { tracker: Tracker | null }
export type CreateRequest = { tracker: Tracker }
export type CreateResponse =
  { ref: string; url: string | null } | { specPath: string; url: string | null }
export type ApiErrorBody = { error?: string; message?: string }
