import { useMutation, useQueryClient } from "@tanstack/react-query"
import { sendJson } from "./client"
import { paths } from "./paths"
import { keys } from "./queries"
import type { RedraftRequest, RedraftResponse } from "./types"

/** Asks the Slack drafter for a rewrite (I-10). The drafts and loops events refresh what changes. */
export const useRedraft = (p: string) =>
  useMutation<RedraftResponse, Error, RedraftRequest>({
    mutationFn: (body) =>
      sendJson<RedraftResponse>("POST", paths.slackRedraft(p), body),
  })

/** Flips the "Check Slack" switch (spec 3.14); the Slack query refetches what the server holds. */
export function useSlackPaused() {
  const client = useQueryClient()
  return useMutation<{ paused: boolean }, Error, { paused: boolean }>({
    mutationFn: (body) =>
      sendJson<{ paused: boolean }>("PUT", paths.slackPaused(), body),
    onSettled: () => client.invalidateQueries({ queryKey: keys.slack }),
  })
}
