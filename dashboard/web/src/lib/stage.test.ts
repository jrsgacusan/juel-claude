import { describe, expect, it } from "vitest"
import type { ItemRow } from "@/api/types"
import { railLabel, railOf, UPCOMING } from "@/lib/stage"

const row = (over: Partial<ItemRow>): ItemRow => ({
  item: "SPH-1",
  state: "building",
  stage: "build",
  worktree: "-",
  pr: "-",
  title: "t",
  status: "building",
  step: null,
  prUrl: null,
  ...over,
})

describe("railOf", () => {
  const cases: [string, Partial<ItemRow>, unknown][] = [
    ["briefing", { state: "briefing", status: "briefing" as ItemRow["status"] }, { done: 0, current: 0, tone: "run" }],
    ["queued", { state: "queued", status: "queued" as ItemRow["status"] }, { done: 1, current: null, tone: "run" }],
    ["building, no PR", { state: "building", pr: "-", step: "2026-10-21T22:20:00Z executor writing the code" }, { done: 1, current: 1, tone: "run" }],
    ["building with a PR", { state: "building", pr: "https://github.com/o/r/pull/214" }, { done: 2, current: 2, tone: "run" }],
    ["building at gate-r2", { state: "building", pr: "-", step: "2026-10-21T23:06:00Z gate-r2 codex gate" }, { done: 2, current: 2, tone: "run" }],
    ["babysitting", { state: "babysitting", status: "in-review" as ItemRow["status"] }, { done: 3, current: 3, tone: "run" }],
    ["verifying", { state: "verifying" }, { done: 4, current: 4, tone: "run" }],
    ["done", { state: "done", status: "merged" as ItemRow["status"] }, { done: 5, current: null, tone: "run" }],
    ["needs-you at brief", { state: "needs-you", stage: "brief", status: "needs-you" }, { done: 0, current: 0, tone: "wait" }],
    ["needs-you at build", { state: "needs-you", stage: "build", pr: "-", status: "needs-you" }, { done: 1, current: 1, tone: "wait" }],
    ["building but needs-you", { state: "building", pr: "-", status: "needs-you" }, { done: 1, current: 1, tone: "wait" }],
    ["set aside past verifying", { state: "set-aside", stage: "babysit", counters: "tries=3 reached=verifying", status: "stopped" }, { done: 4, current: 4, tone: "stop" }],
    ["set aside in review", { state: "set-aside", stage: "babysit", counters: "tries=3", status: "stopped" }, { done: 3, current: 3, tone: "stop" }],
    ["dropped", { state: "dropped", status: "stopped" }, { done: 0, current: null, tone: "muted" }],
    ["posting", { state: "posting", stage: "post" }, null],
    ["done report", { state: "done", stage: "post" }, null],
  ]
  for (const [name, over, expected] of cases)
    it(name, () => expect(railOf(row(over))).toEqual(expected))
})

describe("railLabel", () => {
  it("names the stage, and who it waits on", () => {
    expect(railLabel({ done: 2, current: 2, tone: "run" })).toBe("Stage 3 of 5, Gate")
    expect(railLabel({ done: 1, current: 1, tone: "wait" })).toBe("Stage 2 of 5, Build, waiting on you")
    expect(railLabel({ done: 3, current: 3, tone: "stop" })).toBe("Stage 4 of 5, Review, set aside")
  })
  it("has words for the rails with no current segment", () => {
    expect(railLabel({ done: 1, current: null, tone: "run" })).toBe("Brief done, waiting for Build")
    expect(railLabel({ done: 5, current: null, tone: "run" })).toBe("Merged")
    expect(railLabel({ done: 0, current: null, tone: "muted" })).toBe("Dropped")
  })
})

it("UPCOMING is the sheet's still-to-come lines", () => {
  expect(UPCOMING).toEqual({
    Build: "Build: plan, code and live checks",
    Gate: "Codex gate on the draft PR",
    Review: "Hosted review or a teammate's approval",
    Merge: "STAR merges it once every gate holds",
  })
})
