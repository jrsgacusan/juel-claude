import { useMutation, useQueryClient } from "@tanstack/react-query"
import { ApiError, apiJson } from "./client"
import { paths } from "./paths"
import { keys } from "./queries"

export type DeleteBriefingResponse = { deleted: true }

export function useDeleteBriefing(p: string) {
  const qc = useQueryClient()
  return useMutation<DeleteBriefingResponse, Error, { id: string }>({
    mutationFn: ({ id }) => apiJson<DeleteBriefingResponse>(paths.briefing(p, id), { method: "DELETE" }),
    onSuccess: () => qc.invalidateQueries({ queryKey: keys.briefings(p) }),
    onError: (error) => {
      if (error instanceof ApiError && error.status === 409)
        void qc.invalidateQueries({ queryKey: keys.briefings(p) })
    },
  })
}
