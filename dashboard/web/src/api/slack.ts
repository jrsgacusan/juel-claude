import { useMutation } from "@tanstack/react-query"
import { sendJson } from "./client"
import { paths } from "./paths"
import type { RedraftRequest, RedraftResponse } from "./types"

/** Asks the Slack drafter for a rewrite (I-10). The drafts and loops events refresh what changes. */
export const useRedraft = (p: string) =>
  useMutation<RedraftResponse, Error, RedraftRequest>({
    mutationFn: (body) =>
      sendJson<RedraftResponse>("POST", paths.slackRedraft(p), body),
  })
