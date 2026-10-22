import { render, screen } from "@testing-library/react"
import { describe, expect, it } from "vitest"
import { SlotPips, StageRail } from "@/components/stage-rail"

describe("StageRail", () => {
  it("is an image with five segments in their states", () => {
    render(<StageRail rail={{ done: 2, current: 2, tone: "wait" }} />)
    const rail = screen.getByRole("img", { name: "Stage 3 of 5, Gate, waiting on you" })
    const segments = rail.querySelectorAll('[data-slot="stage-segment"]')
    expect([...segments].map((s) => s.getAttribute("data-state"))).toEqual(["done", "done", "current", "upcoming", "upcoming"])
    expect(segments[2]).toHaveAttribute("data-tone", "wait")
    expect(segments[0]).not.toHaveAttribute("data-tone")
    expect(rail).toHaveAttribute("data-size", "sm")
  })
  it("shows the stage names at size lg, the current one bold in its tone", () => {
    render(<StageRail rail={{ done: 2, current: 2, tone: "wait" }} size="lg" />)
    for (const name of ["Brief", "Build", "Gate", "Review", "Merge"]) expect(screen.getByText(name)).toBeInTheDocument()
    expect(screen.getByText("Gate")).toHaveClass("font-semibold", "text-wait-fg")
    expect(screen.getByText("Brief")).not.toHaveClass("font-semibold")
  })
  it("marks a finished rail all done", () => {
    render(<StageRail rail={{ done: 5, current: null, tone: "run" }} />)
    const segments = screen.getByRole("img", { name: "Merged" }).querySelectorAll('[data-state="done"]')
    expect(segments).toHaveLength(5)
  })
})

describe("SlotPips", () => {
  it("is an image with total squares, busy of them filled", () => {
    render(<SlotPips busy={2} total={3} />)
    const pips = screen.getByRole("img", { name: "2 of 3 busy" })
    expect(pips).toHaveAttribute("data-slot", "slot-pips")
    expect(pips.children).toHaveLength(3)
    expect(pips.querySelectorAll('[data-filled="true"]')).toHaveLength(2)
  })
})
