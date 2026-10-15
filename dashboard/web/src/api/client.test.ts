import { afterEach, describe, expect, it, vi } from "vitest"
import { ApiError, apiJson, sendJson } from "./client"
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
})
