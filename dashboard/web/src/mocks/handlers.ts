import { http, HttpResponse } from "msw/http"
import { bypass } from "msw/utils/bypass"
import { delay } from "msw/utils/delay"
import type { BriefingEvent, Project, Tracker } from "@/api/types"
import {
  consumeFailedBriefingTurn,
  getDb,
  getScenario,
  mockEvents,
} from "./state"
import { HOME } from "./fixtures"
import clipUrl from "./assets/clip.webm?url"

const API = "*/api"
const json = (body: unknown, status = 200) =>
  HttpResponse.json(body as never, { status })
const fail = (status: number, error: string) => json({ error }, status)
const pageGate = async (): Promise<Response | null> => {
  const s = getScenario()
  if (s === "loading") await delay("infinite")
  if (s === "error")
    return fail(502, "Could not read ledger.md: permission denied")
  return null
}
const isEmpty = () => getScenario() === "empty"
const projectOf = (
  params: Record<string, string | readonly string[] | undefined>
) => String(params.p)
const findProject = (p: string): Project | undefined =>
  getDb().projects.find((project) => project.name === p)
const bodyJson = async (request: Request): Promise<Record<string, unknown>> => {
  const body = (await request.json()) as unknown
  return body && typeof body === "object"
    ? (body as Record<string, unknown>)
    : {}
}
const escapeXml = (s: string) =>
  s.replace(
    /[<>&"']/g,
    (c) =>
      ({
        "<": "&lt;",
        ">": "&gt;",
        "&": "&amp;",
        '"': "&quot;",
        "'": "&apos;",
      })[c] ?? c
  )
const screenshotSvg = (name: string) =>
  `<svg xmlns="http://www.w3.org/2000/svg" width="1440" height="900" viewBox="0 0 1440 900"><rect width="1440" height="900" fill="#f4f4f5"/><rect x="48" y="48" width="1344" height="56" rx="10" fill="#262626"/><rect x="48" y="150" width="880" height="28" rx="6" fill="#d4d4d4"/><rect x="48" y="200" width="1100" height="28" rx="6" fill="#d4d4d4"/><rect x="48" y="250" width="640" height="28" rx="6" fill="#d4d4d4"/><rect x="48" y="760" width="520" height="72" rx="10" fill="#ffffff" stroke="#d4d4d4"/><text x="72" y="806" font-family="monospace" font-size="28" fill="#525252">${escapeXml(name)}</text></svg>`
async function clip(): Promise<Response> {
  const headers = { "Content-Type": "video/webm" }
  if (import.meta.env.MODE === "test")
    return new HttpResponse(new Uint8Array([0x1a, 0x45, 0xdf, 0xa3]), {
      headers,
    })
  const res = await fetch(bypass(new URL(clipUrl, window.location.origin)))
  return new HttpResponse(await res.arrayBuffer(), { headers })
}

export const handlers = [
  http.all(`${API}/*`, ({ request }) =>
    request.headers.get("X-Star-Token")
      ? undefined
      : fail(401, "This dashboard needs its token")
  ),
  http.get(`${API}/projects`, () => {
    const db = getDb()
    const stopped = getScenario() === "stopped"
    const projects = db.projects.map((p) => ({
      ...p,
      state: stopped ? ("stopped" as const) : p.state,
      needsYou: isEmpty()
        ? 0
        : (db.loops[p.name] ?? []).filter((l) => !l.answer).length,
    }))
    return json(projects)
  }),
  http.get(`${API}/projects/:p/overview`, async ({ params }) => {
    const p = projectOf(params)
    const gate = await pageGate()
    if (gate) return gate
    if (!findProject(p)) return fail(404, `No project named ${p}`)
    return json(
      isEmpty()
        ? {
            resume: { state: "idle", pools: "", next: "", lastTick: null },
            counts: {},
            workers: { brief: [0, 4], build: [0, 3], babysit: [0, 3] },
            gateDown: null,
            away: null,
            quietHours: null,
          }
        : getDb().overview[p]
    )
  }),
  http.get(`${API}/projects/:p/loops`, async ({ params }) => {
    const gate = await pageGate()
    if (gate) return gate
    return json(isEmpty() ? [] : (getDb().loops[projectOf(params)] ?? []))
  }),
  http.post(
    `${API}/projects/:p/loops/:id/answer`,
    async ({ params, request }) => {
      const p = projectOf(params)
      if (getScenario() === "conflict")
        return fail(409, "open-loops.md has unresolved git conflict markers")
      const loop = (getDb().loops[p] ?? []).find(
        (candidate) => candidate.id === String(params.id)
      )
      if (!loop) return fail(404, `No loop ${String(params.id)}`)
      if (loop.answer?.trim())
        return fail(409, `${loop.id} already has an answer: STAR acts on that one`)
      const body = await bodyJson(request)
      const text = typeof body.text === "string" ? body.text.trim() : ""
      if (!text) return fail(400, "An answer needs text")
      loop.answer = text
      mockEvents.later(50, () =>
        mockEvents.emit({ type: "change", project: p, what: "loops" })
      )
      return json({
        recorded: true,
        nudged: findProject(p)?.state !== "stopped",
      })
    }
  ),
  http.get(`${API}/projects/:p/items`, async ({ params }) => {
    const gate = await pageGate()
    if (gate) return gate
    return json(
      isEmpty()
        ? []
        : (getDb().items[projectOf(params)] ?? []).map((detail) => detail.row)
    )
  }),
  http.get(`${API}/projects/:p/items/:item`, async ({ params }) => {
    const gate = await pageGate()
    if (gate) return gate
    const detail = (getDb().items[projectOf(params)] ?? []).find(
      (candidate) => candidate.row.item === String(params.item)
    )
    return detail
      ? json(detail)
      : fail(404, `No item ${String(params.item)} in ${projectOf(params)}`)
  }),
  http.get(`${API}/projects/:p/evidence`, async ({ params }) => {
    const gate = await pageGate()
    if (gate) return gate
    const details = isEmpty() ? [] : (getDb().evidence[projectOf(params)] ?? [])
    return json(
      details
        .map((d) => ({
          item: d.item,
          title: d.title,
          pr: d.pr,
          sha: d.sha,
          mergedAt: d.mergedAt,
          goAt: d.goAt,
          files: d.groups.reduce((sum, group) => sum + group.files.length, 0),
        }))
        .sort((a, b) => (b.mergedAt ?? "").localeCompare(a.mergedAt ?? ""))
    )
  }),
  http.get(`${API}/projects/:p/evidence/:item`, async ({ params }) => {
    const gate = await pageGate()
    if (gate) return gate
    const detail = (getDb().evidence[projectOf(params)] ?? []).find(
      (candidate) => candidate.item === String(params.item)
    )
    return detail
      ? json(detail)
      : fail(404, `No evidence ${String(params.item)}`)
  }),
  http.get(`${API}/projects/:p/file`, async ({ params, request }) => {
    const p = projectOf(params)
    const path = new URL(request.url).searchParams.get("path") ?? ""
    if (path.includes("..") || path.startsWith("/"))
      return fail(400, "The path leaves the STAR folder")
    if (path.endsWith(".webm")) return clip()
    const entry = getDb().files[`${p}/${path}`]
    if (entry)
      return new HttpResponse(entry.body, {
        headers: { "Content-Type": entry.type },
      })
    if (path.endsWith(".png"))
      return new HttpResponse(screenshotSvg(path.split("/").pop() ?? path), {
        headers: { "Content-Type": "image/svg+xml" },
      })
    return fail(404, `No file ${path}`)
  }),
  http.put(`${API}/projects/:p/drafts/:name`, async ({ params, request }) => {
    const p = projectOf(params)
    const message = getDb().slack.routed.find(
      (candidate) =>
        candidate.project === p &&
        candidate.draftPath?.split("/").pop() === String(params.name)
    )
    if (!message?.draftPath) return fail(404, "No draft")
    const body = await bodyJson(request)
    const text = typeof body.text === "string" ? body.text : ""
    const file = getDb().files[`${p}/${message.draftPath}`]
    if (file) file.body = `${file.body.split("\n")[0]}\n${text}`
    mockEvents.later(50, () =>
      mockEvents.emit({ type: "change", project: p, what: "drafts" })
    )
    return json({ saved: true })
  }),
  http.get(`${API}/search`, async ({ request }) => {
    const gate = await pageGate()
    if (gate) return gate
    if (isEmpty()) return json([])
    const url = new URL(request.url)
    const q = (url.searchParams.get("q") ?? "").toLowerCase()
    const p = url.searchParams.get("project") ?? HOME
    const all = url.searchParams.get("all") === "1"
    return json(
      getDb().search.filter(
        (result) =>
          (all || result.project === p) &&
          (!q ||
            [result.title, result.sub, result.ref].some((value) =>
              value.toLowerCase().includes(q)
            ))
      )
    )
  }),
  http.get(`${API}/events`, () =>
    mockEvents.dropped
      ? HttpResponse.error()
      : new HttpResponse(mockEvents.open(), {
          headers: {
            "Content-Type": "text/event-stream",
            "Cache-Control": "no-cache",
            Connection: "keep-alive",
          },
        })
  ),
  http.get(`${API}/slack`, async () => {
    const gate = await pageGate()
    if (gate) return gate
    const db = getDb()
    return json({
      status: {
        ...db.slack.status,
        connected:
          getScenario() === "slack-off" ? false : db.slack.status.connected,
      },
      routed: isEmpty() ? [] : db.slack.routed,
      unrouted: isEmpty() ? [] : db.slack.unrouted,
    })
  }),
  http.post(`${API}/slack/:id/route`, async ({ params, request }) => {
    const id = String(params.id)
    const body = await bodyJson(request)
    const project = typeof body.project === "string" ? body.project : "none"
    const index = getDb().slack.unrouted.findIndex(
      (candidate) => candidate.id === id
    )
    if (index < 0) return fail(404, "No unrouted message")
    const [message] = getDb().slack.unrouted.splice(index, 1)
    if (project !== "none" && message)
      getDb().slack.routed.push({
        ...message,
        project,
        thread: [],
        draftPath: null,
        loopId: null,
      })
    mockEvents.later(50, () =>
      mockEvents.emit({ type: "change", what: "slack" })
    )
    return json({ routed: true })
  }),
  http.post(
    `${API}/slack/check`,
    () => new HttpResponse(null, { status: 202 })
  ),
  http.get(`${API}/projects/:p/briefings`, async ({ params }) => {
    const gate = await pageGate()
    if (gate) return gate
    return json(
      isEmpty()
        ? []
        : (getDb().briefings[projectOf(params)] ?? [])
            .map((entry) => entry.summary)
            .sort((a, b) => b.updatedAt.localeCompare(a.updatedAt))
    )
  }),
  http.post(`${API}/projects/:p/briefings`, async ({ params }) => {
    const p = projectOf(params)
    const list = getDb().briefings[p] ?? (getDb().briefings[p] = [])
    const id = `b${list.length + 1}`
    list.unshift({
      summary: {
        id,
        title: "New briefing",
        updatedAt: new Date().toISOString(),
        ref: null,
      },
      briefing: { turns: [], draft: null, busy: false },
    })
    return json({ id })
  }),
  http.get(`${API}/projects/:p/briefings/:id`, async ({ params }) => {
    const gate = await pageGate()
    if (gate) return gate
    const entry = (getDb().briefings[projectOf(params)] ?? []).find(
      (candidate) => candidate.summary.id === String(params.id)
    )
    return entry
      ? json(entry.briefing)
      : fail(404, `No briefing ${String(params.id)}`)
  }),
  http.post(
    `${API}/projects/:p/briefings/:id/messages`,
    async ({ params, request }) => {
      const p = projectOf(params)
      const entry = (getDb().briefings[p] ?? []).find(
        (candidate) => candidate.summary.id === String(params.id)
      )
      if (!entry) return fail(404, "No briefing")
      if (entry.briefing.busy) return fail(409, "The agent is still answering")
      const body = await bodyJson(request)
      const text = typeof body.text === "string" ? body.text.trim() : ""
      if (!text) return fail(400, "A message needs text")
      entry.briefing.busy = true
      if (consumeFailedBriefingTurn()) {
        mockEvents.later(500, () => {
          entry.briefing.busy = false
          mockEvents.emit({
            type: "briefing",
            project: p,
            id: String(params.id),
            error: "claude exited 1",
          })
        })
        return new HttpResponse(null, { status: 202 })
      }
      const reply = `Noted: ${text}. I added it to the draft's acceptance criteria. Anything else before I create it?`
      const words = reply.split(" ")
      for (const [i, ms] of [250, 500, 750].entries())
        mockEvents.later(ms, () =>
          mockEvents.emit({
            type: "briefing",
            project: p,
            id: String(params.id),
            turn: {
              who: "agent",
              text: words
                .slice(0, Math.ceil((words.length * (i + 1)) / 3))
                .join(" "),
            },
          } satisfies BriefingEvent)
        )
      mockEvents.later(1000, () => {
        entry.briefing.busy = false
        entry.briefing.draft ??= {
          title: text.slice(0, 60),
          description: text,
          criteria: [],
          outOfScope: [],
        }
        entry.briefing.draft.criteria.push(text)
        entry.summary.updatedAt = new Date().toISOString()
        mockEvents.emit({
          type: "briefing",
          project: p,
          id: String(params.id),
          turn: { who: "agent", text: reply, done: true },
          draft: entry.briefing.draft,
        })
        entry.briefing.turns.push({ who: "me", text })
        entry.briefing.turns.push({ who: "agent", text: reply, done: true })
        mockEvents.emit({ type: "change", project: p, what: "briefings" })
      })
      return new HttpResponse(null, { status: 202 })
    }
  ),
  http.post(
    `${API}/projects/:p/briefings/:id/create`,
    async ({ params, request }) => {
      const p = projectOf(params)
      const entry = (getDb().briefings[p] ?? []).find(
        (candidate) => candidate.summary.id === String(params.id)
      )
      if (!entry?.briefing.draft)
        return fail(400, "The briefing has no ticket draft yet")
      if (entry.summary.ref)
        return fail(409, `This briefing already made ${entry.summary.ref}`)
      const body = await bodyJson(request)
      const tracker = typeof body.tracker === "string" ? body.tracker : "none"
      const connected =
        getDb().trackerConnected[p]?.[tracker as Tracker] !== false
      let result:
        | { ref: string; url: string | null }
        | { specPath: string; url: string | null }
      if (tracker === "github" && connected)
        result = {
          ref: "#88",
          url: `https://github.com/example/${p}/issues/88`,
        }
      else if ((tracker === "linear" || tracker === "jira") && connected)
        result = {
          ref: "SPH-16",
          url: "https://linear.app/example/issue/SPH-16",
        }
      else
        result = {
          specPath: `items/${p}/${entry.briefing.draft.title
            .toLowerCase()
            .replace(/[^a-z0-9]+/g, "-")
            .replace(/(^-|-$)/g, "")}.md`,
          url: null,
        }
      entry.summary.ref = "ref" in result ? result.ref : result.specPath
      mockEvents.later(50, () => {
        mockEvents.emit({ type: "change", project: p, what: "loops" })
        mockEvents.emit({ type: "change", project: p, what: "briefings" })
      })
      return json(result)
    }
  ),
  http.get(`${API}/projects/:p/tracker`, async ({ params }) => {
    const gate = await pageGate()
    if (gate) return gate
    return json(getDb().trackers[projectOf(params)] ?? { tracker: null })
  }),
  http.put(`${API}/projects/:p/tracker`, async ({ params, request }) => {
    const p = projectOf(params)
    const body = await bodyJson(request)
    const tracker = typeof body.tracker === "string" ? body.tracker : "none"
    if (
      !(["synapse", "linear", "jira", "github", "none"] as string[]).includes(
        tracker
      )
    )
      return fail(400, `Unknown tracker ${tracker}`)
    const current = getDb().trackers[p] ?? { tracker: null }
    current.tracker = tracker as Tracker
    getDb().trackers[p] = current
    return json({ tracker })
  }),
]
