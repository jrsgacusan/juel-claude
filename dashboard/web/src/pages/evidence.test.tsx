import { screen, within } from "@testing-library/react"
import { describe, expect, it } from "vitest"
import { setScenario } from "@/mocks/state"
import { renderApp } from "@/test/render"

describe("Evidence", () => {
  it("lists merged items by day and shows the selected one's checks and criteria", async () => {
    renderApp("/sphere-app/evidence")
    const list = await screen.findByRole("region", { name: "Merged items" })
    expect(
      await within(list).findByText("Fix invoice rounding")
    ).toBeInTheDocument()
    expect(within(list).getAllByRole("button")).toHaveLength(3)
    expect(within(list).getByText("Today")).toBeInTheDocument()
    expect(within(list).getByText("3 files")).toBeInTheDocument()
    const detail = screen.getByRole("region", { name: "Evidence detail" })
    expect(
      await within(detail).findByRole("heading", {
        name: "Fix invoice rounding",
      })
    ).toBeInTheDocument()
    expect(within(detail).getByText("Merged")).toBeInTheDocument()
    expect(within(detail).getByText("0b8e4c3")).toBeInTheDocument()
    for (const check of ["Claude review", "Codex gate", "CI", "Approval"])
      expect(within(detail).getByText(check)).toBeInTheDocument()
    expect(within(detail).getByText("14 checks green")).toBeInTheDocument()
    expect(
      within(detail).getByText("Totals round half up to the cent")
    ).toBeInTheDocument()
    expect(
      within(detail).getByRole("button", { name: "Open invoice-pdf.png" })
    ).toBeInTheDocument()
  })

  it("opens an image, a video and a text file full size", async () => {
    const { user } = renderApp("/sphere-app/evidence?item=SPH-4")
    const detail = await screen.findByRole("region", {
      name: "Evidence detail",
    })
    await user.click(
      await within(detail).findByRole("button", {
        name: "Open filters-in-url.png",
      })
    )
    let dialog = await screen.findByRole("dialog", {
      name: "filters-in-url.png",
    })
    expect(
      await within(dialog).findByRole("img", { name: "filters-in-url.png" })
    ).toHaveAttribute("src", "blob:mock")
    await user.keyboard("{Escape}")
    await user.click(
      within(detail).getByRole("button", { name: "Open clear-all.webm" })
    )
    dialog = await screen.findByRole("dialog", { name: "clear-all.webm" })
    const video = await within(dialog).findByLabelText("clear-all.webm")
    expect(video.tagName).toBe("VIDEO")
    expect(video).toHaveAttribute("controls")
    await user.keyboard("{Escape}")
    await user.click(
      within(detail).getByRole("button", {
        name: "Open reports-filters.spec.txt",
      })
    )
    dialog = await screen.findByRole("dialog", {
      name: "reports-filters.spec.txt",
    })
    const text = await within(dialog).findByText(/6 passed/)
    expect(text.tagName).toBe("PRE")
    expect(text).toHaveClass("font-mono")
  })

  it("shows the release record", async () => {
    const { user } = renderApp("/sphere-app/evidence?item=SPH-4")
    await user.click(
      await screen.findByRole("button", { name: /Release record/ })
    )
    const dialog = await screen.findByRole("dialog", { name: "Release record" })
    expect(
      within(dialog).getByText("Passed round 2, sol xhigh")
    ).toBeInTheDocument()
  })

  it("has loading, empty and error states", async () => {
    setScenario("loading")
    const first = renderApp("/sphere-app/evidence")
    expect(await screen.findByTestId("page-loading")).toBeInTheDocument()
    first.unmount()
    setScenario("empty")
    const second = renderApp("/sphere-app/evidence")
    expect(await screen.findByText("No merged items yet.")).toBeInTheDocument()
    second.unmount()
    setScenario("error")
    renderApp("/sphere-app/evidence")
    expect(await screen.findByTestId("page-error")).toHaveTextContent(
      "Couldn't load the evidence."
    )
  })
})
