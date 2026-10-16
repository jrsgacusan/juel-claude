import { describe, expect, it } from "vitest"
import { itemLabel, trackerRef } from "./items"

describe("trackerRef", () => {
  it.each([
    [{ item: "seat-pause", ref: "SPH-7" }, "SPH-7"],
    [{ item: "audit-log", ref: " AUD-3 " }, "AUD-3"],
    [{ item: "issue-41", ref: "#41" }, "#41"],
    [{ item: "SPH-7", ref: "SPH-7" }, null],
    [{ item: "csv-import", ref: "-" }, null],
    [{ item: "csv-import", ref: "" }, null],
    [{ item: "csv-import", ref: null }, null],
    [{ item: "csv-import" }, null],
    [{ item: "invoice-export", ref: "/Users/owner/star/items/sample/invoice-export.md" }, null],
    [{ item: "x", ref: "~/star/items/x.md" }, null],
    [{ item: "x", ref: "./items/x" }, null],
    [{ item: "x", ref: "../items/x" }, null],
    [{ item: "x", ref: "items/sample/x.md" }, null],
  ])("%o -> %o", (row, want) => expect(trackerRef(row)).toBe(want))
})

describe("itemLabel", () => {
  it("is the name, then the tracker ref after a middle dot", () => {
    expect(itemLabel({ item: "seat-pause", ref: "SPH-7" })).toBe("seat-pause · SPH-7")
    expect(itemLabel({ item: "invoice-export", ref: "/a/b.md" })).toBe("invoice-export")
  })
})
