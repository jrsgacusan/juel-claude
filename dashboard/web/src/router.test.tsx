import { screen, within } from "@testing-library/react"
import { describe, expect, it } from "vitest"
import { renderApp } from "@/test/render"

describe("the project routes", () => {
  // By pattern, not exact text, so the owners' real headings (lanes G and H) keep this passing.
  for (const [path, heading, crumb] of [
    ["chat", /chat/i, "Chat"],
    ["accounts", /accounts/i, "Accounts"],
  ] as const)
    it(`opens ${crumb} under a project, named in the breadcrumb`, async () => {
      renderApp(`/sphere-app/${path}`)
      expect(
        await screen.findByRole("heading", { level: 1, name: heading })
      ).toBeInTheDocument()
      const crumbs = await screen.findByRole("navigation", {
        name: /breadcrumb/i,
      })
      expect(within(crumbs).getByText(crumb)).toBeInTheDocument()
    })
  it("names every page on the not-found page", async () => {
    renderApp("/sphere-app/nowhere")
    expect(
      await screen.findByText(
        "The dashboard has Needs you, Progress, Chat, Slack replies, Briefing and Evidence for each project, and Claude accounts."
      )
    ).toBeInTheDocument()
  })
})
