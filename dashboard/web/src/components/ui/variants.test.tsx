import { render, screen } from "@testing-library/react"
import { describe, expect, it } from "vitest"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"

describe("answer variants", () => {
  it("Button answer is solid amber with its own text colour", () => {
    render(<Button variant="answer">Send to STAR</Button>)
    const button = screen.getByRole("button", { name: "Send to STAR" })
    expect(button).toHaveClass("bg-answer", "text-answer-foreground")
  })
  it("Badge count is solid amber with tabular figures", () => {
    render(<Badge variant="count">3</Badge>)
    expect(screen.getByText("3")).toHaveClass("bg-answer", "text-answer-foreground", "tabular-nums")
  })
})
