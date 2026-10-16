import { http, HttpResponse, type HttpHandler } from "msw/http"
import { getDb, mockEvents } from "./state"

// Routes added here: POST /api/projects/:p/slack/redraft and PUT /api/slack/paused.
const fail = (status: number, error: string) =>
  HttpResponse.json({ error }, { status })

const nextLoopId = (ids: string[]) => {
  const numbers = ids.map((id) => Number(/^N-(\d+)$/.exec(id)?.[1] ?? 0))
  return `N-${Math.max(0, ...numbers) + 1}`
}

export const slackExtraHandlers: HttpHandler[] = [
  http.put("*/api/slack/paused", async ({ request }) => {
    const body = (await request.json().catch(() => null)) as {
      paused?: unknown
    } | null
    if (typeof body?.paused !== "boolean")
      return fail(400, "the body must be {paused: true} or {paused: false}")
    getDb().slack.paused = body.paused
    mockEvents.emit({ type: "change", what: "slack" })
    return HttpResponse.json({ paused: body.paused })
  }),
  http.post("*/api/projects/:p/slack/redraft", async ({ params, request }) => {
    const p = String(params.p)
    const body = (await request.json().catch(() => null)) as {
      loop?: unknown
      how?: unknown
    } | null
    const loop = typeof body?.loop === "string" ? body.loop.trim() : ""
    const how = typeof body?.how === "string" ? body.how.trim() : ""
    if (!loop || !how) return fail(400, "A redraft needs loop and how")
    const db = getDb()
    const item = (db.loops[p] ?? []).find(
      (l) => l.id === loop && l.kind === "slack-reply" && !l.answer
    )
    if (!item) return fail(404, `No open slack-reply item ${loop}`)
    // The drafter rewrites the draft, then STAR closes the item and adds it again.
    mockEvents.later(400, () => {
      const loops = db.loops[p] ?? []
      const index = loops.findIndex((l) => l.id === loop)
      if (index < 0) return
      const message = db.slack.routed.find((m) => m.loopId === loop)
      const file = message?.draftPath
        ? db.files[`${p}/${message.draftPath}`]
        : undefined
      const [first = "", ...rest] = (file?.body ?? "").split("\n")
      const old = rest.join("\n")
      const reply = old
        ? `Rewritten (${how}): ${old}`
        : `A first draft (${how}).`
      if (file) file.body = `${first}\n${reply}`
      const id = nextLoopId(loops.map((l) => l.id))
      loops.splice(index, 1, {
        ...item,
        id,
        suggestion: `Send: "${reply}"`,
        askedAt: new Date().toISOString(),
      })
      if (message) message.loopId = id
      mockEvents.emit({ type: "change", project: p, what: "drafts" })
      mockEvents.emit({ type: "change", project: p, what: "loops" })
    })
    return HttpResponse.json({ queued: true })
  }),
]
