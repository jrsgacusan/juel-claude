import { CircleCheck } from "lucide-react"
import { type KeyboardEvent, useEffect, useRef, useState } from "react"
import { toast } from "sonner"
import { isConflictMarkers } from "@/api/client"
import { useAnswer, useItems, useSlack } from "@/api/queries"
import type { ProjectLoop } from "@/api/types"
import { AnswerDock, isTyping, useNarrow } from "@/components/list-detail"
import {
  type AskedRewrite,
  SlackReplyEditor,
} from "@/components/slack-reply-editor"
import { SlackText } from "@/components/slack-text"
import { StageRail } from "@/components/stage-rail"
import { StarMark } from "@/components/status"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import { Label } from "@/components/ui/label"
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group"
import { Skeleton } from "@/components/ui/skeleton"
import { Textarea } from "@/components/ui/textarea"
import { errorMessage } from "@/lib/errors"
import { agoText } from "@/lib/format"
import {
  alsoItems,
  kindOf,
  subkindLabel,
  subkindOf,
  visibleBody,
} from "@/lib/loops"
import { railOf } from "@/lib/stage"
import { stepText } from "@/lib/status"

/** The items this answer unblocks: each with its title, a small rail and its step. The refs alone when the items cannot be read. */
function Unblocks({ project, refs }: { project: string; refs: string[] }) {
  const items = useItems(project)
  return (
    <section aria-label="Unblocks" className="flex flex-col gap-2">
      <h3 className="text-sm font-medium">Unblocks</h3>
      <ul className="flex flex-col gap-2">
        {refs.map((ref) => {
          const row = items.data?.find((r) => r.ref === ref || r.item === ref)
          const rail = row ? railOf(row) : null
          return (
            <li
              key={ref}
              className="flex flex-col gap-1.5 rounded-lg border px-3 py-2"
            >
              <span className="flex min-w-0 items-baseline gap-2 text-sm">
                <span className="shrink-0 font-mono text-xs">{ref}</span>
                {row?.title && (
                  <span className="min-w-0 break-words">{row.title}</span>
                )}
              </span>
              {row &&
                (rail ? (
                  <span className="flex flex-wrap items-center gap-x-3 gap-y-1">
                    <StageRail rail={rail} size="sm" className="w-40" />
                    {stepText(row.step) && (
                      <span className="min-w-0 text-xs break-words text-muted-foreground">
                        {stepText(row.step)}
                      </span>
                    )}
                  </span>
                ) : (
                  <span className="text-xs text-muted-foreground">
                    Report{stepText(row.step) ? `. ${stepText(row.step)}` : ""}
                  </span>
                ))}
            </li>
          )
        })}
      </ul>
    </section>
  )
}

