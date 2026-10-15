import { describe, expect, it } from "vitest"
import { projectStateOf, statusOf, stepText } from "./status"

describe("status", () => {
  it("strips the time and the step token the server leaves on a progress line", () => {
    expect(
      stepText("2026-10-16T10:52:00Z gate-r2 Codex gate, round 2 of 3")
    ).toBe("Codex gate, round 2 of 3")
    expect(stepText("gate-r2 Codex gate, round 2 of 3")).toBe(
      "Codex gate, round 2 of 3"
    )
    expect(stepText("executor Codex running on luna")).toBe(
      "Codex running on luna"
    )
    expect(stepText("Executor writing the code")).toBe(
      "Executor writing the code"
    )
  })

  it("falls back for an unknown status or project state", () => {
    expect(statusOf("weird")).toEqual({ label: "weird", tone: "muted" })
    expect(projectStateOf("weird")).toMatchObject({
      label: "weird",
      tone: "muted",
    })
  })
})
