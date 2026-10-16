import { useQueryClient } from "@tanstack/react-query"
import { ArrowUp, FileText, RotateCcw } from "lucide-react"
import { type ReactNode, useCallback, useEffect, useRef, useState } from "react"
import { toast } from "sonner"
import { ApiError } from "@/api/client"
import { subscribeBriefing } from "@/api/events"
import { keys, useBriefing, useSendBriefingMessage } from "@/api/queries"
import type { BriefingSummary, BriefingTurn } from "@/api/types"
import { StarMark } from "@/components/status"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"
import { Skeleton } from "@/components/ui/skeleton"
import { Textarea } from "@/components/ui/textarea"
import { errorMessage } from "@/lib/errors"
import {
  getPendingBriefing,
  setPendingBriefing,
  usePendingBriefing,
} from "@/lib/pending-briefing"
import { cn } from "@/lib/utils"

function AgentTurn({
  turn,
  streaming = false,
}: {
  turn: BriefingTurn
  streaming?: boolean
}) {
  return (
    <li
      className="flex gap-3"
      data-testid={streaming ? "agent-streaming" : undefined}
    >
      <span className="grid size-7 shrink-0 place-items-center rounded-full border bg-card">
        <StarMark className="size-3.5" />
      </span>
      <div className="flex min-w-0 flex-col gap-2">
        {turn.files && turn.files.length > 0 && (
          <div className="flex flex-wrap gap-1.5">
            {turn.files.map((file) => (
              <span
                key={file}
                className="inline-flex max-w-full items-center gap-1.5 rounded-md border bg-card px-2 py-1 font-mono text-[11px] text-muted-foreground"
              >
                <FileText className="size-3 shrink-0" />
                <span className="truncate">{`Read ${file}`}</span>
              </span>
            ))}
          </div>
        )}
        <p
          className={cn(
            "text-sm leading-6 break-words",
            streaming &&
              "animate-pulse text-muted-foreground motion-reduce:animate-none"
          )}
        >
          {turn.text}
        </p>
      </div>
    </li>
  )
}

