import { CircleCheck, PenLine } from "lucide-react"
import { type KeyboardEvent, useState } from "react"
import { Link } from "react-router"
import { toast } from "sonner"
import { ApiError } from "@/api/client"
import { useAnswer, useItems, useSlack } from "@/api/queries"
import type { Loop } from "@/api/types"
import { StarMark, StateBadge } from "@/components/status"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import { Label } from "@/components/ui/label"
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group"
import { Textarea } from "@/components/ui/textarea"
import { errorMessage } from "@/lib/errors"
import { agoText } from "@/lib/format"
import { kindOf, visibleBody } from "@/lib/loops"
import { projectPath } from "@/lib/routes"

export function LoopDetail({
  project,
  loop,
  sentText,
  onSent,
}: {
  project: string
  loop: Loop
  sentText: string | null
  onSent: (text: string) => void
}) {
  const answer = useAnswer(project)
  const items = useItems(project)
  const slack = useSlack()
  const [reply, setReply] = useState("")
  const { label, icon: Icon } = kindOf(loop.kind)
  const body = visibleBody(loop)
  const chosen = loop.options.find((o) => o.answer === reply)?.answer ?? ""
  const message =
    loop.kind === "slack-reply"
      ? slack.data?.routed.find((m) => m.loopId === loop.id)
      : undefined

  const send = async () => {
    const text = reply.trim()
    if (!text) {
      toast("Pick an answer or write one first.")
      return
    }
    try {
      const res = await answer.mutateAsync({ id: loop.id, text })
      onSent(text)
      toast.success(
        res?.nudged === false
          ? `Sent to STAR: "${text}". STAR reads it on its next tick.`
          : `Sent to STAR: "${text}". It acts on it now.`
      )
    } catch (error) {
      // A 409 raises the conflict banner (useAnswer); anything else is said here.
      if (error instanceof ApiError && error.status === 409) return
      toast.error(`Couldn't send the answer: ${errorMessage(error)}`)
    }
  }

  // ⌘Enter / Ctrl+Enter sends from anywhere in the answer pane (a picked radio has the focus).
  const onKeyDown = (event: KeyboardEvent) => {
    if ((event.metaKey || event.ctrlKey) && event.key === "Enter") {
      event.preventDefault()
      void send()
    }
  }

  return (
    <div
      onKeyDown={onKeyDown}
      className="mx-auto flex max-w-3xl flex-col gap-6 p-4 sm:p-6 lg:p-8"
    >
      <div className="flex flex-col gap-3">
        <div className="flex flex-wrap items-center gap-2">
          <Badge variant="outline">
            <Icon className="size-3" />
            {label}
          </Badge>
          <span className="font-mono text-xs text-muted-foreground">
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

      {loop.kind === "go-batch" && body.length > 0 ? (
        <ul className="divide-y overflow-hidden rounded-xl border">
          {body.map((line) => {
            const row = items.data?.find(
              (r) => r.item === line.trim() || r.ref === line.trim()
            )
            return (
              <li
                key={line}
                className="flex flex-wrap items-center gap-x-4 gap-y-1 px-4 py-3"
              >
                <span className="w-16 font-mono text-xs text-muted-foreground">
                  {row?.ref ?? line}
                </span>
                <span className="min-w-0 flex-1 text-sm font-medium break-words">
                  {row?.title ?? (row ? "" : line)}
                </span>
                {row && <StateBadge status={row.status} />}
              </li>
            )
          })}
        </ul>
      ) : loop.kind === "slack-reply" ? (
        <div className="rounded-xl border bg-muted px-4 py-3 text-sm leading-6">
          {message && (
            <span className="mb-1 block text-xs font-medium text-muted-foreground">
              {message.from} in {message.channel}
            </span>
          )}
          <p className="break-words">{message?.text ?? loop.title}</p>
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

      {loop.options.length > 0 && (
        <fieldset className="flex flex-col gap-2">
          <legend className="mb-2 text-sm font-medium">Your answer</legend>
          <RadioGroup value={chosen} onValueChange={setReply} className="gap-2">
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
          Goes into STAR's queue, the same one as open-loops.md.
        </p>
        <div className="flex items-center gap-2">
          {loop.kind === "slack-reply" && (
            <Button variant="outline" asChild>
              <Link to={projectPath(project, "slack", { loop: loop.id })}>
                <PenLine />
                Edit the draft
              </Link>
            </Button>
          )}
          <Button onClick={() => void send()} disabled={answer.isPending}>
            Send to STAR
            <span className="opacity-60">⌘↵</span>
          </Button>
        </div>
      </div>

      {sentText && (
        <p
          role="status"
          className="flex items-center gap-2 rounded-lg border border-done-line bg-done-bg px-3 py-2 text-sm text-done-fg"
        >
          <CircleCheck className="size-4 shrink-0" />
          <span className="min-w-0 break-words">{`Sent "${sentText}". STAR picked it up.`}</span>
        </p>
      )}
    </div>
  )
}
