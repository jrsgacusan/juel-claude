import { render, screen, within } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { describe, expect, it, vi } from "vitest"
import { Pager } from "./pager"

const pager = (page: number, pageCount: number, onPage = vi.fn()) => (
  <Pager page={page} pageCount={pageCount} onPage={onPage} label="Progress pages" />
)
const button = (name: string) => screen.getByRole("button", { name })

describe("Pager", () => {
  it("renders nothing when everything fits on one page", () => {
    const { container } = render(pager(1, 1))
    expect(container).toBeEmptyDOMElement()
  })
  it("says where you are, inside a nav named by its label", () => {
    render(pager(2, 5))
    const nav = screen.getByRole("navigation", { name: "Progress pages" })
    expect(within(nav).getByText("Page 2 of 5")).toBeInTheDocument()
  })
  it("disables Previous page on the first page and Next page on the last", () => {
    const { rerender } = render(pager(1, 5))
    expect(button("Previous page")).toBeDisabled()
    expect(button("Next page")).toBeEnabled()
    rerender(pager(5, 5))
    expect(button("Previous page")).toBeEnabled()
    expect(button("Next page")).toBeDisabled()
  })
  it("asks for the page before and after, with 44 px buttons on touch", async () => {
    const onPage = vi.fn()
    render(pager(2, 5, onPage))
    await userEvent.click(button("Next page"))
    expect(onPage).toHaveBeenLastCalledWith(3)
    await userEvent.click(button("Previous page"))
    expect(onPage).toHaveBeenLastCalledWith(1)
    for (const name of ["Previous page", "Next page"])
      expect(button(name).className).toContain("pointer-coarse:h-11")
  })
})
