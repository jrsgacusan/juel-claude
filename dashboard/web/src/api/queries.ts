import {
  keepPreviousData,
  QueryClient,
  useMutation,
  useQuery,
  useQueryClient,
} from "@tanstack/react-query"
import { setConflict } from "@/lib/conflict"
import { ApiError, apiFetch, apiJson, sendJson } from "./client"
import { paths } from "./paths"
import type {
  AnswerResponse,
  Briefing,
  BriefingSummary,
  CreateResponse,
  EvidenceDetail,
  EvidenceSummary,
  ItemDetail,
  ItemRow,
  Loop,
  NewBriefingResponse,
  Overview,
  Project,
  SearchResult,
  SlackState,
  Tracker,
  TrackerInfo,
} from "./types"
export const keys = {
  projects: ["projects"] as const,
  overview: (p: string) => ["overview", p] as const,
  loops: (p: string) => ["loops", p] as const,
  items: (p: string) => ["items", p] as const,
  item: (p: string, item: string) => ["item", p, item] as const,
  evidence: (p: string) => ["evidence", p] as const,
  evidenceItem: (p: string, item: string) => ["evidence", p, item] as const,
  slack: ["slack"] as const,
  draft: (p: string, draftPath: string) => ["draft", p, draftPath] as const,
  briefings: (p: string) => ["briefings", p] as const,
  briefing: (p: string, id: string) => ["briefing", p, id] as const,
  tracker: (p: string) => ["tracker", p] as const,
  search: (q: string, all: boolean, p: string) =>
    ["search", q, all, p] as const,
  file: (url: string) => ["file", url] as const,
}
export const retryQuery = (count: number, error: unknown): boolean =>
  !(error instanceof ApiError && error.status < 500) && count < 2

export function createQueryClient(): QueryClient {
  const client = new QueryClient({
    defaultOptions: {
      queries: {
        staleTime: 15_000,
        refetchOnWindowFocus: false,
        retry: retryQuery,
      },
    },
  })
  client.getQueryCache().subscribe((event) => {
    if (event.type !== "removed" || event.query.queryKey[0] !== "file") return
    const data = event.query.state.data as { url?: string | null } | undefined
    if (data?.url) URL.revokeObjectURL(data.url)
  })
  return client
}
export const useProjects = () =>
  useQuery({
    queryKey: keys.projects,
    queryFn: () => apiJson<Project[]>(paths.projects()),
    refetchInterval: 30_000,
  })
export const useOverview = (p: string) =>
  useQuery({
    queryKey: keys.overview(p),
    queryFn: () => apiJson<Overview>(paths.overview(p)),
  })
export const useLoops = (p: string) =>
  useQuery({
    queryKey: keys.loops(p),
    queryFn: () => apiJson<Loop[]>(paths.loops(p)),
  })
export const useItems = (p: string) =>
  useQuery({
    queryKey: keys.items(p),
    queryFn: () => apiJson<ItemRow[]>(paths.items(p)),
  })
export const useItem = (p: string, item: string | null) =>
  useQuery({
    queryKey: keys.item(p, item ?? ""),
    queryFn: () => apiJson<ItemDetail>(paths.item(p, item ?? "")),
    enabled: item !== null,
  })
export const useEvidence = (p: string) =>
  useQuery({
    queryKey: keys.evidence(p),
    queryFn: () => apiJson<EvidenceSummary[]>(paths.evidence(p)),
  })
export const useEvidenceItem = (p: string, item: string | null) =>
  useQuery({
    queryKey: keys.evidenceItem(p, item ?? ""),
    queryFn: () => apiJson<EvidenceDetail>(paths.evidenceItem(p, item ?? "")),
    enabled: item !== null,
  })
export const useSlack = () =>
  useQuery({
    queryKey: keys.slack,
    queryFn: () => apiJson<SlackState>(paths.slack()),
  })
export const useDraftText = (p: string, draftPath: string | null) =>
  useQuery({
    queryKey: keys.draft(p, draftPath ?? ""),
    queryFn: async () =>
      (await apiFetch(paths.file(p, draftPath ?? ""))).text(),
    enabled: draftPath !== null,
  })
export const useBriefings = (p: string) =>
  useQuery({
    queryKey: keys.briefings(p),
    queryFn: () => apiJson<BriefingSummary[]>(paths.briefings(p)),
  })
export const useBriefing = (p: string, id: string | null) =>
  useQuery({
    queryKey: keys.briefing(p, id ?? ""),
    queryFn: () => apiJson<Briefing>(paths.briefing(p, id ?? "")),
    enabled: id !== null,
  })
export const useTracker = (p: string) =>
  useQuery({
    queryKey: keys.tracker(p),
    queryFn: () => apiJson<TrackerInfo>(paths.tracker(p)),
  })
export const useSearch = (q: string, all: boolean, p: string) =>
  useQuery({
    queryKey: keys.search(q, all, p),
    queryFn: () =>
      apiJson<SearchResult[]>(paths.search({ q, project: p, all })),
    enabled: q.trim().length > 0,
    placeholderData: keepPreviousData,
  })
export function useAnswer(p: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ id, text }: { id: string; text: string }) =>
      sendJson<AnswerResponse>("POST", paths.answer(p, id), { text }),
    onSuccess: () => {
      setConflict(null)
      void qc.invalidateQueries({ queryKey: keys.loops(p) })
      void qc.invalidateQueries({ queryKey: keys.projects })
    },
    onError: (error) => {
      if (error instanceof ApiError && error.status === 409) setConflict(p)
    },
  })
}
const basename = (path: string) => path.split("/").pop() ?? path
export function useSaveDraft(p: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ draftPath, text }: { draftPath: string; text: string }) =>
      sendJson<unknown>("PUT", paths.draft(p, basename(draftPath)), { text }),
    onSuccess: (_data, { draftPath }) =>
      qc.invalidateQueries({ queryKey: keys.draft(p, draftPath) }),
  })
}
export function useRouteMessage() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ id, project }: { id: string; project: string }) =>
      sendJson<unknown>("POST", paths.slackRoute(id), { project }),
    onSuccess: () => qc.invalidateQueries({ queryKey: keys.slack }),
  })
}
export function useNewBriefing(p: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: () =>
      sendJson<NewBriefingResponse>("POST", paths.briefings(p), {}),
    onSuccess: () => qc.invalidateQueries({ queryKey: keys.briefings(p) }),
  })
}
export function useSendBriefingMessage(p: string, id: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ text }: { text: string }) =>
      sendJson<null>("POST", paths.briefingMessages(p, id), { text }),
    onSuccess: () => qc.invalidateQueries({ queryKey: keys.briefing(p, id) }),
  })
}
export function useCreateTicket(p: string, id: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ tracker }: { tracker: Tracker }) =>
      sendJson<CreateResponse>("POST", paths.briefingCreate(p, id), {
        tracker,
      }),
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: keys.briefings(p) })
      void qc.invalidateQueries({ queryKey: keys.briefing(p, id) })
      void qc.invalidateQueries({ queryKey: keys.loops(p) })
    },
  })
}
export function useSetTracker(p: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ tracker }: { tracker: Tracker }) =>
      sendJson<unknown>("PUT", paths.tracker(p), { tracker }),
    onSuccess: (_data, { tracker }) => {
      qc.setQueryData<TrackerInfo>(keys.tracker(p), (old) => ({
        ...(old ?? {}),
        tracker,
      }))
    },
  })
}
