import { act, renderHook } from "@testing-library/react"
import { describe, expect, it } from "vitest"
import { PAGE_SIZE, usePage } from "./paginate"

const range = (n: number) => Array.from({ length: n }, (_, i) => i)

describe("usePage", () => {
  it("pages ten at a time from page 1, one empty page for nothing, or another size", () => {
    expect(PAGE_SIZE).toBe(10)
    const ten = renderHook(() => usePage(range(25))).result.current
    expect(ten).toMatchObject({ page: 1, pageCount: 3, pageItems: range(10) })
    const none = renderHook(() => usePage([])).result.current
    expect(none).toMatchObject({ page: 1, pageCount: 1, pageItems: [] })
    const four = renderHook(() => usePage(range(10), { pageSize: 4 })).result.current
    expect(four).toMatchObject({ pageCount: 3, pageItems: [0, 1, 2, 3] })
  })
  it("moves with setPage and stays inside the pages", () => {
    const { result } = renderHook(() => usePage(range(25)))
    act(() => result.current.setPage(3))
    expect(result.current.pageItems).toEqual([20, 21, 22, 23, 24])
    act(() => result.current.setPage(0))
    expect(result.current.page).toBe(1)
    act(() => result.current.setPage(9))
    expect(result.current.page).toBe(3)
  })
  it("clamps when the list shrinks, and stays there when it grows back", () => {
    const { result, rerender } = renderHook(({ items }) => usePage(items), {
      initialProps: { items: range(25) },
    })
    act(() => result.current.setPage(3))
    rerender({ items: range(12) })
    expect(result.current.page).toBe(2)
    expect(result.current.pageItems).toEqual([10, 11])
    rerender({ items: range(25) })
    expect(result.current.page).toBe(2)
    rerender({ items: [] })
    expect(result.current).toMatchObject({ page: 1, pageCount: 1 })
  })
  it("goes back to page 1 when resetKey changes, and only then", () => {
    const { result, rerender } = renderHook(
      ({ tab }) => usePage(range(25), { resetKey: tab }),
      { initialProps: { tab: "all" } }
    )
    act(() => result.current.setPage(3))
    rerender({ tab: "all" })
    expect(result.current.page).toBe(3)
    rerender({ tab: "running" })
    expect(result.current.page).toBe(1)
  })
  it("opens on the page that holds focusIndex and follows it when it changes", () => {
    const { result, rerender } = renderHook(
      ({ focus }: { focus: number | null }) =>
        usePage(range(25), { focusIndex: focus }),
      { initialProps: { focus: 23 as number | null } }
    )
    expect(result.current.page).toBe(3)
    rerender({ focus: 5 })
    expect(result.current.page).toBe(1)
    act(() => result.current.setPage(2))
    rerender({ focus: 5 })
    expect(result.current.page).toBe(2)
    rerender({ focus: null })
    expect(result.current.page).toBe(2)
    rerender({ focus: -1 })
    expect(result.current.page).toBe(2)
  })
  it("lets focusIndex win when it and resetKey change together", () => {
    const { result, rerender } = renderHook(
      ({ tab, focus }: { tab: string; focus: number | null }) =>
        usePage(range(25), { resetKey: tab, focusIndex: focus }),
      { initialProps: { tab: "a", focus: null as number | null } }
    )
    rerender({ tab: "b", focus: 15 })
    expect(result.current.page).toBe(2)
  })
})
