import { render, screen } from "@testing-library/react"
import { describe, expect, it } from "vitest"
import { ApiError, NetworkError } from "@/api/client"
import { ErrorState } from "./page-state"

const renderError = (error: unknown) =>
  render(<ErrorState what="the items" error={error} onRetry={() => {}} />)

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
  it("gives only the token advice on a 401", () => {
    renderError(new ApiError(401, "no token"))
    expect(screen.getByText(/refused the token/)).toBeInTheDocument()
    expect(
      screen.queryByText(/Check that the dashboard server is running/)
    ).not.toBeInTheDocument()
  })
})
