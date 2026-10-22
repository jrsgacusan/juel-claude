import { RefreshCw, Send } from "lucide-react"
import { useEffect, useRef, useState } from "react"
import { toast } from "sonner"
import { ApiError } from "@/api/client"
import { useRedraft } from "@/api/slack"
import { useAnswer, useDraftText, useLoops, useSaveDraft } from "@/api/queries"
import type { RoutedMessage } from "@/api/types"
import { AnswerDock } from "@/components/list-detail"
import { StarMark } from "@/components/status"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Skeleton } from "@/components/ui/skeleton"
import { Textarea } from "@/components/ui/textarea"
import { errorMessage } from "@/lib/errors"
import { cn } from "@/lib/utils"

const CHIPS = ["Shorter", "Add the PR link", "Less formal"]
/** A draft file is "to: slack <channelId> <threadTs or ts>" and then the reply. */
export const replyOf = (file: string) => file.split("\n").slice(1).join("\n")

/** A rewrite the owner asked the drafter for: the item it was asked on and the Suggest line it had. */
export type AskedRewrite = {
  how: string
  loopId: string
  suggestion: string | null
}

/** The Slack reply editor: the draft that saves on blur, Skip and Send reply, and the rewrite request. Used by the Slack replies page and by a slack-reply in Needs you. With dock, Skip and Send reply sit in the phone's bottom dock. */
export function SlackReplyEditor({
  project,
  message,
  onDone,
  rewrite,
  onRewrite,
  dock = false,
  onBeforeAnswer,
}: {
  project: string
  message: RoutedMessage
  onDone: (mark: string) => void
  rewrite: AskedRewrite | null
  onRewrite: (asked: AskedRewrite) => void
  dock?: boolean
  // Runs just before the editor answers the loop (Needs you cancels a held one-tap answer here).
  onBeforeAnswer?: () => void
}) {
  const draft = useDraftText(project, message.draftPath)
  const loops = useLoops(project)
  const redraft = useRedraft(project)
  const loop = loops.data?.find((l) => l.id === message.loopId)
  const save = useSaveDraft(project)
  const answer = useAnswer(project)
  const [edited, setEdited] = useState<string | null>(null)
  const [ask, setAsk] = useState("")
  const pendingSave = useRef<Promise<boolean> | null>(null)
  const saved = draft.data !== undefined ? replyOf(draft.data) : ""
  const value = edited ?? saved
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
    onBeforeAnswer?.()
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
    if (!ready || !message.loopId || noReply) return
    if (await persist())
      await answerLoop(
        "send",
        `Sent. STAR posts it to ${message.channel} as you.`,
        "Sent"
      )
  }
  // A new loop id or a changed Suggest line ends the wait: STAR has added the item again.
  const rewriting =
    rewrite !== null &&
    (message.loopId === null ||
      (message.loopId === rewrite.loopId &&
        (loop === undefined || loop.suggestion === rewrite.suggestion)))
  const failed =
    rewrite !== null && !rewriting
      ? (/\(redraft failed: (.+)\)$/.exec(loop?.title ?? "")?.[1] ?? null)
      : null
  // I-11: a draft that holds only its first line is not a reply to edit or send.
  const noReply = ready && saved.trim() === ""
  const whyNoDraft = /^no draft: (.+)$/.exec(loop?.suggestion ?? "")?.[1]
  const askRewrite = async (how: string) => {
    if (!ready || !message.loopId) return
    const text = how.trim()
    if (!text) {
      toast("Say what to change first.")
      return
    }
    if (!(await persist())) return
    const loopId = message.loopId
    // The Suggest line as it is now, so a loops query still loading never records null for a line with text.
    const items = loops.data ?? (await loops.refetch()).data
    const suggestion = items?.find((l) => l.id === loopId)?.suggestion ?? null
    try {
      await redraft.mutateAsync({ loop: loopId, how: text })
      onRewrite({ how: text, loopId, suggestion })
      setEdited(null)
      setAsk("")
    } catch (error) {
      toast.error(`Couldn't ask for a rewrite: ${errorMessage(error)}`)
    }
  }
  const disabled =
    !ready ||
    !message.loopId ||
    answer.isPending ||
    redraft.isPending ||
    rewriting
  const saveStatus = () => {
    if (save.isPending) return "Saving…"
    if (save.isError) return "Not saved"
    if (edited !== null) return ""
    if (save.isSuccess) return "Saved"
    return ""
  }

  const actions = (
    <>
      <Button
        variant={dock ? "outline" : "ghost"}
        size={dock ? "default" : "sm"}
        className={dock ? "h-11 flex-1" : "pointer-coarse:h-11"}
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
      {!noReply && (
        <Button
          variant="answer"
          size={dock ? "default" : "sm"}
          className={dock ? "h-11 flex-[2]" : "pointer-coarse:h-11"}
          disabled={disabled}
          onClick={() => void sendReply()}
        >
          <Send className="size-3.5" />
          Send reply
        </Button>
      )}
    </>
  )

  return (
    <>
      {message.draftPath ? (
        <Card className="gap-0 overflow-hidden p-0 focus-within:ring-2 focus-within:ring-ring">
          <div className="flex items-center justify-between gap-2 border-b px-4 py-2 text-xs text-muted-foreground">
            <span>Reply in {message.channel} as you</span>
            {!noReply && (
              <Badge variant="secondary">
                <StarMark className="size-3" />
                Drafted for you
              </Badge>
            )}
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
          ) : noReply ? (
            <p
              role="status"
              className="px-4 py-3 text-sm text-muted-foreground"
            >
              {whyNoDraft
                ? `No draft yet: ${whyNoDraft}`
                : "No draft yet. When the drafter can't write one, Needs you says why."}
            </p>
          ) : (
            <Textarea
              aria-label="Your reply"
              readOnly={rewriting}
              rows={3}
              value={value}
              onChange={(e) => setEdited(e.target.value)}
              onBlur={() => void persist()}
              className="block min-h-[96px] w-full resize-y rounded-none border-0 px-4 py-3 text-base leading-7 shadow-none focus-visible:ring-0 md:text-sm"
            />
          )}
          <div className="flex flex-wrap items-center justify-between gap-2 border-t px-3 py-2">
            <p
              className={cn(
                "text-xs text-muted-foreground",
                failed && !rewriting && "text-stop-fg"
              )}
              aria-live="polite"
            >
              {rewriting
                ? "Rewriting…"
                : failed
                  ? `Couldn't rewrite it: ${failed}`
                  : saveStatus()}
            </p>
            {!dock && <div className="flex gap-2">{actions}</div>}
          </div>
        </Card>
      ) : (
        <p className="rounded-xl border border-dashed p-4 text-sm text-muted-foreground">
          No draft yet. When the drafter can't write one, Needs you says why.
        </p>
      )}
      <div className="flex flex-col gap-2">
        <Label htmlFor={`ask-${message.id}`}>
          Ask the drafter to rewrite it
        </Label>
        <div className="flex gap-2">
          <Input
            id={`ask-${message.id}`}
            value={ask}
            onChange={(e) => setAsk(e.target.value)}
            placeholder="Shorter, add the PR link, less formal"
            className="h-9 pointer-coarse:h-11"
          />
          <Button
            variant="outline"
            className="pointer-coarse:h-11"
            disabled={disabled}
            onClick={() => void askRewrite(ask)}
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
              className="h-7 rounded-full px-3 text-xs pointer-coarse:h-11"
              disabled={disabled}
              onClick={() => setAsk(chip.toLowerCase())}
            >
              {chip}
            </Button>
          ))}
        </div>
      </div>
      {dock && message.draftPath && <AnswerDock>{actions}</AnswerDock>}
    </>
  )
}
