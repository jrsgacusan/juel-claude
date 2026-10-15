import { QueryClientProvider } from "@tanstack/react-query"
import { renderHook } from "@testing-library/react"
import type { ReactNode } from "react"
import { afterEach, describe, expect, it, vi } from "vitest"
import { getConflict } from "@/lib/conflict"
import { createQueryClient, useAnswer } from "./queries"
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
