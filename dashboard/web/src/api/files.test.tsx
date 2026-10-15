import { QueryClient, QueryClientProvider } from "@tanstack/react-query"
import { renderHook, waitFor } from "@testing-library/react"
import type { ReactNode } from "react"
import { afterEach, describe, expect, it, vi } from "vitest"
import { useFileBlob } from "./files"
const wrapper = ({ children }: { children: ReactNode }) => (
  <QueryClientProvider
    client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}
  >
    {children}
  </QueryClientProvider>
)
describe("useFileBlob", () => {
  afterEach(() => vi.restoreAllMocks())
  it("fetches a text file with the token and returns its text", async () => {
    sessionStorage.setItem("star-token", "tok")
    const fetchMock = vi
      .spyOn(globalThis, "fetch")
      .mockImplementation(() =>
        Promise.resolve(
          new Response("✓ 18 passed", {
            headers: { "Content-Type": "text/plain" },
          })
        )
      )
    const { result } = renderHook(
      () => useFileBlob("/api/projects/p/file?path=a.txt", "text"),
      { wrapper }
    )
    await waitFor(() => expect(result.current.text).toBe("✓ 18 passed"))
    expect(
      new Headers(fetchMock.mock.calls[0]?.[1]?.headers).get("X-Star-Token")
    ).toBe("tok")
    expect(result.current.url).toBeNull()
  })
  it("turns an image into an object URL", async () => {
    vi.spyOn(globalThis, "fetch").mockImplementation(() =>
      Promise.resolve(
        new Response(new Blob(["<svg/>"], { type: "image/svg+xml" }))
      )
    )
    const { result } = renderHook(
      () => useFileBlob("/api/projects/p/file?path=a.png", "image"),
      { wrapper }
    )
    await waitFor(() => expect(result.current.url).toBe("blob:mock"))
  })
  it("does nothing without a URL", () => {
    const fetchMock = vi.spyOn(globalThis, "fetch")
    const { result } = renderHook(() => useFileBlob(null, "image"), { wrapper })
    expect(result.current.url).toBeNull()
    expect(fetchMock).not.toHaveBeenCalled()
  })
})
