import { useState } from "react"

export const PAGE_SIZE = 10

type Options = {
  pageSize?: number
  resetKey?: unknown
  focusIndex?: number | null
}

const asFocus = (value: number | null | undefined): number | null =>
  typeof value === "number" && value >= 0 ? value : null

/** Pages a list (1-based). The page clamps when the list shrinks, returns to 1 when
 * `resetKey` changes, and follows `focusIndex` to the page that holds it. */
export function usePage<T>(items: readonly T[], opts: Options = {}) {
  const pageSize = opts.pageSize ?? PAGE_SIZE
  const pageCount = Math.max(1, Math.ceil(items.length / pageSize))
  const focus = asFocus(opts.focusIndex)
  const [state, setState] = useState(() => ({
    page: focus === null ? 1 : Math.floor(focus / pageSize) + 1,
    resetKey: opts.resetKey,
    focus,
  }))

  // Adjust state while rendering when an input changed (React's "adjust state on a prop change").
  let next = state
  if (focus !== state.focus || !Object.is(opts.resetKey, state.resetKey)) {
    const page =
      focus !== null && focus !== state.focus
        ? Math.floor(focus / pageSize) + 1
        : !Object.is(opts.resetKey, state.resetKey)
          ? 1
          : state.page
    next = { page, resetKey: opts.resetKey, focus }
  }
  if (next.page > pageCount) next = { ...next, page: pageCount }
  if (next !== state) setState(next)

  const page = Math.min(Math.max(next.page, 1), pageCount)
  const setPage = (value: number) =>
    setState((s) => ({ ...s, page: Math.min(Math.max(value, 1), pageCount) }))
  const pageItems = items.slice((page - 1) * pageSize, page * pageSize)
  return { page, pageCount, pageItems, setPage }
}
