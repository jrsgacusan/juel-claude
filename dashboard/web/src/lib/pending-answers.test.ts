import { act, renderHook } from "@testing-library/react"
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest"
import { HOLD_MS, holdAnswer, undoAnswer, usePending } from "@/lib/pending-answers"

beforeEach(() => vi.useFakeTimers())
afterEach(() => vi.useRealTimers())

const hide = (event: "visibilitychange" | "pagehide") => {
  if (event === "visibilitychange")
    vi.spyOn(document, "visibilityState", "get").mockReturnValue("hidden")
  document.dispatchEvent(new Event(event))
  window.dispatchEvent(new Event(event))
}

describe("pending answers", () => {
  it("holds for 5 seconds, then sends once", async () => {
    let resolve!: () => void
    const send = vi.fn(() => new Promise<void>((r) => (resolve = r)))
    const { result } = renderHook(() => usePending("a"))
    act(() => holdAnswer("a", send))
    expect(HOLD_MS).toBe(5000)
    expect(result.current).toBe("held")
    act(() => void vi.advanceTimersByTime(4999))
    expect(send).not.toHaveBeenCalled()
    act(() => void vi.advanceTimersByTime(1))
    expect(send).toHaveBeenCalledTimes(1)
    expect(result.current).toBe("sending")
    await act(async () => resolve())
    expect(result.current).toBeNull()
  })

  it("undo before the send cancels it, and returns false after", async () => {
    const send = vi.fn(() => Promise.resolve())
    const { result } = renderHook(() => usePending("a"))
    act(() => holdAnswer("a", send))
    let undone = false
    act(() => void (undone = undoAnswer("a")))
    expect(undone).toBe(true)
    expect(result.current).toBeNull()
    act(() => void vi.advanceTimersByTime(10_000))
    expect(send).not.toHaveBeenCalled()

    act(() => holdAnswer("a", send))
    await act(async () => void vi.advanceTimersByTime(HOLD_MS))
    expect(undoAnswer("a")).toBe(false)
  })

  it("holding the same key twice keeps only the second answer", () => {
    const first = vi.fn(() => Promise.resolve())
    const second = vi.fn(() => Promise.resolve())
    act(() => holdAnswer("a", first))
    act(() => void vi.advanceTimersByTime(3000))
    act(() => holdAnswer("a", second))
    act(() => void vi.advanceTimersByTime(HOLD_MS))
    expect(first).not.toHaveBeenCalled()
    expect(second).toHaveBeenCalledTimes(1)
  })

  for (const event of ["visibilitychange", "pagehide"] as const)
    it(`posts at once on ${event} and not again at 5 seconds`, () => {
      const send = vi.fn(() => Promise.resolve())
      act(() => holdAnswer("a", send))
      act(() => hide(event))
      expect(send).toHaveBeenCalledTimes(1)
      act(() => void vi.advanceTimersByTime(10_000))
      expect(send).toHaveBeenCalledTimes(1)
    })

  it("keeps two keys independent", () => {
    const a = vi.fn(() => Promise.resolve())
    const b = vi.fn(() => Promise.resolve())
    act(() => holdAnswer("a", a))
    act(() => holdAnswer("b", b))
    act(() => void undoAnswer("a"))
    act(() => void vi.advanceTimersByTime(HOLD_MS))
    expect(a).not.toHaveBeenCalled()
    expect(b).toHaveBeenCalledTimes(1)
  })

  it("leaves the store when the send rejects", async () => {
    const { result } = renderHook(() => usePending("a"))
    act(() => holdAnswer("a", () => Promise.reject(new Error("no"))))
    await act(async () => void vi.advanceTimersByTime(HOLD_MS))
    expect(result.current).toBeNull()
  })

  it("still sends after the component that held it is gone", () => {
    const send = vi.fn(() => Promise.resolve())
    const { unmount } = renderHook(() => usePending("a"))
    act(() => holdAnswer("a", send))
    unmount()
    act(() => void vi.advanceTimersByTime(HOLD_MS))
    expect(send).toHaveBeenCalledTimes(1)
  })
})
