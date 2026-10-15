import { beforeEach, describe, expect, it, vi } from "vitest"
import { captureToken, getToken } from "./token"

describe("captureToken", () => {
  beforeEach(() => {
    sessionStorage.clear()
    window.history.replaceState(null, "", "/")
  })
  it("returns null when there is no token anywhere", () => {
    expect(captureToken()).toBeNull()
    expect(getToken()).toBeNull()
  })
  it("keeps ?t= in sessionStorage and drops it from the visible URL", () => {
    window.history.replaceState(
      null,
      "",
      "/sphere-app/needs?t=abc123&loop=N-41#top"
    )
    expect(captureToken()).toBe("abc123")
    expect(sessionStorage.getItem("star-token")).toBe("abc123")
    expect(
      window.location.pathname + window.location.search + window.location.hash
    ).toBe("/sphere-app/needs?loop=N-41#top")
  })
  it("reads the stored token when the URL has none", () => {
    sessionStorage.setItem("star-token", "kept")
    expect(captureToken()).toBe("kept")
    expect(window.location.search).toBe("")
  })
  it("keeps the token in memory when sessionStorage cannot store it", () => {
    const setItem = vi
      .spyOn(Storage.prototype, "setItem")
      .mockImplementation(() => {
        throw new DOMException("full", "QuotaExceededError")
      })
    window.history.replaceState(null, "", "/?t=mem")
    expect(captureToken()).toBe("mem")
    expect(getToken()).toBe("mem")
    setItem.mockRestore()
  })
})
