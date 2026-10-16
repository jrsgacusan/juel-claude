import type { ItemRow, ItemStatus, ProjectState } from "@/api/types"

// Color only for state (brief): amber needs you, blue running, green done, red stopped. Blue marks
// an item at work (Building, In review); a running STAR project shows the green pulsing dot, as in
// the mock.
export type Tone = "wait" | "run" | "done" | "stop" | "muted"

export const STATUS: Record<ItemStatus, { label: string; tone: Tone }> = {
  "needs-you": { label: "Needs you", tone: "wait" },
  stopped: { label: "Stopped", tone: "stop" },
  building: { label: "Building", tone: "run" },
  "in-review": { label: "In review", tone: "run" },
  briefing: { label: "Briefing", tone: "muted" },
  queued: { label: "Queued", tone: "muted" },
  merged: { label: "Merged", tone: "done" },
  dropped: { label: "Dropped", tone: "muted" },
}

export type ProgressTab = "all" | "needs" | "running" | "merged"

export const TAB_OF: Record<ItemStatus, Exclude<ProgressTab, "all"> | null> = {
  "needs-you": "needs",
  stopped: "needs",
  building: "running",
  "in-review": "running",
  briefing: "running",
  queued: "running",
  merged: "merged",
  dropped: null,
}

export const PROJECT_STATE: Record<
  ProjectState,
  { label: string; tone: Tone; pulse: boolean }
> = {
  running: { label: "Running", tone: "done", pulse: true },
  idle: { label: "Idle", tone: "muted", pulse: false },
  stopped: { label: "Stopped", tone: "stop", pulse: false },
}

const STEP_TOKEN =
  /^(?:phase[1-8]|executor|live-check|regression-gate|gate-r\d+|post-pass|ready|sync|report|update)\s+/
const ISO_PREFIX = /^\d{4}-\d{2}-\d{2}T\S+\s+/

/** A progress line's text, without its time and step token when the line carries them. */
export function stepText(step: string | null | undefined): string {
  if (!step) return ""
  return step.trim().replace(ISO_PREFIX, "").replace(STEP_TOKEN, "")
}

export const statusOf = (status: string): { label: string; tone: Tone } =>
  STATUS[status as ItemStatus] ?? { label: status, tone: "muted" }

export const projectStateOf = (
  state: string
): { label: string; tone: Tone; pulse: boolean } =>
  PROJECT_STATE[state as ProjectState] ?? {
    label: state,
    tone: "muted",
    pulse: false,
  }

/** "#209" from the ledger's pr cell or the PR URL; null when there is no PR. */
export function prLabel(row: Pick<ItemRow, "pr" | "prUrl">): string | null {
  const raw = row.pr && row.pr !== "-" ? row.pr : (row.prUrl ?? "")
  const number = /(\d+)\/?$/.exec(raw.trim())?.[1]
  return number ? `#${number}` : null
}
