import { act, screen, waitFor, within } from "@testing-library/react"
import { http, HttpResponse } from "msw/http"
import { afterEach, describe, expect, it, vi } from "vitest"
import { getConnection } from "@/api/events"
import { server } from "@/mocks/node"
import { getDb, mockEvents, setScenario } from "@/mocks/state"
import { renderApp } from "@/test/render"

const loopAnswer = (id: string) =>
  getDb().loops["sphere-app"]?.find((l) => l.id === id)?.answer

const setWidth = (value: number) =>
  Object.defineProperty(window, "innerWidth", { configurable: true, writable: true, value })
const phone = () => {
  setWidth(390)
  return vi.spyOn(window, "scrollTo").mockImplementation(() => {})
}
afterEach(() => setWidth(1024))

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

  it("names a go-batch's items by their ledger name, not a raw spec path (integration brief D5)", async () => {
    const row = getDb().items["sphere-app"]?.find(
      (d) => d.row.item === "SPH-12"
    )?.row
    if (!row) throw new Error("fixture SPH-12 missing")
    row.ref = "/Users/owner/star/items/sphere-app/sph-12.md"
    renderApp("/sphere-app/needs?loop=N-41")
    const detail = await screen.findByRole("region", { name: "Answer" })
    expect(await within(detail).findByText("SPH-12")).toBeInTheDocument()
    expect(within(detail).queryByText(/sph-12\.md/)).not.toBeInTheDocument()
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
    expect(loopAnswer("N-43")).toBe("")
  })

  it("an item with no options sends free text", async () => {
    const { user } = renderApp("/sphere-app/needs?loop=N-46")
    const detail = await screen.findByRole("region", { name: "Answer" })
    await within(detail).findByRole("heading", {
      name: /Mark PR #211 ready, then/,
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

  it("says when another answer got there first, without the conflict banner", async () => {
    server.use(
      http.post("*/api/projects/:p/loops/:id/answer", ({ params }) =>
        HttpResponse.json(
          {
            error: `${String(params.id)} already has an answer: STAR acts on that one`,
          },
          { status: 409 }
        )
      )
    )
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
        "Couldn't send the answer: N-41 already has an answer: STAR acts on that one"
      )
    ).toBeInTheDocument()
    expect(
      screen.queryByText(
        "open-loops.md has conflict markers. Resolve them, then answer here."
      )
    ).not.toBeInTheDocument()
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

  it("says when STAR was not reached (a stopped project)", async () => {
    const { user } = renderApp("/juel-claude/needs?loop=N-7")
    const detail = await screen.findByRole("region", { name: "Answer" })
    await user.click(
      (await within(detail).findAllByRole("radio"))[0] as HTMLElement
    )
    await user.click(
      within(detail).getByRole("button", { name: /Send to STAR/ })
    )
    expect(
      await screen.findByText(
        'Sent to STAR: "go". STAR reads it on its next tick.'
      )
    ).toBeInTheDocument()
    expect(
      within(detail).getByText('Sent "go". STAR reads it when it next runs.')
    ).toBeInTheDocument()
  })

  it("sends once on a double ⌘Enter", async () => {
    const { user } = renderApp("/sphere-app/needs?loop=N-41")
    const detail = await screen.findByRole("region", { name: "Answer" })
    await user.click(
      (await within(detail).findAllByRole("radio"))[0] as HTMLElement
    )
    let posts = 0
    server.events.on("request:start", ({ request }) => {
      if (request.method === "POST" && request.url.includes("/answer"))
        posts += 1
    })
    await user.keyboard("{Control>}{Enter}{Enter}{/Control}")
    await screen.findAllByText('Sent to STAR: "go". It acts on it now.')
    expect(posts).toBe(1)
    server.events.removeAllListeners()
  })

  it("shows an answer already waiting for STAR", async () => {
    const loop = getDb().loops["sphere-app"]?.find(
      (candidate) => candidate.id === "N-41"
    )
    if (!loop) throw new Error("fixture N-41 missing")
    loop.answer = "go"
    const { user } = renderApp("/sphere-app/needs?loop=N-41")
    const detail = await screen.findByRole("region", { name: "Answer" })
    expect(
      within(detail).getByText('Sent "go". Waiting for STAR to pick it up.')
    ).toBeInTheDocument()
    await user.click(
      (await within(detail).findAllByRole("radio"))[0] as HTMLElement
    )
  })

  it("keeps the loaded page when a refetch fails", async () => {
    const { user, client } = renderApp("/sphere-app/needs?loop=N-41")
    const detail = await screen.findByRole("region", { name: "Answer" })
    const box = await within(detail).findByLabelText("Or write your own")
    await user.type(box, "go except SPH-14")
    server.use(
      http.get("*/api/projects/:p/loops", () =>
        HttpResponse.json(
          { error: "Could not read open-loops.md" },
          { status: 502 }
        )
      )
    )
    await act(() =>
      client.refetchQueries({ queryKey: ["loops", "sphere-app"] })
    )
    expect(
      await screen.findByText(
        /Couldn't refresh the open loops: Could not read open-loops.md/
      )
    ).toBeInTheDocument()
    expect(box).toHaveValue("go except SPH-14")
  })

  it("refreshes when STAR changes the queue (a loops event)", async () => {
    renderApp("/sphere-app/needs")
    await screen.findByRole("tab", { name: /^All\s*9$/ })
    await waitFor(() => expect(getConnection()).toBe("open"))
    getDb().loops["sphere-app"]?.push({
      id: "N-50",
      kind: "question",
      item: "SPH-20",
      title: "A new question from the build worker",
      body: [],
      options: [],
      suggestion: null,
      answer: "",
      askedAt: null,
    })
    act(() =>
      mockEvents.emit({ type: "change", project: "sphere-app", what: "loops" })
    )
    expect(
      await screen.findByText("A new question from the build worker")
    ).toBeInTheDocument()
    expect(screen.getByRole("tab", { name: /^All\s*10$/ })).toBeInTheDocument()
  })

  it("on a phone, shows the list, opens an item on its own, and Back keeps the tab", async () => {
    phone()
    const { user, router } = renderApp("/sphere-app/needs")
    await user.click(await screen.findByRole("tab", { name: /^Slack\s*3$/ }))
    const list = screen.getByRole("region", { name: "Open loops" })
    expect(screen.queryByRole("region", { name: "Answer" })).not.toBeInTheDocument()
    await user.click(within(list).getByRole("button", { name: /Lea in #releases/ }))
    const detail = await screen.findByRole("region", { name: "Answer" })
    expect(await within(detail).findByText("which PR fixes the invoice time zone?")).toBeInTheDocument()
    expect(router.state.historyAction).toBe("PUSH")
    expect(router.state.location.search).toBe("?loop=N-48")
    expect(screen.queryByRole("region", { name: "Open loops" })).not.toBeInTheDocument()
    await user.click(within(detail).getByRole("button", { name: "Back to Needs you" }))
    const again = await screen.findByRole("region", { name: "Open loops" })
    expect(router.state.location.search).toBe("")
    expect(screen.getByRole("tab", { name: /^Slack\s*3$/ })).toHaveAttribute("aria-selected", "true")
    expect(within(again).getAllByRole("button")).toHaveLength(3)
  })

  it("fades the list in once when the tab changes", async () => {
    const { user } = renderApp("/sphere-app/needs")
    const list = await screen.findByRole("region", { name: "Open loops" })
    const before = within(list).getByRole("list")
    expect(before).toHaveClass("motion-fade-in")
    await user.click(screen.getByRole("tab", { name: /^Blocked\s*4$/ }))
    const after = within(list).getByRole("list")
    expect(after).not.toBe(before)
    expect(after).toHaveClass("motion-fade-in")
  })

  it("on a phone, Back from a linked item removes it in place", async () => {
    phone()
    const { user, router } = renderApp("/sphere-app/needs?loop=N-41")
    const detail = await screen.findByRole("region", { name: "Answer" })
    expect(screen.queryByRole("region", { name: "Open loops" })).not.toBeInTheDocument()
    await user.click(within(detail).getByRole("button", { name: "Back to Needs you" }))
    expect(await screen.findByRole("region", { name: "Open loops" })).toBeInTheDocument()
    expect(router.state.historyAction).toBe("REPLACE")
    expect(router.state.location.search).toBe("")
  })

  it("on a phone, a loop STAR already closed shows the list, not another item", async () => {
    phone()
    renderApp("/sphere-app/needs?loop=N-99")
    expect(await screen.findByRole("region", { name: "Open loops" })).toBeInTheDocument()
    expect(screen.queryByRole("region", { name: "Answer" })).not.toBeInTheDocument()
  })

  it("hides the ⌘↵ hint on touch and grows its buttons to 44 px", async () => {
    renderApp("/sphere-app/needs?loop=N-45")
    const detail = await screen.findByRole("region", { name: "Answer" })
    const send = within(detail).getByRole("button", { name: /Send to STAR/ })
    expect(within(send).getByText("⌘↵")).toHaveClass("pointer-coarse:hidden")
    expect(send).toHaveClass("pointer-coarse:h-11")
    expect(within(detail).getByRole("link", { name: /Edit the draft/ })).toHaveClass("pointer-coarse:h-11")
    expect(within(detail).getByText("slack")).toHaveClass("break-all")
  })

  it("shows a Slack item's message with its bullets and links", async () => {
    const lea = getDb().slack.routed.find((m) => m.from === "Lea")
    if (!lea) throw new Error("fixture Lea missing")
    lea.text =
      "which PR fixes the invoice time zone?\n• the bug: https://github.com/example/sphere-app/issues/88\n• the PR, if there is one"
    renderApp("/sphere-app/needs?loop=N-48")
    const detail = await screen.findByRole("region", { name: "Answer" })
    expect(await within(detail).findByRole("link", { name: "https://github.com/example/sphere-app/issues/88" })).toHaveAttribute("target", "_blank")
    expect(within(within(detail).getByRole("list")).getAllByRole("listitem")).toHaveLength(2)
  })
})
