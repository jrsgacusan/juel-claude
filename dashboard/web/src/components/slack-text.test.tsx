import { render, screen, within } from "@testing-library/react"
import { describe, expect, it } from "vitest"
import { SlackText } from "./slack-text"

// The phone check (D20): a long message with bullets and raw URLs read as one wall of text.
const LONG = [
  "hey Juel, before the demo can you check these?",
  "• the CSV export PR: https://github.com/example/sphere-app/pull/212",
  "• the invoice ticket <https://linear.app/example/issue/SPH-13|SPH-13>",
  "- staging (https://staging.example.com/reports?tab=export&amp;from=2026-10-01).",
  "",
  "thanks! <javascript:alert(1)|click me> &lt;b&gt;not bold&lt;/b&gt; &amp; done",
].join("\n")

describe("SlackText", () => {
  it("keeps a long message's paragraphs, bullets and links, and renders no HTML", () => {
    const { container } = render(<SlackText text={LONG} />)
    expect(screen.getByText("hey Juel, before the demo can you check these?").tagName).toBe("P")
    const items = within(screen.getByRole("list")).getAllByRole("listitem")
    expect(items).toHaveLength(3)
    expect(items[0]).toHaveTextContent("the CSV export PR: https://github.com/example/sphere-app/pull/212")
    expect(items[2]).toHaveTextContent(
      "staging (https://staging.example.com/reports?tab=export&from=2026-10-01)."
    )
    const links = screen.getAllByRole("link")
    expect(links.map((a) => a.getAttribute("href"))).toEqual([
      "https://github.com/example/sphere-app/pull/212",
      "https://linear.app/example/issue/SPH-13",
      "https://staging.example.com/reports?tab=export&from=2026-10-01",
    ])
    for (const a of links) {
      expect(a).toHaveAttribute("target", "_blank")
      expect(a).toHaveAttribute("rel", "noopener noreferrer")
      expect(a).toHaveClass("break-all")
    }
    expect(screen.getByRole("link", { name: "SPH-13" })).toBeInTheDocument()
    expect(screen.queryByRole("link", { name: "click me" })).not.toBeInTheDocument()
    expect(container).toHaveTextContent("thanks! click me <b>not bold</b> & done")
    expect(container.querySelector("b, script")).toBeNull()
  })

  it("keeps a single line break and adds no list to plain text", () => {
    const { container } = render(<SlackText text={"ok, will do\nafter lunch"} />)
    expect(container.querySelectorAll("p")).toHaveLength(1)
    expect(container.querySelectorAll("br")).toHaveLength(1)
    expect(screen.queryByRole("list")).not.toBeInTheDocument()
    expect(screen.queryByRole("link")).not.toBeInTheDocument()
  })
})
