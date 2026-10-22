import { describe, expect, it } from "vitest"
import type { Loop, LoopOption } from "@/api/types"
import {
  alsoItems,
  groupOf,
  kindOf,
  primaryOf,
  secondaryOf,
  subkindLabel,
  subkindOf,
  visibleBody,
} from "./loops"

const opt = (label: string, recommended = false): LoopOption => ({
  label,
  answer: label.toLowerCase(),
  recommended,
})
const loop = (over: Partial<Loop> = {}): Loop => ({
  id: "N-1",
  kind: "person",
  item: "SPH-1",
  title: "t",
  body: [],
  options: [],
  suggestion: null,
  answer: null,
  askedAt: null,
  ...over,
})

describe("loop kinds", () => {
  it("groups person and set-aside as hold, slack-reply as slack and the rest as other", () => {
    expect(groupOf("person")).toBe("hold")
    expect(groupOf("set-aside")).toBe("hold")
    expect(groupOf("slack-reply")).toBe("slack")
    expect(groupOf("draft")).toBe("other")
    expect(groupOf("error")).toBe("other")
    expect(groupOf("whatever")).toBe("other")
  })
  it("labels the schema-3 kinds, and an unknown kind generically", () => {
    expect(kindOf("set-aside").label).toBe("Set aside")
    expect(kindOf("person").label).toBe("Your step")
    expect(kindOf("go-batch").label).toBe("Go batch")
  })
})

describe("body lines", () => {
  it("reads the subkind word", () => {
    expect(subkindOf(["kind: account", "SPH-11 and SPH-12 read"])).toBe(
      "account"
    )
    expect(subkindOf(["nothing here"])).toBeNull()
  })
  it("reads the items of also lines", () => {
    expect(
      alsoItems(["x", "also: SPH-12 briefs/sphere-app/SPH-12.md #2 account"])
    ).toEqual(["SPH-12"])
    expect(alsoItems(["x"])).toEqual([])
  })
  it("drops kind and also lines and keeps the rest in order", () => {
    const body = [
      "kind: account",
      "first",
      "also: SPH-12 a.md #2 account",
      "second",
    ]
    expect(visibleBody(loop({ body }))).toEqual(["first", "second"])
  })
  it("labels the subkinds", () => {
    expect(subkindLabel("secret")).toBe("Secret")
    expect(subkindLabel("account")).toBe("Account")
    expect(subkindLabel("screen")).toBe("At your screen")
    expect(subkindLabel("approval")).toBe("Approval")
    expect(subkindLabel("access")).toBe("Access")
    expect(subkindLabel("other-thing")).toBe("Other-thing")
  })
})

describe("one-tap options", () => {
  it("picks the recommended option as primary, else the first", () => {
    expect(
      primaryOf(loop({ options: [opt("A"), opt("B", true)] }))?.label
    ).toBe("B")
    expect(primaryOf(loop({ options: [opt("A"), opt("B")] }))?.label).toBe("A")
    expect(primaryOf(loop())).toBeNull()
  })
  it("picks the second option as secondary only when there are exactly two", () => {
    expect(
      secondaryOf(loop({ options: [opt("A", true), opt("B")] }))
    ).toMatchObject({ label: "B" })
    expect(secondaryOf(loop({ options: [opt("A"), opt("B"), opt("C")] }))).toBe(
      "open"
    )
    expect(secondaryOf(loop({ options: [opt("A")] }))).toBeNull()
    expect(secondaryOf(loop())).toBeNull()
  })
})
