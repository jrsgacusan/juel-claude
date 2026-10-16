import { useSearchParams } from "react-router"

/** One search param of the page's URL: read it, set it, or delete it with null. Other params stay. */
export function useSearchParam(
  name: string
): [
  string | null,
  (value: string | null, options?: { replace?: boolean }) => void,
] {
  const [params, setParams] = useSearchParams()
  const set = (value: string | null, options?: { replace?: boolean }) =>
    setParams(
      (prev) => {
        const next = new URLSearchParams(prev)
        if (value === null) next.delete(name)
        else next.set(name, value)
        return next
      },
      { replace: options?.replace ?? true }
    )
  return [params.get(name), set]
}
