import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"
import { apiJson, sendJson } from "./client"
import { paths } from "./paths"
import { keys } from "./queries"
import type { AwayRequest, AwayResponse, Overview } from "./types"

export const AWAY_POLL_MS = 5_000

/** The overview, polled while a change of away is waiting for STAR to apply it. */
export const useAwayState = (p: string) =>
  useQuery({
    queryKey: keys.overview(p),
    queryFn: () => apiJson<Overview>(paths.overview(p)),
    refetchInterval: (query) =>
      query.state.data?.awayPending ? AWAY_POLL_MS : false,
  })

export function useAway(p: string) {
  const client = useQueryClient()
  return useMutation<AwayResponse, Error, AwayRequest>({
    mutationFn: (body) => sendJson<AwayResponse>("POST", paths.away(p), body),
    onSuccess: () => client.invalidateQueries({ queryKey: keys.overview(p) }),
  })
}
