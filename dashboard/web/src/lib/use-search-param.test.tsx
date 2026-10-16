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
})
