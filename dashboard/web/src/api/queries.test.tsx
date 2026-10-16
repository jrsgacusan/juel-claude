import { QueryClientProvider } from "@tanstack/react-query"
import { renderHook } from "@testing-library/react"
import type { ReactNode } from "react"
import { afterEach, describe, expect, it, vi } from "vitest"
import { getConflict, setConflict } from "@/lib/conflict"
import { ApiError, NetworkError } from "./client"
import { createQueryClient, retryQuery, useAnswer } from "./queries"
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  })
function wrap() {
  const client = createQueryClient()
  return ({ children }: { children: ReactNode }) => (
    <QueryClientProvider client={client}>{children}</QueryClientProvider>
  )
}
describe("useAnswer", () => {
  afterEach(() => vi.restoreAllMocks())
  it("raises the conflict banner for that project on a 409", async () => {
    vi.spyOn(globalThis, "fetch").mockImplementation(() =>
      Promise.resolve(
        json(
          { error: "open-loops.md has unresolved git conflict markers" },
          409
        )
      )
    )
    const { result } = renderHook(() => useAnswer("sphere-app"), {
      wrapper: wrap(),
    })
    await expect(
      result.current.mutateAsync({ id: "N-41", text: "go" })
    ).rejects.toMatchObject({ status: 409 })
    expect(getConflict()).toBe("sphere-app")
  })
  it("clears the banner on the next answer that goes through", async () => {
    setConflict("sphere-app")
    vi.spyOn(globalThis, "fetch").mockImplementation(() =>
      Promise.resolve(json({ recorded: true, nudged: true }))
    )
    const { result } = renderHook(() => useAnswer("sphere-app"), {
      wrapper: wrap(),
    })
    await expect(
      result.current.mutateAsync({ id: "N-41", text: "go" })
    ).resolves.toEqual({ recorded: true, nudged: true })
    expect(getConflict()).toBeNull()
  })
})

describe("retryQuery", () => {
  it("never retries a 4xx, retries a 5xx or a network error twice", () => {
    expect(retryQuery(0, new ApiError(401, "no"))).toBe(false)
    expect(retryQuery(0, new ApiError(404, "no"))).toBe(false)
    expect(retryQuery(0, new ApiError(502, "no"))).toBe(true)
    expect(retryQuery(1, new NetworkError("down"))).toBe(true)
    expect(retryQuery(2, new ApiError(502, "no"))).toBe(false)
  })
})
