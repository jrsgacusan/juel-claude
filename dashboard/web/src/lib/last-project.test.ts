import { act, renderHook } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"
import { lastProject, rememberProject, useLastProject } from "@/lib/last-project"

describe("last project", () => {
  it("remembers the project in the store and in localStorage", () => {
    expect(lastProject()).toBeNull()
    const { result } = renderHook(() => useLastProject())
    act(() => rememberProject("sphere-app"))
    expect(lastProject()).toBe("sphere-app")
    expect(result.current).toBe("sphere-app")
    expect(localStorage.getItem("star-last-project")).toBe("sphere-app")
  })
  it("still works for the session when storage throws", () => {
    vi.spyOn(Storage.prototype, "setItem").mockImplementation(() => {
      throw new Error("blocked")
    })
    rememberProject("sphere-app")
    expect(lastProject()).toBe("sphere-app")
  })
  it("reads the stored project on first use", () => {
    localStorage.setItem("star-last-project", "other")
    expect(lastProject()).toBe("other")
  })
})
