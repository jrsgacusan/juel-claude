import { afterEach, describe, expect, it, vi } from "vitest"
import { ApiError, apiJson, checkToken, NetworkError, sendJson } from "./client"
import { errorMessage } from "@/lib/errors"
import { paths } from "./paths"
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  })

describe("the API client", () => {
  afterEach(() => vi.restoreAllMocks())
  it("sends X-Star-Token on every request, against the page's origin", async () => {
    sessionStorage.setItem("star-token", "tok")
    const fetchMock = vi
      .spyOn(globalThis, "fetch")
      .mockImplementation(() => Promise.resolve(json([])))
    await apiJson("/api/projects")
    await sendJson("POST", "/api/projects/a/loops/N-1/answer", { text: "go" })
    for (const [url, init] of fetchMock.mock.calls) {
      expect(String(url)).toMatch(new RegExp(`^${window.location.origin}/api/`))
      expect(new Headers(init?.headers).get("X-Star-Token")).toBe("tok")
    }
    const [, post] = fetchMock.mock.calls[1]
    expect(post?.method).toBe("POST")
    expect(new Headers(post?.headers).get("Content-Type")).toBe(
      "application/json"
    )
    expect(post?.body).toBe(JSON.stringify({ text: "go" }))
    expect(post?.keepalive).toBeUndefined()
  })

  it("keeps a request alive past the page's unload when asked", async () => {
    const fetchMock = vi
      .spyOn(globalThis, "fetch")
      .mockImplementation(() => Promise.resolve(json([])))
    await sendJson("POST", "/api/projects/a/loops/N-1/answer", { text: "go" }, { keepalive: true })
    expect(fetchMock.mock.calls[0]?.[1]?.keepalive).toBe(true)
  })
  it("throws ApiError with the server's message and status", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      json({ error: "open-loops.md has unresolved git conflict markers" }, 409)
    )
    await expect(apiJson("/api/projects")).rejects.toMatchObject({
      name: "ApiError",
      status: 409,
      message: "open-loops.md has unresolved git conflict markers",
    })
  })
  it("falls back to the status text when the body is not JSON", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response("Bad Gateway", { status: 502, statusText: "Bad Gateway" })
    )
    const err = await apiJson("/api/projects").catch((e: unknown) => e)
    expect(err).toBeInstanceOf(ApiError)
    expect((err as ApiError).message).toBe("Bad Gateway")
  })
  it("returns null for an empty 202", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response(null, { status: 202 })
    )
    await expect(sendJson("POST", "/api/x", { text: "hi" })).resolves.toBeNull()
  })
  it("turns a failed fetch into a NetworkError and keeps other TypeErrors as they are", async () => {
    vi.spyOn(globalThis, "fetch").mockRejectedValue(
      new TypeError("Failed to fetch")
    )
    const err = await apiJson("/api/projects").catch((e: unknown) => e)
    expect(err).toBeInstanceOf(NetworkError)
    expect(errorMessage(err)).toBe("The dashboard server did not answer.")
    expect(errorMessage(new TypeError("x is undefined"))).toBe("x is undefined")
  })
  it("refuses a body that is not JSON, and an empty one unless allowed", async () => {
    vi.spyOn(globalThis, "fetch").mockImplementation(() =>
      Promise.resolve(
        new Response("<!doctype html>", {
          status: 200,
          headers: { "Content-Type": "text/html" },
        })
      )
    )
    await expect(apiJson("/api/projects")).rejects.toMatchObject({
      message:
        "The dashboard server sent something that is not JSON for /api/projects.",
    })
    vi.spyOn(globalThis, "fetch").mockImplementation(() =>
      Promise.resolve(new Response(null, { status: 200 }))
    )
    await expect(apiJson("/api/projects")).rejects.toMatchObject({
      message: "The dashboard server sent an empty answer for /api/projects.",
    })
  })
  it("encodes project names, ids and search params", () => {
    expect(paths.loops("sphere.api tools")).toBe(
      "/api/projects/sphere.api%20tools/loops"
    )
    expect(paths.answer("p", "N-41")).toBe("/api/projects/p/loops/N-41/answer")
    expect(paths.file("p", "evidence/SPH-4/a b.png")).toBe(
      "/api/projects/p/file?path=evidence%2FSPH-4%2Fa%20b.png"
    )
    expect(paths.search({ q: "csv export", project: "p", all: true })).toBe(
      "/api/search?q=csv+export&project=p&all=1"
    )
    expect(paths.search({ q: "x", project: "p", all: false })).toBe(
      "/api/search?q=x&project=p"
    )
  })
  it("checks a pasted token against the server without storing it", async () => {
    const fetchMock = vi.spyOn(globalThis, "fetch")
      .mockResolvedValueOnce(json([]))
      .mockResolvedValueOnce(json({ error: "missing or wrong X-Star-Token" }, 401))
      .mockResolvedValueOnce(json({ error: "Could not read ledger.md" }, 502))
      .mockRejectedValueOnce(new TypeError("Failed to fetch"))
    await expect(checkToken("pasted")).resolves.toBe("accepted")
    await expect(checkToken("wrong")).resolves.toBe("refused")
    // Any answer but 401 passed the server's token check (dashboard/server/app.ts:102-105).
    await expect(checkToken("pasted")).resolves.toBe("accepted")
    await expect(checkToken("pasted")).resolves.toBe("unreachable")
    const [url, init] = fetchMock.mock.calls[0] ?? []
    expect(String(url)).toBe(`${window.location.origin}/api/projects`)
    expect(new Headers(init?.headers).get("X-Star-Token")).toBe("pasted")
    expect(localStorage.getItem("star-token")).toBeNull()
  })
  it("says a refused token plainly", () => {
    expect(errorMessage(new ApiError(401, "missing or wrong X-Star-Token"))).toBe("The dashboard server refused the token.")
  })
})
