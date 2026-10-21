import { Navigate, useParams, useSearchParams } from "react-router"

/** /:project/needs: the project's items now live in the combined Needs you, filtered to it. */
export function NeedsRedirect() {
  const { project = "" } = useParams()
  const [search] = useSearchParams()
  const next = new URLSearchParams({ project })
  search.forEach((value, key) => {
    if (key !== "project") next.set(key, value)
  })
  return <Navigate to={`/needs?${next.toString()}`} replace />
}
