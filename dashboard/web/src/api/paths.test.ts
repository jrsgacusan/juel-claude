import { describe, expect, it } from "vitest"
import { paths } from "./paths"

describe("the API paths", () => {
  it("names the chat, away, redraft and accounts routes (I-6, I-7, I-9, I-10)", () => {
    expect(paths.chat("sphere app")).toBe("/api/projects/sphere%20app/chat")
    expect(paths.chat("sphere-app", "20261017T101500Z-me-a1b2")).toBe(
      "/api/projects/sphere-app/chat?before=20261017T101500Z-me-a1b2"
    )
    expect(paths.away("sphere-app")).toBe("/api/projects/sphere-app/away")
    expect(paths.slackRedraft("sphere-app")).toBe(
      "/api/projects/sphere-app/slack/redraft"
    )
    expect(paths.accounts()).toBe("/api/accounts")
  })
})