export function Conversation({
  project,
  id,
  briefings,
  onPick,
  newButton,
}: {
  project: string
  id: string | null
  briefings: BriefingSummary[]
  onPick: (id: string) => void
  newButton: ReactNode
}) {
  const briefing = useBriefing(project, id)
  const send = useSendBriefingMessage(project, id ?? "")
  const qc = useQueryClient()
  const [text, setText] = useState("")
  const [streaming, setStreaming] = useState<BriefingTurn | null>(null)
  const pending = usePendingBriefing(project, id)
  const end = useRef<HTMLLIElement>(null)

  const refresh = useCallback(() => {
    void Promise.all([
      qc.invalidateQueries({ queryKey: keys.briefing(project, id ?? "") }),
      qc.invalidateQueries({ queryKey: keys.briefings(project) }),
    ])
  }, [id, project, qc])

  // The reply streams in as briefing events (spec D18: turn.text is the reply so far).
  useEffect(
    () =>
      subscribeBriefing((event) => {
        if (event.project !== project || event.id !== id) return
        if (event.error) {
          setStreaming(null)
          if (pending)
            setPendingBriefing(project, id ?? "", {
              ...pending,
              failed: event.error,
            })
          refresh()
          return
        }
        if (!event.turn) return
        if (event.turn.done) {
          setStreaming(null)
          setPendingBriefing(project, id ?? "", null)
          refresh()
        } else {
          setStreaming(event.turn)
        }
      }),
    [id, pending, project, refresh]
  )

  // Only data fetched after the server took the message can tell whether the turn finished.
  // Before that, busy is still false from the previous turn (briefing D7).
  useEffect(() => {
    if (
      !pending ||
      pending.failed ||
      pending.sentAt === null ||
      !briefing.data ||
      briefing.data.busy ||
      briefing.dataUpdatedAt <= pending.sentAt
    )
      return
    const lastOwner = [...briefing.data.turns]
      .reverse()
      .find((turn) => turn.who === "me")?.text
    setPendingBriefing(
      project,
      id ?? "",
      lastOwner === pending.text
        ? null
        : { ...pending, failed: "The turn did not finish." }
    )
    queueMicrotask(() => setStreaming(null))
  }, [briefing.data, id, pending, project])

  useEffect(() => {
    end.current?.scrollIntoView({ block: "end" })
  }, [briefing.data?.turns.length, streaming?.text])

  const lastMine =
    [...(briefing.data?.turns ?? [])].reverse().find((t) => t.who === "me")
      ?.text ?? ""

  const submit = async (value: string) => {
    const message = value.trim()
    if (!message || !id) return
    setPendingBriefing(project, id, {
      text: message,
      failed: null,
      sentAt: null,
    })
    try {
      await send.mutateAsync({ text: message })
      setText("")
      // The done or error event can arrive before the POST answers; then it already settled
      // the pending message, and there is nothing to mark as sent.
      const now = getPendingBriefing(project, id)
      if (now && now.text === message && !now.failed && now.sentAt === null)
        setPendingBriefing(project, id, { ...now, sentAt: Date.now() })
    } catch (error) {
      // The server took nothing: drop the pending message and put the text back in the box.
      setPendingBriefing(project, id, null)
      setText(message)
      if (error instanceof ApiError && error.status === 409)
        toast.error(
          "The agent is still answering. Wait for its reply, then send."
        )
      else toast.error(`Couldn't send it: ${errorMessage(error)}`)
    }
  }

  const current = briefings.find((b) => b.id === id)
  const showPending = pending !== null && pending.text !== lastMine

  return (
    <section
      aria-label="Conversation"
      className="flex min-h-0 min-w-0 flex-col border-b lg:border-r lg:border-b-0"
    >
      <div className="flex flex-wrap items-center justify-between gap-2 border-b px-4 py-3">
        <Select value={id ?? undefined} onValueChange={onPick}>
          <SelectTrigger
            aria-label="Briefing"
            className="h-8 w-auto max-w-full gap-2 border-0 font-medium shadow-none"
          >
            <SelectValue placeholder="Pick a briefing">
              {current?.title}
            </SelectValue>
          </SelectTrigger>
          <SelectContent>
            {briefings.map((b) => (
              <SelectItem key={b.id} value={b.id}>
                {b.title}
                {b.ref ? ` (${b.ref})` : ""}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        {newButton}
      </div>
      <div className="min-h-0 flex-1 lg:overflow-y-auto">
        <ol
          className="mx-auto flex max-w-2xl flex-col gap-6 p-4 sm:p-6"
          aria-live="polite"
        >
          {briefing.isPending &&
            id &&
            [0, 1].map((i) => (
              <li key={i}>
                <Skeleton className="h-14 w-full" />
              </li>
            ))}
          {briefing.isError && (
            <li role="alert" className="text-sm text-stop-fg">
              Couldn't load this briefing: {errorMessage(briefing.error)}
            </li>
          )}
          {briefing.data?.turns.length === 0 && !streaming && !showPending && (
            <li className="text-sm text-muted-foreground">
              Say what you want built. The agent reads the code and asks one
              question at a time.
            </li>
          )}
          {briefing.data?.turns.map((turn, i) =>
            turn.who === "me" ? (
              <li
                key={i}
                className="ml-auto max-w-[85%] rounded-2xl bg-muted px-4 py-2.5 text-sm leading-6 break-words"
              >
                {turn.text}
              </li>
            ) : (
              <AgentTurn key={i} turn={turn} />
            )
          )}
          {showPending && (
            <li className="ml-auto max-w-[85%] rounded-2xl bg-muted px-4 py-2.5 text-sm leading-6 break-words">
              {pending.text}
            </li>
          )}
          {streaming && !pending?.failed && (
            <AgentTurn turn={streaming} streaming />
          )}
          {!streaming && briefing.data?.busy && !pending?.failed && (
            <AgentTurn
              turn={{ who: "agent", text: "Reading the code for that…" }}
              streaming
            />
          )}
          {pending?.failed && (
            <li
              role="alert"
              className="flex flex-wrap items-center gap-2 rounded-lg border border-stop-line bg-stop-bg px-3 py-2 text-sm text-stop-fg"
            >
              <span className="min-w-0 flex-1 break-words">{`The briefing agent stopped: ${pending.failed}.`}</span>
              <Button
                variant="outline"
                size="sm"
                onClick={() => void submit(pending.text)}
                disabled={send.isPending}
              >
                <RotateCcw className="size-3.5" />
                Retry
              </Button>
            </li>
          )}
          <li ref={end} aria-hidden="true" />
        </ol>
      </div>
      <div className="p-3 sm:p-4">
        <div className="mx-auto max-w-2xl rounded-xl border bg-card shadow-sm focus-within:ring-2 focus-within:ring-ring">
          <label htmlFor="brief-input" className="sr-only">
            Message the briefing agent
          </label>
          <Textarea
            id="brief-input"
            rows={2}
            value={text}
            onChange={(e) => setText(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter" && !e.shiftKey) {
                e.preventDefault()
                void submit(text)
              }
            }}
            placeholder="Answer its questions, or say what to change"
            className="block min-h-0 w-full resize-none border-0 bg-transparent px-4 pt-3 shadow-none focus-visible:ring-0"
          />
          <div className="flex items-center justify-between gap-2 px-3 pb-3">
            <span className="flex min-w-0 items-center gap-2 text-xs text-muted-foreground">
              <Badge variant="outline">Opus</Badge>
              <span className="truncate">{`Reads ${project}, changes nothing`}</span>
            </span>
            <Button
              size="icon"
              className="size-8 rounded-full"
              aria-label="Send"
              onClick={() => void submit(text)}
              disabled={send.isPending || !id}
            >
              <ArrowUp />
            </Button>
          </div>
        </div>
      </div>
    </section>
  )
}
