import { render, screen } from "@testing-library/react"
import { describe, expect, it } from "vitest"
import type { Overview } from "@/api/types"
import { WorkersCard } from "./workers-card"

type Pool = [number, number]
const pools = (brief: Pool, build: Pool, babysit: Pool): Overview["workers"] => ({ brief, build, babysit })
const slots = (pool: string) =>
  Array.from(screen.getByRole("meter", { name: pool }).querySelectorAll<HTMLElement>("[data-slot=worker-slot]"))
const filled = (pool: string) => slots(pool).filter((s) => s.dataset.filled === "true")

describe("the Workers card", () => {
  it("shows each pool as one square per slot with n/max, and the busy count", () => {
    render(<WorkersCard workers={pools([1, 4], [3, 3], [1, 3])} />)
    for (const text of ["Workers", "5 busy", "1 of 4", "3 of 3", "1 of 3"]) expect(screen.getByText(text)).toBeInTheDocument()
    // Counts are words in the UI face; the mono face is kept for SHAs and paths.
    expect(screen.getByText("1 of 4")).not.toHaveClass("font-mono")
    expect(slots("Briefing")).toHaveLength(4)
    expect(filled("Briefing")).toHaveLength(1)
    expect(slots("Review")).toHaveLength(3)
    const building = screen.getByRole("meter", { name: "Building" })
    for (const [name, value] of [["aria-valuenow", "3"], ["aria-valuemin", "0"], ["aria-valuemax", "3"], ["aria-valuetext", "3 of 3 busy"]])
      expect(building).toHaveAttribute(name, value)
  })

  it("says all free when nothing is busy, and draws no square for a pool of 0", () => {
    render(<WorkersCard workers={pools([0, 4], [0, 0], [0, 3])} />)
    expect(screen.getByText("all free")).toBeInTheDocument()
    expect(slots("Building")).toHaveLength(0)
    expect(screen.getByText("0 of 0")).toBeInTheDocument()
  })

  it("breathes filled squares and pops only a square that fills while shown", () => {
    const motion = () => slots("Building").map((s) => (s.className.match(/motion-\w+/g) ?? []).join(" "))
    const { rerender } = render(<WorkersCard workers={pools([0, 4], [1, 4], [0, 3])} />)
    expect(motion()).toEqual(["motion-breathe", "", "", ""])
    rerender(<WorkersCard workers={pools([0, 4], [2, 4], [0, 3])} />)
    expect(motion()).toEqual(["motion-breathe", "motion-breathe motion-pop", "", ""])
    rerender(<WorkersCard workers={pools([0, 4], [0, 4], [0, 3])} />)
    expect(filled("Building")).toHaveLength(0)
    expect(motion()).toEqual(["", "", "", ""])
    rerender(<WorkersCard workers={pools([0, 4], [1, 4], [0, 3])} />)
    expect(motion()).toEqual(["motion-breathe motion-pop", "", "", ""])
  })
})
