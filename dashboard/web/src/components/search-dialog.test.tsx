import { QueryClient, QueryClientProvider } from "@tanstack/react-query"
import { render, screen, waitFor } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import {
  createMemoryRouter,
  RouterProvider,
  useLocation,
  useParams,
} from "react-router"
import { describe, expect, it } from "vitest"
import { setScenario } from "@/mocks/state"
import { resultPath, SearchDialog } from "./search-dialog"
const PLACEHOLDER = "Search items, decisions, Slack, briefings and evidence"
function Page() {
  const { project = "" } = useParams()
  const location = useLocation()
  return (
    <>
      <p data-testid="where">{location.pathname + location.search}</p>
      <SearchDialog open onOpenChange={() => {}} project={project} />
    </>
  )
}
function renderSearch() {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  })
  const router = createMemoryRouter(
    [{ path: "/:project/:page", Component: Page }],
    { initialEntries: ["/sphere-app/needs"] }
  )
  render(
    <QueryClientProvider client={client}>
      <RouterProvider router={router} />
    </QueryClientProvider>
  )
  return { user: userEvent.setup() }
}
describe("SearchDialog", () => {
  it("groups the server's results by type and highlights the query", async () => {
    const { user } = renderSearch()
    await user.type(screen.getByPlaceholderText(PLACEHOLDER), "csv")
    for (const group of [
      "Items",
      "Needs you",
      "Decisions",
      "Slack",
      "Briefings",
      "Evidence",
    ])
      expect(await screen.findByText(group)).toBeInTheDocument()
    const marks = [...document.querySelectorAll("mark")].map((m) =>
      m.textContent?.toLowerCase()
    )
    expect(marks.length).toBeGreaterThan(3)
    expect(new Set(marks)).toEqual(new Set(["csv"]))
  })
  it("moves with the arrow keys and opens the result with Enter", async () => {
    const { user } = renderSearch()
    await user.type(screen.getByPlaceholderText(PLACEHOLDER), "csv")
    await screen.findByText("Start building SPH-11, SPH-12 and SPH-14")
    await waitFor(() =>
      expect(screen.getAllByRole("option")[0]).toHaveAttribute(
        "aria-selected",
        "true"
      )
    )
    await user.keyboard("{ArrowDown}")
    expect(screen.getAllByRole("option")[1]).toHaveAttribute(
      "aria-selected",
      "true"
    )
    await user.keyboard("{Enter}")
    expect(screen.getByTestId("where")).toHaveTextContent(
      "/sphere-app/needs?loop=N-41"
    )
  })
  it("searches every project with the switch on", async () => {
    const { user } = renderSearch()
    await user.type(screen.getByPlaceholderText(PLACEHOLDER), "csv")
    await screen.findByText("Start building SPH-11, SPH-12 and SPH-14")
    expect(screen.queryByText("juel-claude, building")).not.toBeInTheDocument()
    await user.click(
      screen.getByRole("switch", { name: "Search every project" })
    )
    await user.click(await screen.findByText(/juel-claude, building/))
    expect(screen.getByTestId("where")).toHaveTextContent(
      "/juel-claude/progress?item=star-dashboard-web"
    )
  })
  it("says when nothing matches, and when the search failed", async () => {
    const { user } = renderSearch()
    const input = screen.getByPlaceholderText(PLACEHOLDER)
    await user.type(input, "zzz")
    expect(
      await screen.findByText(
        'Nothing matches "zzz". Try a ref like SPH-11 or part of a file name.'
      )
    ).toBeInTheDocument()
    setScenario("error")
    await user.type(input, "z")
    expect(
      await screen.findByText(/Search failed: Could not read ledger.md/)
    ).toBeInTheDocument()
  })
  it("routes a result as given when it starts with a slash, else under its project", () => {
    const base = { group: "Items", title: "t", sub: "s", ref: "r" }
    expect(
      resultPath({
        ...base,
        project: "sphere.api tools",
        route: "progress?item=A",
      })
    ).toBe("/sphere.api%20tools/progress?item=A")
    expect(
      resultPath({ ...base, project: "x", route: "/juel-claude/needs" })
    ).toBe("/juel-claude/needs")
  })
})
