import { act, renderHook } from "@testing-library/react"
import { expect, it } from "vitest"
import { setDetailOpen, useDetailOpen } from "@/lib/chrome"

it("follows setDetailOpen", () => {
  const { result } = renderHook(() => useDetailOpen())
  expect(result.current).toBe(false)
  act(() => setDetailOpen(true))
  expect(result.current).toBe(true)
  act(() => setDetailOpen(false))
  expect(result.current).toBe(false)
})
