import { screen, waitFor, within } from "@testing-library/react"
import { http, HttpResponse } from "msw/http"
import { describe, expect, it } from "vitest"
import { server } from "@/mocks/node"
import { getDb, setScenario } from "@/mocks/state"
import { renderApp } from "@/test/render"

const loopAnswer = (id: string) =>
  getDb().loops["sphere-app"]?.find((l) => l.id === id)?.answer

describe("Needs you", () => {
  it("lists the open loops with tab counts, blocked work first", async () => {
    renderApp("/sphere-app/needs")
    expect(
      await screen.findByRole("tab", { name: /^All\s*9$/ })
    ).toBeInTheDocument()
    expect(
      screen.getByRole("tab", { name: /^Blocked\s*4$/ })
    ).toBeInTheDocument()
    expect(screen.getByRole("tab", { name: /^Slack\s*3$/ })).toBeInTheDocument()
    expect(
      screen.getByRole("tab", { name: /^Others\s*2$/ })
    ).toBeInTheDocument()
    const list = screen.getByRole("region", { name: "Open loops" })
    const entries = within(list).getAllByRole("button")
    expect(entries).toHaveLength(9)
    expect(entries[0]).toHaveTextContent(
      "The merge gate failed twice on e3f1a92"
    )
  })

  it("filters the list by tab", async () => {
    const { user } = renderApp("/sphere-app/needs")
    await user.click(await screen.findByRole("tab", { name: /^Slack\s*3$/ }))
    const list = screen.getByRole("region", { name: "Open loops" })
    const entries = within(list).getAllByRole("button")
    expect(entries).toHaveLength(3)
    for (const entry of entries) expect(entry).toHaveTextContent("Slack reply")
  })

  it("shows a go-batch's items, STAR's pick and the options, and sends with Ctrl+Enter", async () => {
    const { user } = renderApp("/sphere-app/needs?loop=N-41")
    const detail = await screen.findByRole("region", { name: "Answer" })
    expect(
      await within(detail).findByRole("heading", {
        name: "Start building SPH-11, SPH-12 and SPH-14",
      })
    ).toBeInTheDocument()
    expect(within(detail).getByText("Go for a batch")).toBeInTheDocument()
    expect(
      await within(detail).findByText("Export reports as CSV")
    ).toBeInTheDocument()
    expect(
      within(detail).getByText("Rewrite the invite email")
    ).toBeInTheDocument()
    expect(within(detail).queryByText(/^Options:/)).not.toBeInTheDocument()
    expect(within(detail).getByText("STAR recommends")).toBeInTheDocument()
    expect(
      within(detail).getByText(/SPH-11 and SPH-12 start in the next tick/)
    ).toBeInTheDocument()
    const radios = within(detail).getAllByRole("radio")
    expect(radios).toHaveLength(3)
    expect(
      within(detail).getByText("Recommended").closest("label")
    ).toHaveTextContent(/^Go\s*Recommended$/)
    await user.click(radios[0] as HTMLElement)
    expect(within(detail).getByLabelText("Or write your own")).toHaveValue("go")
    await user.keyboard("{Control>}{Enter}{/Control}")
    expect(
      await screen.findByText('Sent to STAR: "go". It acts on it now.')
    ).toBeInTheDocument()
    expect(
      within(detail).getByText('Sent "go". STAR picked it up.')
    ).toBeInTheDocument()
    expect(loopAnswer("N-41")).toBe("go")
    const list = screen.getByRole("region", { name: "Open loops" })
    expect(within(list).getAllByText("Sent to STAR")).toHaveLength(1)
  })

  it("a loop with no time shows no age", async () => {
    renderApp("/sphere-app/needs?loop=N-39")
    const detail = await screen.findByRole("region", { name: "Answer" })
    expect(
      await within(detail).findByRole("heading", {
        name: "SPH-5 needs an approval from a teammate",
      })
    ).toBeInTheDocument()
    expect(within(detail).queryByText(/^Asked/)).not.toBeInTheDocument()
  })

  it("asks for an answer before sending", async () => {
    const { user } = renderApp("/sphere-app/needs?loop=N-43")
    await user.click(
      await screen.findByRole("button", { name: /Send to STAR/ })
    )
    expect(
      await screen.findByText("Pick an answer or write one first.")
    ).toBeInTheDocument()
    expect(loopAnswer("N-43")).toBeNull()
  })

  it("an item with no options sends free text", async () => {
    const { user } = renderApp("/sphere-app/needs?loop=N-46")
    const detail = await screen.findByRole("region", { name: "Answer" })
    await within(detail).findByRole("heading", {
      name: /Mark PR #211 ready once quiet hours end/,
    })
    expect(
      within(detail).queryByText("STAR recommends")
    ).not.toBeInTheDocument()
    expect(within(detail).queryAllByRole("radio")).toHaveLength(0)
    await user.type(
      within(detail).getByLabelText("Or write your own"),
      "ok, do it"
    )
    await user.keyboard("{Meta>}{Enter}{/Meta}")
    expect(
      await screen.findByText('Sent to STAR: "ok, do it". It acts on it now.')
    ).toBeInTheDocument()
    expect(loopAnswer("N-46")).toBe("ok, do it")
  })

  it("shows the conflict banner on a 409 and no Sent mark", async () => {
    setScenario("conflict")
    const { user } = renderApp("/sphere-app/needs?loop=N-41")
    const detail = await screen.findByRole("region", { name: "Answer" })
    await user.click(
      (await within(detail).findAllByRole("radio"))[0] as HTMLElement
    )
    await user.click(
      within(detail).getByRole("button", { name: /Send to STAR/ })
    )
    expect(
      await screen.findByText(
        "open-loops.md has conflict markers. Resolve them, then answer here."
      )
    ).toBeInTheDocument()
    expect(within(detail).queryByText(/^Sent "/)).not.toBeInTheDocument()
  })

  it("a failed send keeps the answer and says what failed", async () => {
    server.use(
      http.post("*/api/projects/:p/loops/:id/answer", () =>
        HttpResponse.json(
          { error: "loops.sh failed: disk full" },
          { status: 500 }
        )
      )
    )
    const { user } = renderApp("/sphere-app/needs?loop=N-41")
    const detail = await screen.findByRole("region", { name: "Answer" })
    const box = await within(detail).findByLabelText("Or write your own")
    await user.type(box, "go except SPH-14")
    await user.click(
      within(detail).getByRole("button", { name: /Send to STAR/ })
    )
    expect(
      await screen.findByText(
        "Couldn't send the answer: loops.sh failed: disk full"
      )
    ).toBeInTheDocument()
    expect(box).toHaveValue("go except SPH-14")
    expect(within(detail).queryByText(/^Sent "/)).not.toBeInTheDocument()
  })

  it("links a Slack reply to its draft on the Slack page", async () => {
    renderApp("/sphere-app/needs?loop=N-45")
    const detail = await screen.findByRole("region", { name: "Answer" })
    expect(
      await within(detail).findByText(
        "hey, is the CSV export landing today? sales wants to demo it tomorrow"
      )
    ).toBeInTheDocument()
    expect(
      within(detail).getByRole("link", { name: /Edit the draft/ })
    ).toHaveAttribute("href", "/sphere-app/slack?loop=N-45")
  })

  it("has loading, empty and error states", async () => {
    setScenario("loading")
    const first = renderApp("/sphere-app/needs")
    expect(await screen.findByTestId("page-loading")).toBeInTheDocument()
    first.unmount()
    setScenario("empty")
    const second = renderApp("/sphere-app/needs")
    expect(
      await screen.findByText("Nothing needs you right now.")
    ).toBeInTheDocument()
    expect(
      screen.getByText(
        "When STAR waits on an answer, a go or one of your steps, it shows here."
      )
    ).toBeInTheDocument()
    second.unmount()
    setScenario("error")
    renderApp("/sphere-app/needs")
    const alert = await screen.findByTestId("page-error")
    expect(alert).toHaveTextContent("Couldn't load the open loops.")
    expect(alert).toHaveTextContent(
      "Could not read ledger.md: permission denied"
    )
    await waitFor(() =>
      expect(
        within(alert).getByRole("button", { name: /Try again/ })
      ).toBeEnabled()
    )
  })
})
