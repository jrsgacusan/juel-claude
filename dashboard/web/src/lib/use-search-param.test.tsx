import { act, render } from "@testing-library/react"
import { createMemoryRouter, RouterProvider } from "react-router"
import { describe, expect, it } from "vitest"
import { useSearchParam } from "./use-search-param"

describe("useSearchParam", () => {
  it("reads, sets and deletes one param and keeps the others", async () => {
    let hook!: ReturnType<typeof useSearchParam>
    function Probe() {
      hook = useSearchParam("item")
      return null
    }
    const router = createMemoryRouter([{ path: "/", Component: Probe }], {
      initialEntries: ["/?item=A&t=x"],
    })
    render(<RouterProvider router={router} />)
    expect(hook[0]).toBe("A")
    await act(() => hook[1]("B"))
    expect(router.state.location.search).toBe("?item=B&t=x")
    await act(() => hook[1](null))
    expect(router.state.location.search).toBe("?t=x")
  })

  it("replaces by default, pushes with replace: false and keeps the entry's state", async () => {
    let hook!: ReturnType<typeof useSearchParam>
    function Probe() {
      hook = useSearchParam("item")
      return null
    }
    const router = createMemoryRouter([{ path: "/", Component: Probe }], {
      initialEntries: ["/"],
    })
    render(<RouterProvider router={router} />)
    await act(() => hook[1]("A"))
    expect(router.state.historyAction).toBe("REPLACE")
    await act(() => hook[1]("B", { replace: false, state: { listDetail: true } }))
    expect(router.state.historyAction).toBe("PUSH")
    expect(router.state.location.search).toBe("?item=B")
    expect(router.state.location.state).toEqual({ listDetail: true })
  })

  it("clears other params in the same navigation", async () => {
    let hook!: ReturnType<typeof useSearchParam>
    function Probe() {
      hook = useSearchParam("message")
      return null
    }
    const router = createMemoryRouter([{ path: "/", Component: Probe }], {
      initialEntries: ["/?message=M&loop=N-1&draft=d.md&t=x"],
    })
    render(<RouterProvider router={router} />)
    await act(() => hook[1]("M2", { clear: ["loop", "draft"] }))
    expect(router.state.location.search).toBe("?message=M2&t=x")
  })
})
