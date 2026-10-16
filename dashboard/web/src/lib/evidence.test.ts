import { describe, expect, it } from "vitest"
import type { EvidenceFile, FileKind } from "@/api/types"
import { evidenceTiles, isBefore } from "./evidence"

const file = (name: string, kind: FileKind = "image"): EvidenceFile => ({
  name,
  kind,
  url: `/file/${name}`,
})

const shape = (files: EvidenceFile[]) =>
  evidenceTiles(files).map((t) =>
    t.kind === "pair"
      ? `${t.before.name} | ${t.after.name}`
      : `${t.file.name}${t.before ? " (before)" : ""}`
  )

describe("isBefore", () => {
  it("reads before as a word of an image or recording's name", () => {
    expect(isBefore(file("05-pill-before.png"))).toBe(true)
    expect(isBefore(file("before-home-card.png"))).toBe(true)
    expect(isBefore(file("recording_before_dev.webm", "video"))).toBe(true)
    expect(isBefore(file("shots/Before.PNG"))).toBe(true)
    expect(isBefore(file("beforehand.png"))).toBe(false)
    expect(isBefore(file("live-results.before.json", "text"))).toBe(false)
  })
})

describe("evidenceTiles", () => {
  it("puts a before shot beside its after shot, pairs first", () => {
    expect(
      shape([
        file("01-home.png"),
        file("02-pill-after.png"),
        file("02-pill-before.png"),
        file("notes.txt", "text"),
      ])
    ).toEqual([
      "02-pill-before.png | 02-pill-after.png",
      "01-home.png",
      "notes.txt",
    ])
  })

  it("pairs a before prefix with the bare name, in the same folder and kind only", () => {
    expect(
      shape([
        file("shots/before-home-card.png"),
        file("shots/home-card.png"),
        file("other/before-vault.png"),
        file("vault.png"),
        file("clip-before.webm", "video"),
        file("clip.png"),
      ])
    ).toEqual([
      "shots/before-home-card.png | shots/home-card.png",
      "other/before-vault.png (before)",
      "vault.png",
      "clip-before.webm (before)",
      "clip.png",
    ])
  })

  it("prefers an after name over a bare one, and pairs each counterpart once", () => {
    expect(
      shape([
        file("menu.png"),
        file("menu-after.png"),
        file("menu-before.png"),
        file("before-menu.png"),
      ])
    ).toEqual([
      "menu-before.png | menu-after.png",
      "menu.png",
      "before-menu.png (before)",
    ])
  })
})
