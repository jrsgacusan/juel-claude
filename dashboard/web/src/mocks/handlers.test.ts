import { describe, expect, it, vi } from "vitest"
import { apiFetch, apiJson, ApiError, sendJson } from "@/api/client"
import { paths } from "@/api/paths"
import type {
  EvidenceDetail,
  ItemDetail,
  ItemRow,
  Loop,
  Overview,
  Project,
  ProjectLoop,
} from "@/api/types"
import { HOME } from "./fixtures"
import { dayLabel } from "@/lib/format"
import { getDb, mockEvents, resetMockState, setScenario } from "./state"
describe("the mock API", () => {
  it("lists the projects with their open loop counts", async () => {
    const projects = await apiJson<Project[]>(paths.projects())
    expect(projects.map((p) => [p.name, p.state, p.needsYou])).toEqual([
      ["sphere-app", "running", 6],
      ["sphere-api", "idle", 0],
      ["juel-claude", "stopped", 1],
    ])
  })
  it("orders the loops blocked first, then the rest", async () => {
    const loops = await apiJson<Loop[]>(paths.loops(HOME))
    expect(loops.map((l) => l.id)).toEqual([
      "N-38",
      "N-41",
      "N-44",
      "N-43",
      "N-39",
      "N-46",
    ])
    expect(
      loops.find((l) => l.id === "N-41")?.options.find((o) => o.recommended)
        ?.answer
    ).toBe("done")
  })
  it("lists every project's loops by rank, then project, then number", async () => {
    const loops = await apiJson<ProjectLoop[]>(paths.allLoops())
    expect(loops.map((l) => `${l.project}/${l.id}`)).toEqual([
      "sphere-app/N-41",
      "sphere-app/N-44",
      "juel-claude/N-7",
      "sphere-app/N-38",
      "sphere-app/N-39",
      "sphere-app/N-43",
      "sphere-app/N-46",
    ])
  })
  it("serves the shapes of the server's contract", async () => {
    const overview = await apiJson<Overview>(paths.overview(HOME))
    expect(overview).not.toHaveProperty("quietHours")
    const loops = await apiJson<Loop[]>(paths.loops(HOME))
    expect(loops.find((l) => l.id === "N-39")?.askedAt).toBeNull()
    expect(loops.find((l) => l.id === "N-41")?.answer).toBe("")
    for (const item of ["SPH-8", "SPH-4", "SPH-3"]) {
      const detail = await apiJson<EvidenceDetail>(
        paths.evidenceItem(HOME, item)
      )
      expect(
        Object.keys(detail.record).every((k) =>
          ["approval", "ci", "gate"].includes(k)
        )
      ).toBe(true)
      expect(detail.pr?.startsWith("https://")).toBe(true)
    }
    const flat = await apiJson<EvidenceDetail>(
      paths.evidenceItem(HOME, "SPH-3")
    )
    expect(flat.groups).toHaveLength(1)
    expect(flat.groups[0]?.criterion).toBeNull()
  })

  it("returns 404 for an unknown project's overview", async () => {
    await expect(
      apiJson(paths.overview("unknown-project"))
    ).rejects.toMatchObject({
      status: 404,
      message: "No project named unknown-project",
    })
  })
  it("records an answer and emits a loops change", async () => {
    const res = await sendJson("POST", paths.answer(HOME, "N-41"), {
      text: "go",
    })
    expect(res).toEqual({ recorded: true, nudged: true })
    expect(getDb().loops[HOME]?.find((l) => l.id === "N-41")?.answer).toBe("go")
    const projects = await apiJson<Project[]>(paths.projects())
    expect(projects[0]?.needsYou).toBe(5)
  })
  it("answers 409 in the conflict scenario", async () => {
    setScenario("conflict")
    await expect(
      sendJson("POST", paths.answer(HOME, "N-41"), { text: "go" })
    ).rejects.toMatchObject({ status: 409 })
  })
  it("refuses a request without the token, like the server", async () => {
    sessionStorage.clear()
    await expect(apiJson(paths.projects())).rejects.toMatchObject({
      status: 401,
    })
  })
  it("serves empty lists and errors by scenario", async () => {
    setScenario("empty")
    expect(await apiJson<Loop[]>(paths.loops(HOME))).toEqual([])
    setScenario("error")
    const err = await apiJson(paths.items(HOME)).catch((e: unknown) => e)
    expect(err).toBeInstanceOf(ApiError)
    expect((err as ApiError).status).toBe(502)
  })
  it("has a detail for every item", async () => {
    const rows = await apiJson<ItemRow[]>(paths.items(HOME))
    expect(rows).toHaveLength(11)
    for (const row of rows) {
      const detail = await apiJson<ItemDetail>(paths.item(HOME, row.item))
      expect(detail.row.item).toBe(row.item)
      expect(detail.progress.length).toBeGreaterThan(0)
    }
  })
  it("keeps the mock's two merges on today's date when the tests run just after midnight", async () => {
    vi.useFakeTimers({ toFake: ["Date"] })
    const night = new Date()
    night.setHours(0, 30, 0, 0)
    vi.setSystemTime(night)
    try {
      resetMockState()
      const rows = getDb().items[HOME]!.map((d) => d.row)
      for (const ref of ["SPH-8", "SPH-4"])
        expect(dayLabel(rows.find((r) => r.item === ref)!.mergedAt ?? "")).toBe("Today")
    } finally {
      vi.useRealTimers()
      resetMockState()
    }
  })
  it("carries counters, mergedAt, fixed stages and the also line (D9)", async () => {
    const rows = await apiJson<ItemRow[]>(paths.items(HOME))
    const byItem = (ref: string) => rows.find((row) => row.item === ref)!
    const minutesAgo = (iso: string | null | undefined) =>
      Math.round((Date.now() - Date.parse(iso ?? "")) / 60_000)
    // 10 and 150 minutes ago, but never before today's midnight: the mock's merges stay today's.
    expect(minutesAgo(byItem("SPH-8").mergedAt)).toBeLessThanOrEqual(10)
    expect(minutesAgo(byItem("SPH-4").mergedAt)).toBeLessThanOrEqual(150)
    for (const ref of ["SPH-8", "SPH-4"]) expect(dayLabel(byItem(ref).mergedAt ?? "")).toBe("Today")
    for (const row of rows.filter((r) => !["SPH-8", "SPH-4"].includes(r.item)))
      expect(row.mergedAt).toBeNull()
    for (const ref of ["SPH-7", "SPH-9", "SPH-5", "SPH-11", "SPH-13", "SPH-10", "SPH-8", "SPH-4"])
      expect(byItem(ref).counters).toMatch(/reached=/)
    expect(byItem("SPH-5").stage).toBe("babysit")
    expect(byItem("SPH-8").stage).toBe("babysit")
    expect(byItem("SPH-4").stage).toBe("babysit")
    const loops = await apiJson<Loop[]>(paths.loops(HOME))
    expect(loops.find((l) => l.id === "N-41")?.body).toContain(
      "also: SPH-12 briefs/sphere-app/SPH-12.md #2 account"
    )
  })
  it("serves evidence files by kind", async () => {
    const text = await (
      await apiFetch(paths.file(HOME, "evidence/SPH-8/rounding.test.txt"))
    ).text()
    expect(text).toContain("18 passed")
    const image = await apiFetch(
      paths.file(HOME, "evidence/SPH-4/filters-in-url.png")
    )
    expect(image.headers.get("Content-Type")).toBe("image/svg+xml")
    const video = await apiFetch(
      paths.file(HOME, "evidence/SPH-4/clear-all.webm")
    )
    expect(video.headers.get("Content-Type")).toBe("video/webm")
  })
  it("streams events to an open /api/events reader", async () => {
    const res = await apiFetch(paths.events())
    const reader = (res.body as ReadableStream<Uint8Array>).getReader()
    const decoder = new TextDecoder()
    expect(decoder.decode((await reader.read()).value)).toBe(": connected\n\n")
    mockEvents.emit({ type: "change", project: HOME, what: "loops" })
    expect(decoder.decode((await reader.read()).value)).toBe(
      `data: ${JSON.stringify({ type: "change", project: HOME, what: "loops" })}\n\n`
    )
    mockEvents.drop()
    expect((await reader.read()).done).toBe(true)
    await expect(apiFetch(paths.events())).rejects.toThrow()
  })
})
