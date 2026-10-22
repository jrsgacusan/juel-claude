import type { ItemRow } from "@/api/types"

export const STAGES = ["Brief", "Build", "Gate", "Review", "Merge"] as const
export type StageName = (typeof STAGES)[number]
export type RailTone = "run" | "wait" | "stop" | "muted"
/** done: how many leading segments are done; current: the index in progress, or null. */
export type Rail = { done: number; current: number | null; tone: RailTone }

/** The muted "still to come" line for each stage, in the item sheet. */
export const UPCOMING: Record<Exclude<StageName, "Brief">, string> = {
  Build: "Build: plan, code and live checks",
  Gate: "Codex gate on the draft PR",
  Review: "Hosted review or a teammate's approval",
  Merge: "STAR merges it once every gate holds",
}

const BRIEF = 0
const BUILD = 1
const GATE = 2
const REVIEW = 3
const MERGE = 4

/** The step token, after the optional ISO time: gate-r<n>, post-pass and ready all mean the draft PR is at its gate. */
const GATE_STEP = /^(?:\d{4}-\d{2}-\d{2}T\S+\s+)?(?:gate-r\d+|post-pass|ready)(?:\s|$)/

function buildIndex(row: Pick<ItemRow, "pr" | "step">): number {
  const hasPr = !!row.pr && row.pr !== "-"
  return hasPr || GATE_STEP.test((row.step ?? "").trim()) ? GATE : BUILD
}

function toneOf(status: string): RailTone {
  if (status === "needs-you") return "wait"
  if (status === "stopped") return "stop"
  return "run"
}

export function railOf(
  row: Pick<ItemRow, "state" | "stage" | "pr" | "step" | "counters" | "status">
): Rail | null {
  if (row.stage === "post" || row.state === "post-queued" || row.state === "posting") return null
  const at = (index: number): Rail => ({ done: index, current: index, tone: toneOf(row.status) })
  switch (row.state) {
    case "inbox":
    case "briefing":
      return at(BRIEF)
    case "queued":
      return { done: 1, current: null, tone: toneOf(row.status) }
    case "building":
      return at(buildIndex(row))
    case "babysit-queued":
    case "babysitting":
      return at(REVIEW)
    case "verifying":
      return at(MERGE)
    case "done":
      return { done: 5, current: null, tone: toneOf(row.status) }
    case "dropped":
      return { done: 0, current: null, tone: "muted" }
    case "needs-you":
    case "set-aside":
      if (row.stage === "brief") return at(BRIEF)
      if (row.stage === "babysit") return at(/\breached=verifying\b/.test(row.counters ?? "") ? MERGE : REVIEW)
      return at(buildIndex(row))
    default:
      return null
  }
}

export function railLabel(rail: Rail): string {
  if (rail.done >= STAGES.length) return "Merged"
  if (rail.tone === "muted" && rail.done === 0) return "Dropped"
  if (rail.current === null) return `${STAGES[rail.done - 1] ?? STAGES[0]} done, waiting for ${STAGES[rail.done] ?? STAGES[0]}`
  const base = `Stage ${rail.current + 1} of ${STAGES.length}, ${STAGES[rail.current]}`
  if (rail.tone === "wait") return `${base}, waiting on you`
  if (rail.tone === "stop") return `${base}, set aside`
  return base
}
