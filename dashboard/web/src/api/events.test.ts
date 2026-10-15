import { QueryClient } from "@tanstack/react-query"
import { afterEach, describe, expect, it, vi } from "vitest"
import type { BriefingEvent } from "./types"
import {
  getConnection,
  keysFor,
  parseFrames,
  startEvents,
  subscribeBriefing,
  subscribeConnection,
} from "./events"
function stream() {
  let controller!: ReadableStreamDefaultController<Uint8Array>
  const body = new ReadableStream<Uint8Array>({
    start(c) {
      controller = c
    },
  })
  const encoder = new TextEncoder()
  return {
    response: new Response(body, {
      headers: { "Content-Type": "text/event-stream" },
    }),
    send: (event: unknown) =>
      controller.enqueue(encoder.encode(`data: ${JSON.stringify(event)}\n\n`)),
    end: () => controller.close(),
  }
}
describe("the event stream", () => {
  const stops: Array<() => void> = []
  afterEach(() => stops.splice(0).forEach((stop) => stop()))
  it("parses data frames and keeps a partial frame for the next chunk", () => {
    expect(parseFrames('data: {"a":1}\n\ndata: {"b"')).toEqual({
      events: [{ a: 1 }],
      rest: 'data: {"b"',
    })
    expect(parseFrames(": connected\n\n").events).toEqual([])
    expect(parseFrames("data: not json\n\n").events).toEqual([])
    expect(parseFrames('data: {"a":2}\r\n\r\n').events).toEqual([{ a: 2 }])
  })
  it("maps each change to the queries it makes stale", () => {
    const p = "sphere-app"
    expect(keysFor({ type: "change", project: p, what: "loops" })).toEqual([
      ["loops", p],
      ["projects"],
      ["slack"],
    ])
    for (const what of ["ledger", "progress"] as const)
      expect(keysFor({ type: "change", project: p, what })).toEqual([
        ["items", p],
        ["item", p],
        ["overview", p],
        ["projects"],
      ])
    expect(keysFor({ type: "change", project: p, what: "evidence" })).toEqual([
      ["evidence", p],
    ])
    expect(keysFor({ type: "change", project: p, what: "drafts" })).toEqual([
      ["slack"],
      ["draft"],
    ])
    expect(keysFor({ type: "change", what: "slack" })).toEqual([
      ["slack"],
      ["draft"],
    ])
    expect(keysFor({ type: "change", project: p, what: "briefings" })).toEqual([
      ["briefings", p],
      ["briefing", p],
    ])
  })
  it("sends the token, invalidates on change events and hands briefing events on", async () => {
    sessionStorage.setItem("star-token", "tok")
    const s = stream()
    const fetchImpl = vi.fn<typeof fetch>().mockResolvedValue(s.response)
    const client = new QueryClient()
    const invalidate = vi.spyOn(client, "invalidateQueries")
    const seen: BriefingEvent[] = []
    stops.push(subscribeBriefing((e) => seen.push(e)))
    stops.push(startEvents(client, { fetchImpl, retryMs: 20 }))
    await vi.waitFor(() => expect(getConnection()).toBe("open"))
    const init = fetchImpl.mock.calls[0]?.[1]
    expect(new Headers(init?.headers).get("X-Star-Token")).toBe("tok")
    expect(String(fetchImpl.mock.calls[0]?.[0])).toBe(
      `${window.location.origin}/api/events`
    )
    s.send({ type: "change", project: "sphere-app", what: "loops" })
    await vi.waitFor(() =>
      expect(invalidate).toHaveBeenCalledWith({
        queryKey: ["loops", "sphere-app"],
      })
    )
    s.send({
      type: "briefing",
      project: "sphere-app",
      id: "b1",
      turn: { who: "agent", text: "Hi" },
    })
    await vi.waitFor(() =>
      expect(seen).toEqual([
        {
          type: "briefing",
          project: "sphere-app",
          id: "b1",
          turn: { who: "agent", text: "Hi" },
        },
      ])
    )
  })
  it("shows lost when the stream ends, retries, and refetches everything once it is back", async () => {
    const first = stream()
    const second = stream()
    const fetchImpl = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(first.response)
      .mockRejectedValueOnce(new TypeError("Failed to fetch"))
      .mockResolvedValueOnce(second.response)
    const client = new QueryClient()
    const invalidate = vi.spyOn(client, "invalidateQueries")
    const states: string[] = []
    stops.push(subscribeConnection(() => states.push(getConnection())))
    stops.push(startEvents(client, { fetchImpl, retryMs: 20 }))
    await vi.waitFor(() => expect(getConnection()).toBe("open"))
    first.end()
    await vi.waitFor(() => expect(fetchImpl).toHaveBeenCalledTimes(3))
    await vi.waitFor(() => expect(getConnection()).toBe("open"))
    expect(states).toEqual(["open", "lost", "open"])
    expect(invalidate).toHaveBeenCalledWith({
      predicate: expect.any(Function),
    })
  })
  it("waits retryMs between tries", async () => {
    vi.useFakeTimers()
    try {
      const fetchImpl = vi
        .fn<typeof fetch>()
        .mockRejectedValue(new TypeError("Failed to fetch"))
      stops.push(startEvents(new QueryClient(), { fetchImpl }))
      await vi.advanceTimersByTimeAsync(0)
      expect(fetchImpl).toHaveBeenCalledTimes(1)
      expect(getConnection()).toBe("lost")
      await vi.advanceTimersByTimeAsync(4_999)
      expect(fetchImpl).toHaveBeenCalledTimes(1)
      await vi.advanceTimersByTimeAsync(1)
      expect(fetchImpl).toHaveBeenCalledTimes(2)
    } finally {
      vi.useRealTimers()
    }
  })
  it("a refused token stops the retries", async () => {
    vi.useFakeTimers()
    try {
      const fetchImpl = vi
        .fn<typeof fetch>()
        .mockResolvedValue(new Response(null, { status: 401 }))
      stops.push(startEvents(new QueryClient(), { fetchImpl }))
      await vi.advanceTimersByTimeAsync(0)
      expect(getConnection()).toBe("refused")
      await vi.advanceTimersByTimeAsync(20_000)
      expect(fetchImpl).toHaveBeenCalledTimes(1)
    } finally {
      vi.useRealTimers()
    }
  })

  it("never shows lost when it is stopped on purpose", async () => {
    const states: string[] = []
    stops.push(subscribeConnection(() => states.push(getConnection())))
    const fetchImpl = vi.fn<typeof fetch>(
      (_input, init) =>
        new Promise((_resolve, reject) =>
          init?.signal?.addEventListener("abort", () =>
            reject(new DOMException("aborted", "AbortError"))
          )
        )
    )
    const stop = startEvents(new QueryClient(), { fetchImpl, retryMs: 10 })
    stop()
    await new Promise((r) => setTimeout(r, 30))
    expect(states).not.toContain("lost")
  })

  it("does not refetch evidence files on reconnect", async () => {
    const first = stream()
    const second = stream()
    const fetchImpl = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(first.response)
      .mockResolvedValueOnce(second.response)
    const client = new QueryClient()
    const invalidate = vi.spyOn(client, "invalidateQueries")
    stops.push(startEvents(client, { fetchImpl, retryMs: 10 }))
    await vi.waitFor(() => expect(getConnection()).toBe("open"))
    first.end()
    await vi.waitFor(() => expect(fetchImpl).toHaveBeenCalledTimes(2))
    await vi.waitFor(() => expect(invalidate).toHaveBeenCalled())
    const call = invalidate.mock.calls.at(-1)?.[0] as {
      predicate?: (q: { queryKey: readonly unknown[] }) => boolean
    }
    expect(call?.predicate?.({ queryKey: ["file", "/x"] })).toBe(false)
    expect(call?.predicate?.({ queryKey: ["loops", "p"] })).toBe(true)
  })
})
