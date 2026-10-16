import { QueryClient, QueryClientProvider, useQuery } from "@tanstack/react-query"
import { act, render, screen, within } from "@testing-library/react"
import userEvent from "@testing-library/user-event"
import { http, HttpResponse } from "msw"
import type { ReactNode } from "react"
import { describe, expect, it } from "vitest"
import { ApiError, apiJson, NetworkError } from "@/api/client"
import { setConnection } from "@/api/events"
import { paths } from "@/api/paths"
import { server } from "@/mocks/node"
import { setConflict } from "@/lib/conflict"
import { ConflictBanner, ConnectionBanner } from "./banners"
import { ErrorState } from "./page-state"

const withClient = (ui: ReactNode) =>
  render(<QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>{ui}</QueryClientProvider>)
const renderError = (error: unknown) => withClient(<ErrorState what="the items" error={error} onRetry={() => {}} />)
/** The real server's check (dashboard/server/app.ts:102-105): only `good` passes. */
const serverAccepts = (good: string) =>
  server.use(http.all("*/api/*", ({ request }) =>
    request.headers.get("X-Star-Token") === good
      ? undefined
      : HttpResponse.json({ error: "missing or wrong X-Star-Token" }, { status: 401 })))
function ProjectsProbe() {
  const projects = useQuery({ queryKey: ["projects"], queryFn: () => apiJson<unknown[]>(paths.projects()) })
  if (projects.isSuccess) return <p>Projects loaded</p>
  return projects.isError ? <ErrorState what="the projects" error={projects.error} onRetry={() => {}} /> : null
}
const WHERE = "On your Mac, run /juel:star dashboard. It prints a link that ends in ?t= and the token."
const HOW = "Paste that link here, or only the part after ?t=. This browser keeps the token, so you only do this once."
const field = () => screen.getByLabelText("Dashboard token")
const submitButton = () => screen.getByRole("button", { name: "Use this token" })

describe("ErrorState", () => {
  it("tells the owner to check the server when it did not answer", () => {
    renderError(new NetworkError("Failed to fetch"))
    expect(
      screen.getByText(
        "Check that the dashboard server is running (/juel:star dashboard), then try again."
      )
    ).toBeInTheDocument()
  })
  it("names the server's own failure for a 5xx", () => {
    renderError(
      new ApiError(502, "Could not read ledger.md: permission denied")
    )
    expect(
      screen.getByText("Could not read ledger.md: permission denied")
    ).toBeInTheDocument()
    expect(
      screen.getByText(
        "The dashboard server is running but could not read what it needs. Fix what it names, then try again."
      )
    ).toBeInTheDocument()
  })
  it("says a 404 is gone", () => {
    renderError(new ApiError(404, "No item SPH-99 in sphere-app"))
    expect(
      screen.getByText("It may have been removed or renamed. Pick another one.")
    ).toBeInTheDocument()
  })
  it("on a 401 says the token was refused and offers the paste form, not Try again", () => {
    renderError(new ApiError(401, "missing or wrong X-Star-Token"))
    expect(screen.getByText("The dashboard server refused the token.")).toBeInTheDocument()
    expect(screen.getByText(WHERE)).toBeInTheDocument()
    expect(screen.getByText(HOW)).toBeInTheDocument()
    expect(field()).toHaveClass("text-base", "md:text-sm")
    expect(submitButton()).toBeDisabled()
    expect(screen.queryByRole("button", { name: "Try again" })).not.toBeInTheDocument()
    expect(screen.queryByText(/Check that the dashboard server is running/)).not.toBeInTheDocument()
  })
})

describe("the paste-token form", () => {
  it("stores a pasted token and loads the page again with it", async () => {
    serverAccepts("0123abcd")
    const user = userEvent.setup()
    withClient(<ProjectsProbe />)
    await user.type(await screen.findByLabelText("Dashboard token"), "STAR dashboard: http://127.0.0.1:4767/?t=0123abcd")
    await user.click(submitButton())
    expect(await screen.findByText("Projects loaded")).toBeInTheDocument()
    expect(localStorage.getItem("star-token")).toBe("0123abcd")
  })
  it("shows the form again with an error when the server refuses the pasted token", async () => {
    serverAccepts("feedface") // a token no test saves: the module keeps a saved one in memory for the file
    const user = userEvent.setup()
    withClient(<ProjectsProbe />)
    await user.type(await screen.findByLabelText("Dashboard token"), "wrong")
    await user.click(submitButton())
    expect(await screen.findByText("The dashboard server refused that token. Paste the whole link /juel:star dashboard printed, so nothing is cut off.")).toBeInTheDocument()
    expect(field()).toHaveValue("wrong")
    expect(localStorage.getItem("star-token")).toBeNull()
    expect(screen.queryByText("Projects loaded")).not.toBeInTheDocument()
  })
  it("says so when the server did not answer the check", async () => {
    server.use(http.all("*/api/*", () => HttpResponse.error()))
    const user = userEvent.setup()
    renderError(new ApiError(401, "missing or wrong X-Star-Token"))
    await user.type(field(), "0123abcd")
    await user.click(submitButton())
    expect(await screen.findByText("The dashboard server did not answer. Check that it is running on your Mac, then try again.")).toBeInTheDocument()
  })
  it("the refused banner offers the form when the page shows none, without the terminal-only advice", () => {
    withClient(<ConnectionBanner />)
    act(() => setConnection("refused"))
    expect(screen.getByText("The dashboard server refused the token.")).toBeInTheDocument()
    expect(field()).toBeInTheDocument()
    expect(screen.queryByText(/Open the dashboard again/)).not.toBeInTheDocument()
  })
  it("shows one form when the banner and the page both ask, on the page", () => {
    act(() => setConnection("refused"))
    withClient(<><ConnectionBanner /><ErrorState what="the projects" error={new ApiError(401, "x")} onRetry={() => {}} /></>)
    expect(screen.getAllByLabelText("Dashboard token")).toHaveLength(1)
    expect(within(screen.getByTestId("page-error")).getByLabelText("Dashboard token")).toBeInTheDocument()
  })
})

describe("banners", () => {
  it("the conflict dismiss is 44 px on touch and keeps the banner's height", () => {
    setConflict("sphere-app")
    render(<ConflictBanner project="sphere-app" />)
    expect(screen.getByRole("button", { name: "Dismiss" })).toHaveClass("size-6", "pointer-coarse:size-11", "pointer-coarse:-my-2.5")
  })
})
