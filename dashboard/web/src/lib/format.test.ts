import { describe, expect, it } from "vitest"
import { clock, dateTime, dayLabel } from "./format"

describe("format", () => {
  it("renders nothing for a null or invalid time", () => {
    expect(clock(null)).toBe("")
    expect(clock("not a date")).toBe("")
    expect(dateTime(null)).toBe("")
    expect(dayLabel(null)).toBe("")
  })
})
