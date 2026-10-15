import type { ItemRow, ItemStatus, ProjectState } from "@/api/types"

// Color only for state (brief): amber needs you, blue running, green done, red stopped.
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

const PROGRESS_LINE = /^\d{4}-\d{2}-\d{2}T\S+\s+\S+\s+(.*)$/

/** The text of a progress line "<iso> <step> <text>"; other text as is. */
export function stepText(step: string | null | undefined): string {
  if (!step) return ""
  const line = step.trim()
  return PROGRESS_LINE.exec(line)?.[1] ?? line
}

/** "#209" from the ledger's pr cell or the PR URL; null when there is no PR. */
export function prLabel(row: Pick<ItemRow, "pr" | "prUrl">): string | null {
  const raw = row.pr && row.pr !== "-" ? row.pr : (row.prUrl ?? "")
  const number = /(\d+)\/?$/.exec(raw.trim())?.[1]
  return number ? `#${number}` : null
}
