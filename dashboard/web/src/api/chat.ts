import { useInfiniteQuery, useMutation, useQueryClient } from "@tanstack/react-query"
import { apiJson, sendJson } from "./client"
import { keys } from "./queries"
import type { ChatSendRequest, ChatSendResponse, ChatState } from "./types"

export function chatPath(p: string, before?: string | null): string {
  const base = `/api/projects/${encodeURIComponent(p)}/chat`
  return before ? `${base}?before=${encodeURIComponent(before)}` : base
}

/** pages[0] is the newest page; the thread reads oldest first, each message once. */
export function threadOf(pages: ChatState[]): ChatState {
  const seen = new Set<string>()
  const messages = [...pages].reverse().flatMap((page) =>
    page.messages.filter((m) => {
      if (seen.has(m.id)) return false
      seen.add(m.id)
      return true
    })
  )
  return {
    messages,
    hasMore: pages[pages.length - 1]?.hasMore ?? false,
    starRunning: pages[0]?.starRunning ?? false,
  }
}

export const useChat = (p: string) =>
  useInfiniteQuery({
    queryKey: keys.chat(p),
    queryFn: ({ pageParam }) => apiJson<ChatState>(chatPath(p, pageParam)),
    initialPageParam: null as string | null,
    getNextPageParam: (last) => (last.hasMore ? (last.messages[0]?.id ?? null) : null),
    select: (data) => threadOf(data.pages),
  })

export function useSendChat(p: string) {
  const qc = useQueryClient()
  return useMutation<ChatSendResponse, Error, ChatSendRequest>({
    mutationFn: ({ text }) => sendJson<ChatSendResponse>("POST", chatPath(p), { text }),
    onSettled: () => {
      void qc.invalidateQueries({ queryKey: keys.chat(p) })
    },
  })
}
