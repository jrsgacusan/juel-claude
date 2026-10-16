import { RefreshCw, Send } from "lucide-react"
import { useEffect, useRef, useState } from "react"
import { toast } from "sonner"
import { ApiError } from "@/api/client"
import {
  useAnswer,
  useDraftText,
  useProjects,
  useRouteMessage,
  useSaveDraft,
} from "@/api/queries"
import type { RoutedMessage, UnroutedMessage } from "@/api/types"
import { StarMark } from "@/components/status"
import { Avatar, AvatarFallback } from "@/components/ui/avatar"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
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
import { clock, slackTime } from "@/lib/format"

const CHIPS = ["Shorter", "Add the PR link", "Less formal"]
/** A draft file is "to: slack <channelId> <threadTs or ts>" and then the reply. */
const replyOf = (file: string) => file.split("\n").slice(1).join("\n")
const splitLine = (line: string): [string, string] => {
  const at = line.indexOf(": ")
  return at > 0 ? [line.slice(0, at), line.slice(at + 2)] : ["", line]
}

function Person({ name, className }: { name: string; className?: string }) {
  return (
    <Avatar className={className}>
      <AvatarFallback className="text-xs font-semibold">
        {name.slice(0, 1).toUpperCase()}
      </AvatarFallback>
    </Avatar>
  )
}

export function RoutedDetail({
  project,
  message,
  onDone,
}: {
  project: string
  message: RoutedMessage
  onDone: (mark: string) => void
}) {
  const draft = useDraftText(project, message.draftPath)
  const save = useSaveDraft(project)
  const answer = useAnswer(project)
  const [edited, setEdited] = useState<string | null>(null)
  const [ask, setAsk] = useState("")
  const pendingSave = useRef<Promise<boolean> | null>(null)
  const saved = draft.data !== undefined ? replyOf(draft.data) : ""
  const value = edited ?? saved
  const when = slackTime(message.id)
  const editedRef = useRef(edited)
  const savedRef = useRef(saved)
  useEffect(() => {
    editedRef.current = edited
    savedRef.current = saved
  }, [edited, saved])
  const ready = draft.isSuccess

  // brief D7: saved on blur when changed, and before Send reply; a failed save never sends.
  const persist = async (): Promise<boolean> => {
    // Wait for that save and then save again when the text changed while it was in flight.
    if (pendingSave.current && !(await pendingSave.current)) return false
    const currentEdited = editedRef.current
    const currentSaved = savedRef.current
    if (
      !message.draftPath ||
      currentEdited === null ||
      currentEdited === currentSaved
    )
      return true
    const operation = save
      .mutateAsync({ draftPath: message.draftPath, text: currentEdited })
      .then(() => {
        if (editedRef.current === currentEdited) setEdited(null)
        return true
      })
      .catch((error: unknown) => {
        toast.error(`Couldn't save the draft: ${errorMessage(error)}`)
        return false
      })
      .finally(() => {
        pendingSave.current = null
      })
    pendingSave.current = operation
    return operation
  }

  const answerLoop = async (
    text: string,
    success: string,
    mark?: string,
    onSuccess?: () => void
  ) => {
    if (!message.loopId) return
    try {
      const res = await answer.mutateAsync({ id: message.loopId, text })
      if (mark) onDone(mark)
      onSuccess?.()
      toast.success(
        res.nudged === false && text === "send"
          ? `Queued. STAR posts it to ${message.channel} as you when it next runs.`
          : success
      )
    } catch (error) {
      // A 409 raises the conflict banner (useAnswer).
      if (!(error instanceof ApiError && error.status === 409))
        toast.error(`Couldn't send it to STAR: ${errorMessage(error)}`)
    }
  }

  const sendReply = async () => {
    if (!ready || !message.loopId) return
    if (await persist())
      await answerLoop(
        "send",
        `Sent. STAR posts it to ${message.channel} as you.`,
        "Sent"
      )
  }
  const rewrite = (how: string) => {
    if (!ready || !message.loopId) return
    const text = how.trim()
    if (!text) {
      toast("Tell STAR what to change first.")
      return
    }
    void answerLoop(
      `rewrite: ${text}`,
      `STAR is rewriting it: "${text}".`,
      undefined,
      () => {
        setEdited(null)
        setAsk("")
      }
    )
  }
  const disabled = !ready || !message.loopId || answer.isPending
  const saveStatus = () => {
    if (save.isPending) return "Saving…"
    if (save.isError) return "Not saved"
    if (edited !== null) return ""
    if (save.isSuccess) return "Saved"
    return ""
  }

  return (
    <div className="mx-auto flex max-w-3xl flex-col gap-5 p-4 sm:p-6 lg:p-8">
      <div className="flex items-center gap-3">
        <Person name={message.from} className="size-10" />
        <div className="min-w-0">
          <h2 className="text-lg font-semibold break-words">
            {message.from}{" "}
            <span className="font-normal text-muted-foreground">
              in {message.channel}
            </span>
          </h2>
          <p className="text-xs text-muted-foreground">
            Routed to {message.project}
          </p>
        </div>
      </div>
      <ol className="flex flex-col gap-3">
        {[
          ...message.thread.map(splitLine),
          [message.from, message.text] as [string, string],
        ].map(([who, text], i, all) => (
          <li key={i} className="flex gap-3">
            <Person name={who || "?"} className="size-7" />
            <div className="flex min-w-0 flex-col">
              <span className="text-xs">
                <span className="font-medium">{who}</span>{" "}
                {i === all.length - 1 && when && (
                  <span className="text-muted-foreground tabular-nums">
                    {clock(when)}
                  </span>
                )}
              </span>
              <span className="text-sm leading-6 break-words">{text}</span>
            </div>
          </li>
        ))}
      </ol>
      {message.draftPath ? (
        <Card className="gap-0 overflow-hidden p-0 focus-within:ring-2 focus-within:ring-ring">
          <div className="flex items-center justify-between gap-2 border-b px-4 py-2 text-xs text-muted-foreground">
            <span>Reply in {message.channel} as you</span>
            <Badge variant="secondary">
              <StarMark className="size-3" />
              Drafted by STAR
            </Badge>
          </div>
          {draft.isPending ? (
            <Skeleton className="m-4 h-20" />
          ) : draft.isError ? (
            <div
              role="alert"
              className="flex items-center justify-between gap-3 p-4 text-sm text-stop-fg"
            >
              <span>Couldn't load the draft: {errorMessage(draft.error)}</span>
              <Button
                variant="outline"
                size="sm"
                onClick={() => void draft.refetch()}
              >
                Try again
              </Button>
            </div>
          ) : (
            <Textarea
              aria-label="Your reply"
              rows={3}
              value={value}
              onChange={(e) => setEdited(e.target.value)}
              onBlur={() => void persist()}
              className="block min-h-[96px] w-full resize-y rounded-none border-0 px-4 py-3 text-[15px] leading-7 shadow-none focus-visible:ring-0"
            />
          )}
          <div className="flex flex-wrap items-center justify-between gap-2 border-t px-3 py-2">
            <p className="text-xs text-muted-foreground" aria-live="polite">
              {saveStatus()}
            </p>
            <div className="flex gap-2">
              <Button
                variant="ghost"
                size="sm"
                disabled={disabled}
                onClick={() =>
                  void answerLoop(
                    "skip",
                    "Skipped. The watcher will not raise it again.",
                    "Skipped"
                  )
                }
              >
                Skip
              </Button>
              <Button
                size="sm"
                disabled={disabled}
                onClick={() => void sendReply()}
              >
                <Send className="size-3.5" />
                Send reply
              </Button>
            </div>
          </div>
        </Card>
      ) : (
        <p className="rounded-xl border border-dashed p-4 text-sm text-muted-foreground">
          STAR hasn't drafted a reply yet. It drafts one on its next tick.
        </p>
      )}
      <div className="flex flex-col gap-2">
        <Label htmlFor={`ask-${message.id}`}>Ask STAR to rewrite it</Label>
        <div className="flex gap-2">
          <Input
            id={`ask-${message.id}`}
            value={ask}
            onChange={(e) => setAsk(e.target.value)}
            placeholder="Shorter, add the PR link, less formal"
            className="h-9"
          />
          <Button
            variant="outline"
            disabled={disabled}
            onClick={() => rewrite(ask)}
          >
            <RefreshCw className="size-3.5" />
            Rewrite
          </Button>
        </div>
        <div className="flex flex-wrap gap-1.5">
          {CHIPS.map((chip) => (
            <Button
              key={chip}
              variant="outline"
              size="sm"
              className="h-7 rounded-full px-3 text-xs"
              disabled={disabled}
              onClick={() => setAsk(chip.toLowerCase())}
            >
              {chip}
            </Button>
          ))}
        </div>
      </div>
    </div>
  )
}

