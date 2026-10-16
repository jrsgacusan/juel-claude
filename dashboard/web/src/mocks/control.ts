import { http, HttpResponse, type HttpHandler } from "msw/http"
import { getDb, getScenario, mockEvents } from "./state"

export const AWAY_APPLY_MS = 1_500

const fail = (status: number, error: string) =>
  HttpResponse.json({ error }, { status })

// POST /api/projects/:p/away: records the wish, and a running STAR applies it a moment later.
export const controlHandlers: HttpHandler[] = [
  http.post("*/api/projects/:p/away", async ({ params, request }) => {
    const p = String(params.p)
    const db = getDb()
    const project = db.projects.find((candidate) => candidate.name === p)
    const overview = db.overview[p]
    if (!project || !overview) return fail(404, `No project named ${p}`)
    let body: unknown
    try {
      body = await request.json()
    } catch {
      body = null
    }
    const keys =
      body && typeof body === "object" ? Object.keys(body as object) : []
    const away = (body as { away?: unknown } | null)?.away
    if (keys.length !== 1 || keys[0] !== "away" || typeof away !== "boolean")
      return fail(400, 'The body must be { "away": true } or { "away": false }')
    overview.awayPending = away ? "away" : "back"
    const running = project.state === "running" && getScenario() !== "stopped"
    if (running)
      mockEvents.later(AWAY_APPLY_MS, () => {
        overview.away = away ? new Date().toISOString() : null
        overview.awayPending = null
        mockEvents.emit({ type: "change", project: p, what: "progress" })
      })
    return HttpResponse.json({ recorded: true, nudged: running })
  }),
]
