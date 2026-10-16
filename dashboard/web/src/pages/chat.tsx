import { ArrowUp } from "lucide-react"
import {
  type KeyboardEvent,
  type ReactNode,
  type RefObject,
  useLayoutEffect,
  useRef,
  useState,
} from "react"
import { useParams } from "react-router"
import { toast } from "sonner"
import { useChat, useSendChat } from "@/api/chat"
import { useOverview, useProjects } from "@/api/queries"
import type { ChatMessage } from "@/api/types"
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
import { Textarea } from "@/components/ui/textarea"
import { errorMessage } from "@/lib/errors"
import { cn } from "@/lib/utils"

/** Takes what is left of the screen under the header and banners (the layout is a dvh-tall column below md), so the thread scrolls in its own box. */
export const FILL_HEIGHT = "min-h-0 flex-1"

/** Enter sends on a fine pointer; on a touch screen it makes a newline and only Send sends. */
export function enterSends(event: KeyboardEvent<HTMLTextAreaElement>): boolean {
  return (
    event.key === "Enter" &&
    !event.shiftKey &&
    !event.nativeEvent.isComposing &&
    !window.matchMedia("(pointer: coarse)").matches
  )
}

/** Keeps a scroll box at its bottom while the reader is there; never touches the window. */
export function useStickToBottom(change: unknown): {
  ref: RefObject<HTMLDivElement | null>
  onScroll: () => void
  pin: () => void
} {
  const ref = useRef<HTMLDivElement>(null)
  const atBottom = useRef(true)
  const onScroll = () => {
    const box = ref.current
    if (box) atBottom.current = box.scrollHeight - box.clientHeight - box.scrollTop <= 80
  }
  const pin = () => {
    atBottom.current = true
  }
  useLayoutEffect(() => {
    const box = ref.current
    if (box && atBottom.current) box.scrollTop = box.scrollHeight
  }, [change])
  return { ref, onScroll, pin }
}

export function withPending(messages: ChatMessage[], pending: ChatMessage | null): ChatMessage[] {
  if (!pending || messages.some((m) => m.id === pending.id)) return messages
  return [...messages, pending]
}

export function Composer({
  inputId,
  label,
  placeholder,
  value,
  onChange,
  onSend,
  sendDisabled,
  maxLength,
  footer,
}: {
  inputId: string
  label: string
  placeholder: string
  value: string
  onChange: (value: string) => void
  onSend: () => void
  sendDisabled: boolean
  maxLength?: number
  footer?: ReactNode
}) {
  return (
    <div className="shrink-0 p-3 pb-[max(0.75rem,env(safe-area-inset-bottom))] sm:p-4">
      <div className="mx-auto max-w-2xl rounded-xl border bg-card shadow-sm focus-within:ring-2 focus-within:ring-ring">
        <label htmlFor={inputId} className="sr-only">
          {label}
        </label>
        <Textarea
          id={inputId}
          rows={2}
          value={value}
          maxLength={maxLength}
          onChange={(e) => onChange(e.target.value)}
          onKeyDown={(e) => {
            if (enterSends(e)) {
              e.preventDefault()
              onSend()
            }
          }}
          placeholder={placeholder}
          className="block min-h-0 w-full resize-none border-0 bg-transparent px-4 pt-3 text-base shadow-none focus-visible:ring-0 md:text-sm"
        />
        <div className="flex items-center justify-between gap-2 px-3 pb-3">
          {footer ?? <span />}
          <Button
            size="icon"
            className="size-8 rounded-full pointer-coarse:size-11"
            aria-label="Send"
            onClick={onSend}
            disabled={sendDisabled}
          >
            <ArrowUp />
          </Button>
        </div>
      </div>
    </div>
  )
}

export function ChatPage() {
  const { project = "" } = useParams()
  const chat = useChat(project)
  const overview = useOverview(project)
  const projects = useProjects()
  const send = useSendChat(project)
  const [text, setText] = useState("")

  const pendingRow: ChatMessage | null =
    send.variables && (send.isPending || send.isSuccess)
      ? { id: send.data?.id ?? "pending", who: "me", at: "", replyTo: null, text: send.variables.text }
      : null
  const rows = withPending(chat.data?.messages ?? [], pendingRow)
  const { ref, onScroll, pin } = useStickToBottom(`${rows.length}:${rows.at(-1)?.id ?? ""}`)

  if (chat.isPending) return <LoadingState label="the chat" />
  if (queryFailed(chat))
    return <ErrorState what="the chat" error={chat.error} onRetry={() => void chat.refetch()} />

  const submit = () => {
    const message = text.trim()
    if (!message || send.isPending) return
    setText("")
    pin()
    send.mutate(
      { text: message },
      {
        onError: (error) => {
          setText(message)
          toast.error(`Couldn't send it: ${errorMessage(error)}`)
        },
      }
    )
  }
  // The projects query follows STAR's start and stop (as the AwaySwitch does); the chat payload only
  // refetches on a chat event or a send, so it is the fallback while the projects load.
  const current = projects.data?.find((p) => p.name === project)
  const starRunning = current ? current.state !== "stopped" : (chat.data?.starRunning ?? true)
  const answered = new Set(rows.flatMap((m) => (m.who === "star" && m.replyTo ? [m.replyTo] : [])))
  const next = overview.data?.resume.next
  return (
    <>
      {refreshFailed(chat) && (
        <RefreshNotice what="the chat" error={chat.error} onRetry={() => void chat.refetch()} />
      )}
      <div className={cn(FILL_HEIGHT, "flex min-w-0 flex-col")}>
        <h1 className="sr-only">Chat with STAR</h1>
        {next && (
          <section
            aria-label="STAR's next step"
            className="flex shrink-0 items-center gap-2 border-b px-4 py-2"
          >
            <StarMark className="size-3.5 shrink-0" />
            <p className="min-w-0 text-xs text-muted-foreground wrap-anywhere">{next}</p>
          </section>
        )}
        <div ref={ref} onScroll={onScroll} data-testid="chat-scroll" className="min-h-0 flex-1 overflow-y-auto overscroll-contain">
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
                  {!answered.has(m.id) &&
                    (starRunning ? (
                      <p className="flex items-center gap-1.5 text-xs text-muted-foreground">
                        <span aria-hidden="true" className="motion-breathe size-1.5 rounded-full bg-run" />
                        STAR is reading…
                      </p>
                    ) : (
                      <p className="text-xs text-muted-foreground">Waits for STAR's next start</p>
                    ))}
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
        {!starRunning && (
          <p role="status" className="mx-auto w-full max-w-2xl shrink-0 px-4 text-xs text-wait-fg">
            STAR isn't running. Your message waits in its inbox.
          </p>
        )}
        <Composer
          inputId="chat-input"
          label="Message STAR"
          placeholder="Ask STAR, or tell it what to do"
          maxLength={8000}
          value={text}
          onChange={setText}
          onSend={submit}
          sendDisabled={send.isPending}
        />
      </div>
    </>
  )
}