export function UnroutedDetail({
  project,
  message,
  onDone,
}: {
  project: string
  message: UnroutedMessage
  onDone: (mark: string) => void
}) {
  const projects = useProjects()
  const route = useRouteMessage()
  const [target, setTarget] = useState(project)

  const go = async () => {
    try {
      await route.mutateAsync({ id: message.id, project: target })
      onDone(target === "none" ? "Not for STAR" : "Routed")
      toast.success(
        target === "none"
          ? "Dropped. STAR will not see it."
          : "Routed. That STAR drafts a reply on its next tick."
      )
    } catch (error) {
      toast.error(`Couldn't route it: ${errorMessage(error)}`)
    }
  }

  return (
    <div className="mx-auto flex max-w-3xl flex-col gap-5 p-4 sm:p-6 lg:p-8">
      <div className="flex items-center gap-3">
        <Person name={message.from} className="size-10" />
        <div className="min-w-0">
          <h2 className="text-lg font-semibold break-words">
            {message.from}{" "}
            <span className="font-normal text-muted-foreground">
              in {message.channel}
            </span>
          </h2>
          <p className="text-xs text-muted-foreground">
            The watcher could not tell which project this is for
          </p>
        </div>
      </div>
      <p className="rounded-xl border bg-muted px-4 py-3 text-sm leading-6 break-words">
        {message.text}
      </p>
      <Card className="gap-3 p-4">
        <Label htmlFor={`route-${message.id}`}>Send it to a project</Label>
        <div className="flex gap-2">
          <Select value={target} onValueChange={setTarget}>
            <SelectTrigger
              id={`route-${message.id}`}
              aria-label="Project"
              className="h-9 flex-1"
            >
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {projects.data?.map((p) => (
                <SelectItem key={p.name} value={p.name}>
                  {p.name}
                </SelectItem>
              ))}
              <SelectItem value="none">Not for STAR</SelectItem>
            </SelectContent>
          </Select>
          <Button onClick={() => void go()} disabled={route.isPending}>
            Route it
          </Button>
        </div>
        <p className="text-xs text-muted-foreground">
          Messages from {message.channel} go to this project from now on.
        </p>
      </Card>
    </div>
  )
}
