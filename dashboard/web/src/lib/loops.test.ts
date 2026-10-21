import { describe, expect, it } from "vitest"
import { groupOf, kindOf } from "./loops"

describe("loop kinds", () => {
  it("groups person as blocked, slack-reply as slack and the rest as others", () => {
    expect(groupOf("person")).toBe("blocked")
    expect(groupOf("slack-reply")).toBe("slack")
    expect(groupOf("set-aside")).toBe("others")
    expect(groupOf("draft")).toBe("others")
    expect(groupOf("go-batch")).toBe("others")
  })
  it("labels the schema-3 kinds, and an unknown kind generically", () => {
    expect(kindOf("set-aside").label).toBe("Set aside")
    expect(kindOf("person").label).toBe("Your step")
    expect(kindOf("go-batch").label).toBe("Go batch")
  })
})
