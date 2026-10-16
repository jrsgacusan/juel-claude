import { useChat } from "@/api/chat"
import { useOverview } from "@/api/queries"
import { useParams } from "react-router"
import { Markdown } from "@/components/markdown"
import {
  ErrorState,
  LoadingState,
  queryFailed,
  RefreshNotice,
  refreshFailed,
} from "@/components/page-state"
import { StarMark } from "@/components/status"
import { Button } from "@/components/ui/button"
import { cn } from "@/lib/utils"

/** Exactly the screen under the header below md, so the thread scrolls in its own box. */
export const FILL_HEIGHT =
  "h-[calc(100dvh_-_3.5rem_-_env(safe-area-inset-top))] md:h-auto md:min-h-0 md:flex-1"

export function ChatPage() {
  const { project = "" } = useParams()
  const chat = useChat(project)
  const overview = useOverview(project)

  if (chat.isPending) return <LoadingState label="the chat" />
  if (queryFailed(chat))
    return <ErrorState what="the chat" error={chat.error} onRetry={() => void chat.refetch()} />

  const rows = chat.data.messages
  const next = overview.data?.resume.next
  return (
    <>
      {refreshFailed(chat) && (
        <RefreshNotice what="the chat" error={chat.error} onRetry={() => void chat.refetch()} />
      )}
      <div className={cn(FILL_HEIGHT, "flex min-w-0 flex-col")}>
        {next && (
          <section
            aria-label="STAR's next step"
            className="flex shrink-0 items-center gap-2 border-b px-4 py-2"
          >
            <StarMark className="size-3.5 shrink-0" />
            <p className="min-w-0 text-xs text-muted-foreground wrap-anywhere">{next}</p>
          </section>
        )}
        <div data-testid="chat-scroll" className="min-h-0 flex-1 overflow-y-auto overscroll-contain">
          <ol
            aria-label="Chat with STAR"
            aria-live="polite"
            className="mx-auto flex max-w-2xl flex-col gap-5 p-4 sm:p-6"
          >
            {chat.hasNextPage && (
              <li className="flex justify-center">
                <Button
                  variant="ghost"
                  size="sm"
                  className="pointer-coarse:h-11"
                  disabled={chat.isFetchingNextPage}
                  onClick={() => void chat.fetchNextPage()}
                >
                  Load earlier messages
                </Button>
              </li>
            )}
            {rows.length === 0 && (
              <li className="text-sm text-muted-foreground">
                Talk to STAR the way you would in its terminal. Its replies show here.
              </li>
            )}
            {rows.map((m) =>
              m.who === "me" ? (
                <li key={m.id} data-who="me" className="motion-fade-in flex flex-col items-end gap-1">
                  <p className="max-w-[85%] rounded-2xl bg-muted px-4 py-2.5 text-sm leading-6 whitespace-pre-wrap wrap-anywhere">
                    {m.text}
                  </p>
                </li>
              ) : (
                <li key={m.id} data-who="star" className="motion-fade-in flex gap-3">
                  <span className="grid size-7 shrink-0 place-items-center rounded-full border bg-card">
                    <StarMark className="size-3.5" />
                  </span>
                  <Markdown text={m.text} />
                </li>
              )
            )}
          </ol>
        </div>
        {!chat.data.starRunning && (
          <p role="status" className="mx-auto w-full max-w-2xl shrink-0 px-4 text-xs text-wait-fg">
            STAR isn't running. Your message waits in its inbox.
          </p>
        )}
      </div>
    </>
  )
}