export function LoopDetail({
  project,
  loop,
  sentText,
  sentNudged,
  serverAnswer,
  onSent,
}: {
  project: string
  loop: ProjectLoop
  sentText: string | null
  sentNudged?: boolean
  serverAnswer: string | null
  onSent: (text: string, nudged: boolean) => void
}) {
  const answer = useAnswer(project)
  const slack = useSlack()
  const narrow = useNarrow()
  const [rewrite, setRewrite] = useState<AskedRewrite | null>(null)
  const [reply, setReply] = useState("")
  const sending = useRef(false)
  const lastSent = useRef<string | null>(null)
  const { label, icon: Icon } = kindOf(loop.kind)
  const body = visibleBody(loop)
  const subkind = subkindOf(loop.body)
  const unblocks =
    loop.kind === "slack-reply"
      ? []
      : [...new Set([loop.item, ...alsoItems(loop.body)])].filter(Boolean)
  const chosen = loop.options.find((o) => o.answer === reply)?.answer ?? ""
  const message =
    loop.kind === "slack-reply"
      ? slack.data?.routed.find((m) => m.loopId === loop.id)
      : undefined

  const send = async () => {
    const text = reply.trim()
    if (
      !text ||
      sending.current ||
      lastSent.current === text ||
      (sentText !== null && sentText === text)
    ) {
      toast("Pick an answer or write one first.")
      return
    }
    sending.current = true
    let res: { nudged: boolean }
    try {
      res = await answer.mutateAsync({ id: loop.id, text })
    } catch (error) {
      // Conflict markers raise the conflict banner (useAnswer); anything else is said here.
      if (isConflictMarkers(error)) return
      toast.error(`Couldn't send the answer: ${errorMessage(error)}`)
      return
    } finally {
      sending.current = false
    }
    onSent(text, res.nudged)
    lastSent.current = text
    toast.success(
      res.nudged === false
        ? `Sent to STAR: "${text}". STAR reads it on its next tick.`
        : `Sent to STAR: "${text}". It acts on it now.`
    )
  }

  // ⌘Enter / Ctrl+Enter sends from anywhere in the answer pane (a picked radio has the focus).
  const onKeyDown = (event: KeyboardEvent) => {
    if ((event.metaKey || event.ctrlKey) && event.key === "Enter") {
      event.preventDefault()
      void send()
    }
  }

  // On a desktop a number key picks that option, unless the user is typing.
  useEffect(() => {
    if (narrow || loop.kind === "slack-reply") return
    const onKey = (event: globalThis.KeyboardEvent) => {
      if (event.metaKey || event.ctrlKey || event.altKey) return
      if (isTyping(event.target)) return
      const option = loop.options[Number(event.key) - 1]
      if (option && /^[1-9]$/.test(event.key)) setReply(option.answer)
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [narrow, loop.kind, loop.options])

  if (loop.kind === "error")
    return (
      <div className="mx-auto flex max-w-3xl flex-col gap-4 p-4 sm:p-6 lg:p-8">
        <div className="flex flex-wrap items-center gap-2">
          <Badge variant="outline">
            <Icon className="size-3" />
            {label}
          </Badge>
          <Badge variant="secondary">{loop.project}</Badge>
        </div>
        <h2 className="text-xl font-semibold tracking-tight break-words sm:text-2xl">
          {loop.title}
        </h2>
        {body.map((line) => (
          <p key={line} className="text-sm leading-6 break-words">
            {line}
          </p>
        ))}
        <p className="text-xs text-muted-foreground">
          The other projects still list. Fix the file, and this clears.
        </p>
      </div>
    )

  return (
    <div
      onKeyDown={onKeyDown}
      className="mx-auto flex max-w-[680px] flex-col gap-6 p-4 sm:p-6 lg:p-8"
    >
      <div className="flex flex-col gap-3">
        <div className="flex flex-wrap items-center gap-2">
          <Badge variant="outline">
            <Icon className="size-3" />
            {label}
          </Badge>
          {subkind && (
            <Badge variant="secondary">{subkindLabel(subkind)}</Badge>
          )}
          <Badge variant="secondary">{loop.project}</Badge>
          <span className="min-w-0 font-mono text-xs break-all text-muted-foreground">
            {loop.item}
          </span>
          {loop.askedAt !== null && (
            <span className="text-xs text-muted-foreground">
              Asked {agoText(loop.askedAt)}
            </span>
          )}
        </div>
        <h2 className="text-xl font-semibold tracking-tight break-words sm:text-2xl">
          {loop.title}
        </h2>
      </div>

      {loop.kind === "slack-reply" ? (
        <div className="rounded-xl border bg-muted px-4 py-3 text-sm leading-6">
          {message && (
            <span className="mb-1 block text-xs font-medium text-muted-foreground">
              {message.from} in {message.channel}
            </span>
          )}
          <SlackText text={message?.text ?? loop.title} />
        </div>
      ) : (
        body.map((line) => (
          <p key={line} className="text-sm leading-6 break-words">
            {line}
          </p>
        ))
      )}

      {loop.suggestion && (
        <Card className="flex-row gap-3 p-4">
          <span className="grid size-8 shrink-0 place-items-center rounded-lg bg-primary text-primary-foreground">
            <StarMark />
          </span>
          <div className="flex min-w-0 flex-col gap-1">
            <p className="text-sm font-medium">STAR recommends</p>
            <p className="text-sm leading-6 break-words text-muted-foreground">
              {loop.suggestion}
            </p>
          </div>
        </Card>
      )}

      {unblocks.length > 0 && <Unblocks project={project} refs={unblocks} />}

      {loop.kind === "slack-reply" && slack.isPending && (
        <Skeleton className="h-40 w-full" />
      )}

      {loop.kind === "slack-reply" && message ? (
        <SlackReplyEditor
          project={project}
          message={message}
          onDone={(mark) => onSent(mark === "Sent" ? "send" : "skip", true)}
          rewrite={rewrite}
          onRewrite={setRewrite}
          dock={narrow}
        />
      ) : loop.kind !== "slack-reply" || !slack.isPending ? (
        <>
          {loop.options.length > 0 && (
            <fieldset className="flex flex-col gap-2">
              <legend className="mb-2 text-sm font-medium">Your answer</legend>
              <RadioGroup
                value={chosen}
                onValueChange={setReply}
                className="gap-2"
              >
                {loop.options.map((option, i) => (
                  <Label
                    key={option.answer}
                    htmlFor={`${loop.id}-option-${i}`}
                    className="flex cursor-pointer items-center gap-3 rounded-lg border p-3 text-sm font-normal transition-colors hover:bg-muted has-[[data-state=checked]]:border-primary has-[[data-state=checked]]:bg-accent"
                  >
                    <RadioGroupItem
                      id={`${loop.id}-option-${i}`}
                      value={option.answer}
                    />
                    <span className="flex-1 font-medium">{option.label}</span>
                    {option.recommended && (
                      <Badge variant="secondary">
                        <StarMark className="size-3" />
                        Recommended
                      </Badge>
                    )}
                    {!narrow && (
                      <kbd className="rounded border bg-muted px-1.5 py-0.5 font-mono text-[11px] text-muted-foreground">
                        {i + 1}
                      </kbd>
                    )}
                  </Label>
                ))}
              </RadioGroup>
            </fieldset>
          )}

          <div className="flex flex-col gap-2">
            <Label htmlFor={`reply-${loop.id}`}>Or write your own</Label>
            <Textarea
              id={`reply-${loop.id}`}
              rows={3}
              value={reply}
              onChange={(event) => setReply(event.target.value)}
              placeholder={
                loop.options.length > 0
                  ? "Or answer in your own words"
                  : "Type your answer"
              }
              className="min-h-[84px] resize-y leading-6"
            />
          </div>

          <div className="flex flex-wrap items-center justify-between gap-3">
            <p className="text-xs text-muted-foreground">
              STAR acts on your answer as soon as you send it.
            </p>
            {!narrow && (
              <Button
                variant="answer"
                onClick={() => void send()}
                disabled={answer.isPending}
                className="pointer-coarse:h-11"
              >
                Send to STAR
                <span className="opacity-60 pointer-coarse:hidden">⌘↵</span>
              </Button>
            )}
          </div>
          {narrow && (
            <AnswerDock>
              <Button
                variant="answer"
                onClick={() => void send()}
                disabled={answer.isPending}
                className="h-11 flex-1"
              >
                Send to STAR
              </Button>
            </AnswerDock>
          )}
        </>
      ) : null}

      {loop.kind !== "slack-reply" && sentText && (
        <p
          role="status"
          className="flex items-center gap-2 rounded-lg border border-done-line bg-done-bg px-3 py-2 text-sm text-done-fg"
        >
          <CircleCheck className="size-4 shrink-0" />
          <span className="min-w-0 break-words">
            {sentNudged
              ? `Sent "${sentText}". STAR picked it up.`
              : `Sent "${sentText}". STAR reads it when it next runs.`}
          </span>
        </p>
      )}
      {loop.kind !== "slack-reply" && !sentText && serverAnswer && (
        <p
          role="status"
          className="flex items-center gap-2 rounded-lg border border-done-line bg-done-bg px-3 py-2 text-sm text-done-fg"
        >
          <CircleCheck className="size-4 shrink-0" />
          <span className="min-w-0 break-words">{`Sent "${serverAnswer}". Waiting for STAR to pick it up.`}</span>
        </p>
      )}
    </div>
  )
}
