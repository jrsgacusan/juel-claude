import { render, screen } from "@testing-library/react"
import { describe, expect, it } from "vitest"
import { Markdown } from "./markdown"

describe("Markdown", () => {
  it("renders headings, lists and emphasis", () => {
    render(<Markdown text={"# Plan\n\n## Steps\n\n- one\n- two\n\n1. first\n2. second\n\n**bold** and *soft*"} />)
    expect(screen.getByRole("heading", { level: 1, name: "Plan" })).toBeInTheDocument()
    expect(screen.getByRole("heading", { level: 2, name: "Steps" })).toBeInTheDocument()
    const [bullets, numbers] = screen.getAllByRole("list")
    expect(bullets!.tagName).toBe("UL")
    expect(numbers!.tagName).toBe("OL")
    expect(screen.getAllByRole("listitem")).toHaveLength(4)
    expect(screen.getByText("bold").tagName).toBe("STRONG")
    expect(screen.getByText("soft").tagName).toBe("EM")
  })

  it("renders inline code and code blocks, the block scrolling in its own box", () => {
    const { container } = render(<Markdown text={"run `npm ci` now\n\n```sh\nnpm ci\nnpm test\n```"} />)
    const inline = screen.getByText("npm ci", { selector: "p code" })
    expect(inline.tagName).toBe("CODE")
    const pre = container.querySelector("pre")!
    expect(pre.querySelector("code")!.textContent).toBe("npm ci\nnpm test\n")
    expect(pre).toHaveClass("overflow-x-auto")
  })

  it("opens links in a new tab without handing over the page", () => {
    render(<Markdown text="[the PR](https://github.com/o/r/pull/1)" />)
    const link = screen.getByRole("link", { name: "the PR" })
    expect(link).toHaveAttribute("href", "https://github.com/o/r/pull/1")
    expect(link).toHaveAttribute("target", "_blank")
    expect(link).toHaveAttribute("rel", "noopener noreferrer")
  })

  it("renders a GFM table inside a box that scrolls sideways", () => {
    render(<Markdown text={"| Item | State |\n|---|---|\n| SPH-21 | queued |"} />)
    const table = screen.getByRole("table")
    expect(screen.getAllByRole("columnheader")).toHaveLength(2)
    expect(table.parentElement).toHaveClass("max-w-full", "overflow-x-auto")
  })

  it("never renders raw HTML: a script stays text", () => {
    const { container } = render(<Markdown text={"<script>alert(1)</script>\n\nhello <b>there</b>\n\n[x](javascript:alert(1))"} />)
    expect(container.querySelector("script")).toBeNull()
    expect(container.querySelector("b")).toBeNull()
    expect(container).toHaveTextContent("<script>alert(1)</script>")
    expect(container.innerHTML).not.toContain("javascript:")
  })

  it("wraps a long URL instead of widening the page", () => {
    const url = `https://example.com/${"a".repeat(300)}`
    const { container } = render(<Markdown text={`see ${url}`} />)
    const link = screen.getByRole("link", { name: url })
    expect(link).toHaveClass("wrap-anywhere")
    expect(container.firstElementChild).toHaveClass("min-w-0", "wrap-anywhere")
  })
})
