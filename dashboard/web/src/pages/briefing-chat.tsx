import { useQueryClient } from "@tanstack/react-query"
import { FileText, RotateCcw, Trash2 } from "lucide-react"
import { type ReactNode, useCallback, useEffect, useState } from "react"
import { toast } from "sonner"
import { ApiError } from "@/api/client"
import { useDeleteBriefing } from "@/api/briefings"
import { subscribeBriefing } from "@/api/events"
import { keys, useBriefing, useSendBriefingMessage } from "@/api/queries"
import type { BriefingSummary, BriefingTurn } from "@/api/types"
import { Markdown } from "@/components/markdown"
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
import { errorMessage } from "@/lib/errors"
import {
  getPendingBriefing,
  setPendingBriefing,
  usePendingBriefing,
} from "@/lib/pending-briefing"
import { cn } from "@/lib/utils"
import { Composer, useStickToBottom } from "./chat"

/** When a message was sent; read in the send handler, never during render. */
const sentNow = (): number => Date.now()

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
        <Markdown
          text={turn.text}
          className={cn(streaming && "motion-breathe text-muted-foreground")}
        />
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
  onDeleted,
  className,
}: {
  project: string
  id: string | null
  briefings: BriefingSummary[]
  onPick: (id: string) => void
  newButton: ReactNode
  onDeleted: () => void
  className?: string
}) {
  const briefing = useBriefing(project, id)
  const send = useSendBriefingMessage(project, id ?? "")
  const qc = useQueryClient()
  const remove = useDeleteBriefing(project)
  const [confirming, setConfirming] = useState<{ id: string; title: string } | null>(null)
  const [deleteError, setDeleteError] = useState<string | null>(null)
  const [text, setText] = useState("")
  const [streaming, setStreaming] = useState<BriefingTurn | null>(null)
  const pending = usePendingBriefing(project, id)

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
  }, [briefing.data, briefing.dataUpdatedAt, id, pending, project])

  const lastMine =
    [...(briefing.data?.turns ?? [])].reverse().find((t) => t.who === "me")
      ?.text ?? ""
  // A message is in flight until its turn ends (done, error or a refetch says so): the server
  // takes one turn at a time (briefing D7), so the composer holds the next message until then.
  const inFlight = pending !== null && pending.failed === null

  const submit = async (value: string) => {
    const message = value.trim()
    if (!message || !id || inFlight) return
    pin()
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
        setPendingBriefing(project, id, { ...now, sentAt: sentNow() })
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
  const { ref, onScroll, pin } = useStickToBottom(
    `${briefing.data?.turns.length ?? 0}:${streaming?.text.length ?? 0}:${showPending}:${briefing.data?.busy ?? false}`
  )

  return (
    <section
      aria-label="Conversation"
      className={cn(
        "flex min-h-0 min-w-0 flex-col border-b lg:border-r lg:border-b-0",
        className
      )}
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
        {current?.deletable && !briefing.data?.busy && !inFlight && !confirming && (
          <Button
            variant="ghost"
            size="sm"
            className="pointer-coarse:h-11"
            onClick={() => {
              setDeleteError(null)
              setConfirming({ id: current.id, title: current.title })
            }}
          >
            <Trash2 className="size-3.5" />
            Delete
          </Button>
        )}
        {newButton}
      </div>
      {confirming && (
        <div
          role="group"
          aria-label="Delete this briefing"
          className="flex flex-col gap-2 border-b bg-stop-bg px-4 py-3 text-sm text-stop-fg"
        >
          <p className="wrap-anywhere">{`Delete "${confirming.title}"? This removes its chat and draft. Tickets, inbox files and STAR's rows stay.`}</p>
          {deleteError && <p role="alert">{`Couldn't delete this briefing: ${deleteError}`}</p>}
          <div className="flex flex-wrap gap-2">
            <Button
              variant="destructive"
              size="sm"
              className="pointer-coarse:h-11"
              disabled={remove.isPending}
              onClick={() =>
                remove.mutate(
                  { id: confirming.id },
                  {
                    onSuccess: () => {
                      setPendingBriefing(project, confirming.id, null)
                      toast.success(`Deleted "${confirming.title}".`)
                      setConfirming(null)
                      onDeleted()
                    },
                    onError: (error) => setDeleteError(errorMessage(error)),
                  }
                )
              }
            >
              Delete briefing
            </Button>
            <Button
              variant="outline"
              size="sm"
              className="pointer-coarse:h-11"
              onClick={() => {
                setConfirming(null)
                setDeleteError(null)
              }}
            >
              Keep it
            </Button>
          </div>
        </div>
      )}
      <div
        ref={ref}
        onScroll={onScroll}
        data-testid="briefing-scroll"
        className="min-h-0 flex-1 overflow-y-auto overscroll-contain"
      >
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
            <li
              role="alert"
              className="flex flex-wrap items-center gap-2 text-sm text-stop-fg"
            >
              <span className="min-w-0 flex-1 break-words">
                {`Couldn't load this briefing: ${errorMessage(briefing.error)}. Check that the dashboard server is running, then try again.`}
              </span>
              <Button
                variant="outline"
                size="sm"
                className="pointer-coarse:h-11"
                onClick={() => void briefing.refetch()}
              >
                Try again
              </Button>
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
                className="ml-auto max-w-[85%] rounded-2xl bg-muted px-4 py-2.5 text-sm leading-6 whitespace-pre-wrap wrap-anywhere"
              >
                {turn.text}
              </li>
            ) : (
              <AgentTurn key={i} turn={turn} />
            )
          )}
          {showPending && (
            <li className="ml-auto max-w-[85%] rounded-2xl bg-muted px-4 py-2.5 text-sm leading-6 whitespace-pre-wrap wrap-anywhere">
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
        </ol>
      </div>
      <Composer
        inputId="brief-input"
        label="Message the briefing agent"
        placeholder="Answer its questions, or say what to change"
        value={text}
        onChange={setText}
        onSend={() => void submit(text)}
        sendDisabled={send.isPending || !id || inFlight}
        footer={
          <span className="flex min-w-0 items-center gap-2 text-xs text-muted-foreground">
            <Badge variant="outline">Opus</Badge>
            <span className="truncate">{`Reads ${project}, changes nothing`}</span>
          </span>
        }
      />
    </section>
  )
}
