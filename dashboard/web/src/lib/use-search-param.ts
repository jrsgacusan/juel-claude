import { useSearchParams } from "react-router"

export type SetSearchParam = (
  value: string | null,
  options?: { replace?: boolean; clear?: readonly string[]; state?: unknown }
) => void

/** One search param of the page's URL: read it, set it, or delete it with null. Other params stay.
 * `replace` defaults to true; `replace: false` pushes a history entry. `clear` deletes those other
 * params in the same navigation. `state` becomes the history entry's state. */
export function useSearchParam(name: string): [string | null, SetSearchParam] {
  const [params, setParams] = useSearchParams()
  const set: SetSearchParam = (value, options) =>
    setParams(
      (prev) => {
        const next = new URLSearchParams(prev)
        if (value === null) next.delete(name)
        else next.set(name, value)
        for (const other of options?.clear ?? []) next.delete(other)
        return next
      },
      { replace: options?.replace ?? true, state: options?.state }
    )
  return [params.get(name), set]
}
