import { act, render, screen, within } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { createMemoryRouter, RouterProvider, useSearchParams } from "react-router"
import { afterEach, describe, expect, it, vi } from "vitest"
import { useDetailOpen } from "@/lib/chrome"
import { ListDetail, useListSelection } from "./list-detail"

const setWidth = (value: number) =>
  Object.defineProperty(window, "innerWidth", { configurable: true, writable: true, value })
const phone = () => {
  setWidth(390)
  return vi.spyOn(window, "scrollTo").mockImplementation(() => {})
}

function Harness({ aliases }: { aliases: string[] }) {
  const { value, select, back } = useListSelection("item", aliases)
  const [params] = useSearchParams()
  const shown = value ?? aliases.map((a) => params.get(a)).find(Boolean) ?? null
  const list = ["A", "B"].map((id) => (
    <button key={id} type="button" onClick={() => select(id)}>{`Open ${id}`}</button>
  ))
  return (
    <ListDetail showDetail={shown !== null} onBack={back} backLabel="Things" listLabel="Things"
      detailLabel="Thing" columns="md:grid-cols-[minmax(300px,380px)_minmax(0,1fr)]"
      list={<><input aria-label="Filter" />{list}</>} detail={<p>{`Showing ${shown ?? "A"}`}</p>} />
  )
}
function DetailFlag() {
  return <p data-testid="detail-open">{String(useDetailOpen())}</p>
}
function start(path = "/", aliases: string[] = []) {
  const router = createMemoryRouter([{ path: "/", element: <><Harness aliases={aliases} /><DetailFlag /></> }], {
    initialEntries: [path],
  })
  const view = render(<RouterProvider router={router} />)
  return { router, user: userEvent.setup(), view }
}
afterEach(() => setWidth(1024))

describe("ListDetail", () => {
  it("at md and up shows both panes, and selecting replaces history", async () => {
    const { router, user } = start()
    expect(screen.getByRole("region", { name: "Thing" })).toHaveTextContent("Showing A")
    await user.click(screen.getByRole("button", { name: "Open B" }))
    expect(router.state.historyAction).toBe("REPLACE")
    expect(router.state.location.search).toBe("?item=B")
    expect(screen.getByRole("region", { name: "Things" })).toBeInTheDocument()
    expect(screen.getByRole("region", { name: "Thing" })).toHaveTextContent("Showing B")
    expect(screen.queryByRole("button", { name: "Back to Things" })).not.toBeInTheDocument()
  })

  it("below md shows the list alone; selecting pushes and shows only the item; Back pops to the list", async () => {
    const scrollTo = phone()
    const { router, user } = start()
    expect(screen.queryByRole("region", { name: "Thing" })).not.toBeInTheDocument()
    await user.type(screen.getByRole("textbox", { name: "Filter" }), "abc")
    await user.click(screen.getByRole("button", { name: "Open B" }))
    expect(router.state.historyAction).toBe("PUSH")
    expect(router.state.location.search).toBe("?item=B")
    expect(screen.queryByRole("region", { name: "Things" })).not.toBeInTheDocument()
    const thing = screen.getByRole("region", { name: "Thing" })
    expect(thing).toHaveTextContent("Showing B")
    expect(thing).toHaveClass("motion-fade-in")
    expect(scrollTo).toHaveBeenCalledWith(0, 0)
    await user.click(within(thing).getByRole("button", { name: "Back to Things" }))
    expect(await screen.findByRole("region", { name: "Things" })).toBeInTheDocument()
    expect(router.state.historyAction).toBe("POP")
    expect(router.state.location.search).toBe("")
    expect(screen.queryByRole("region", { name: "Thing" })).not.toBeInTheDocument()
    expect(screen.getByRole("textbox", { name: "Filter" })).toHaveValue("abc")
  })

  it("below md, an item opened from a link shows, and Back removes the param in place", async () => {
    phone()
    const { router, user } = start("/?item=B&t=x")
    expect(screen.getByRole("region", { name: "Thing" })).toHaveTextContent("Showing B")
    await user.click(screen.getByRole("button", { name: "Back to Things" }))
    expect(await screen.findByRole("region", { name: "Things" })).toBeInTheDocument()
    expect(router.state.historyAction).toBe("REPLACE")
    expect(router.state.location.search).toBe("?t=x")
  })

  it("Back and select clear the aliases", async () => {
    phone()
    const { router, user } = start("/?loop=N-1&draft=d.md&t=x", ["loop", "draft"])
    expect(screen.getByRole("region", { name: "Thing" })).toHaveTextContent("Showing N-1")
    await user.click(screen.getByRole("button", { name: "Back to Things" }))
    expect(await screen.findByRole("region", { name: "Things" })).toBeInTheDocument()
    expect(router.state.location.search).toBe("?t=x")
    setWidth(1024)
    act(() => void window.dispatchEvent(new Event("resize")))
    await user.click(screen.getByRole("button", { name: "Open A" }))
    expect(router.state.location.search).toBe("?t=x&item=A")
    expect(router.state.historyAction).toBe("REPLACE")
  })

  it("follows the width live", () => {
    start()
    expect(screen.getByRole("region", { name: "Thing" })).toBeInTheDocument()
    phone()
    act(() => void window.dispatchEvent(new Event("resize")))
    expect(screen.queryByRole("region", { name: "Thing" })).not.toBeInTheDocument()
    expect(screen.getByRole("region", { name: "Things" })).toBeInTheDocument()
  })

  it("tells the chrome when a phone shows its detail, and when it does not", async () => {
    phone()
    const { user, view } = start()
    const flag = () => screen.getByTestId("detail-open").textContent
    expect(flag()).toBe("false")
    await user.click(screen.getByRole("button", { name: "Open A" }))
    expect(flag()).toBe("true")
    await user.click(screen.getByRole("button", { name: "Back to Things" }))
    expect(flag()).toBe("false")
    await user.click(screen.getByRole("button", { name: "Open B" }))
    expect(flag()).toBe("true")
    view.unmount()
    render(<DetailFlag />)
    expect(screen.getByTestId("detail-open").textContent).toBe("false")
  })

  it("never reports a detail open on a desktop", () => {
    start("/?item=A")
    expect(screen.getByTestId("detail-open").textContent).toBe("false")
  })
})
