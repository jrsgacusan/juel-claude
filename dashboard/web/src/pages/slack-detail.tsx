import { useState } from "react"
import { toast } from "sonner"
import { useProjects, useRouteMessage } from "@/api/queries"
import type { RoutedMessage, UnroutedMessage } from "@/api/types"
import { useNarrow } from "@/components/list-detail"
import {
  type AskedRewrite,
  SlackReplyEditor,
} from "@/components/slack-reply-editor"
import { SlackText } from "@/components/slack-text"
import { Avatar, AvatarFallback } from "@/components/ui/avatar"
import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import { Label } from "@/components/ui/label"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"
import { errorMessage } from "@/lib/errors"
import { clock, slackTime } from "@/lib/format"

export type { AskedRewrite }

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
  rewrite,
  onRewrite,
}: {
  project: string
  message: RoutedMessage
  onDone: (mark: string) => void
  rewrite: AskedRewrite | null
  onRewrite: (asked: AskedRewrite) => void
}) {
  const when = slackTime(message.id)
  const narrow = useNarrow()

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
              <SlackText text={text} className="text-sm leading-6" />
            </div>
          </li>
        ))}
      </ol>
      <SlackReplyEditor
        project={project}
        message={message}
        onDone={onDone}
        rewrite={rewrite}
        onRewrite={onRewrite}
        dock={narrow}
      />
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
          : `Routed to ${target}.`
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
      <SlackText
        text={message.text}
        className="rounded-xl border bg-muted px-4 py-3 text-sm leading-6"
      />
      <Card className="gap-3 p-4">
        <Label htmlFor={`route-${message.id}`}>Send it to a project</Label>
        <div className="flex gap-2">
          <Select value={target} onValueChange={setTarget}>
            <SelectTrigger
              id={`route-${message.id}`}
              aria-label="Project"
              className="h-9 flex-1 pointer-coarse:h-11"
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
          <Button
            onClick={() => void go()}
            disabled={route.isPending}
            className="pointer-coarse:h-11"
          >
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
