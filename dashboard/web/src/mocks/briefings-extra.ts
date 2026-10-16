import { http, HttpResponse } from "msw/http"
import type { HttpHandler } from "msw/http"
import { getDb, getScenario, mockEvents } from "./state"

const fail = (status: number, error: string) => HttpResponse.json({ error }, { status })

export const briefingsExtraHandlers: HttpHandler[] = [
  http.get("*/api/projects/:p/briefings", ({ params }) => {
    const scenario = getScenario()
    if (scenario === "loading" || scenario === "error" || scenario === "empty") return undefined
    return HttpResponse.json(
      (getDb().briefings[String(params.p)] ?? [])
        .map((entry) => ({ ...entry.summary, deletable: !entry.briefing.busy }))
        .sort((a, b) => b.updatedAt.localeCompare(a.updatedAt))
    )
  }),
  http.delete("*/api/projects/:p/briefings/:id", ({ params }) => {
    const p = String(params.p)
    const id = String(params.id)
    const list = getDb().briefings[p] ?? []
    const index = list.findIndex((b) => b.summary.id === id)
    if (index < 0) return fail(404, `no briefing ${id}`)
    if (list[index]!.briefing.busy) return fail(409, "a reply is being written for it")
    list.splice(index, 1)
    mockEvents.later(50, () => mockEvents.emit({ type: "change", project: p, what: "briefings" }))
    return HttpResponse.json({ deleted: true })
  }),
]
