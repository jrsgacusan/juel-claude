import { Check, CircleAlert, MessageSquare, Unplug } from "lucide-react"
import { useState } from "react"
import { useParams, useSearchParams } from "react-router"
import { useSlack } from "@/api/queries"
import type { RoutedMessage, UnroutedMessage } from "@/api/types"
import { Banner } from "@/components/banners"
import {
  EmptyState,
  ErrorState,
  LoadingState,
  queryFailed,
  RefreshNotice,
  refreshFailed,
} from "@/components/page-state"
import { Dot, StarMark } from "@/components/status"
import { Avatar, AvatarFallback } from "@/components/ui/avatar"
import { Badge } from "@/components/ui/badge"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Skeleton } from "@/components/ui/skeleton"
import { age, agoText, slackTime } from "@/lib/format"
import { RoutedDetail, UnroutedDetail } from "./slack-detail"

function Entry({
  message,
  mark,
  onClick,
}: {
  message: RoutedMessage | UnroutedMessage
  mark?: string
  onClick: () => void
}) {
  const routed = "project" in message
  return (
    <button
      type="button"
      onClick={onClick}
      className="flex w-full min-w-0 flex-col gap-1.5 rounded-lg border border-transparent px-3 py-2.5 text-left hover:bg-muted"
    >
      <span className="flex min-w-0 items-center gap-2">
        <Avatar className="size-6">
          <AvatarFallback className="text-[10px] font-semibold">
            {message.from.slice(0, 1).toUpperCase()}
          </AvatarFallback>
        </Avatar>
        <span className="min-w-0 flex-1 truncate text-sm font-medium">
          {message.from}
        </span>
        <span className="shrink-0 text-xs text-muted-foreground tabular-nums">
          {age(slackTime(message.id))}
        </span>
      </span>
      <span className="flex min-w-0 items-center gap-2 pl-8 text-xs text-muted-foreground">
        <span className="truncate">{message.channel}</span>
      </span>
      <span className="line-clamp-2 pl-8 text-sm leading-5 break-words">
        {message.text}
      </span>
      <span className="flex pl-8">
        {mark ? (
          <Badge variant="done">
            <Check className="size-3" />
            {mark}
          </Badge>
        ) : !routed ? (
          <Badge variant="outline">Pick a project</Badge>
        ) : message.draftPath ? (
          <Badge variant="secondary">
            <StarMark className="size-3" />
            Draft ready
          </Badge>
        ) : (
          <Badge variant="outline">Waiting for STAR&apos;s draft</Badge>
        )}
      </span>
    </button>
  )
}

const isRouted = (
  message: RoutedMessage | UnroutedMessage
): message is RoutedMessage => "thread" in message

export function SlackPage() {
  const { project = "" } = useParams()
  const slack = useSlack()
  const [params, setParams] = useSearchParams()
  const [done, setDone] = useState<Record<string, string>>({})
  if (slack.isPending)
    return (
      <LoadingState label="the Slack replies">
        <div className="grid gap-4 md:grid-cols-[minmax(300px,380px)_minmax(0,1fr)]">
          <Skeleton className="h-96" />
          <Skeleton className="h-96" />
        </div>
      </LoadingState>
    )
  if (queryFailed(slack))
    return (
      <ErrorState
        what="the Slack replies"
        error={slack.error}
        onRetry={() => void slack.refetch()}
      />
    )
  const routed = slack.data.routed.filter((m) => m.project === project)
  const unrouted = slack.data.unrouted
  const all = [...routed, ...unrouted]
  const selectedId = params.get("message")
  const loopId = params.get("loop")
  const selected =
    all.find((m) => m.id === selectedId) ??
    routed.find((m) => m.loopId === loopId) ??
    routed[0] ??
    unrouted[0]
  const select = (id: string) =>
    setParams(
      (prev) => {
        const next = new URLSearchParams(prev)
        next.set("message", id)
        return next
      },
      { replace: true }
    )
  const model = slack.data.status.model
    ? slack.data.status.model[0]?.toUpperCase() +
      slack.data.status.model.slice(1)
    : null
  return (
    <>
      {refreshFailed(slack) && (
        <RefreshNotice
          what="the Slack replies"
          error={slack.error}
          onRetry={() => void slack.refetch()}
        />
      )}
      <div className="grid min-h-0 flex-1 md:h-full md:grid-cols-[minmax(300px,380px)_minmax(0,1fr)]">
        <section
          aria-label="Messages"
          className="flex min-h-0 min-w-0 flex-col border-b md:border-r md:border-b-0"
        >
          <div className="flex flex-col gap-2 p-4 pb-3">
            <div className="flex items-center gap-2">
              <MessageSquare className="size-4" />
              <h1 className="text-base font-semibold">Slack replies</h1>
            </div>
            {slack.data.status.connected ? (
              <p className="flex items-center gap-1.5 text-xs text-muted-foreground">
                <Dot tone="done" pulse />
                {model
                  ? `Watching ${slack.data.status.workspace ?? "Slack"} with ${model}.`
                  : `Watching ${slack.data.status.workspace ?? "Slack"}.`}{" "}
                {slack.data.status.lastCheck &&
                  `Checked ${agoText(slack.data.status.lastCheck)}.`}
              </p>
            ) : (
              <p className="flex items-center gap-1.5 text-xs text-stop-fg">
                <CircleAlert className="size-3.5" />
                The watcher is not connected.
              </p>
            )}
            {slack.data.status.error && (
              <p className="text-xs text-stop-fg">
                The last check failed: {slack.data.status.error}
              </p>
            )}
          </div>
          <ScrollArea className="min-h-0 flex-1">
            <div className="flex flex-col gap-3 px-2 pb-3">
              <p className="px-2 text-xs font-medium text-muted-foreground">
                For {project}
              </p>
              {routed.map((m) => (
                <Entry
                  key={m.id}
                  message={m}
                  mark={done[m.id]}
                  onClick={() => select(m.id)}
                />
              ))}
              <p className="px-2 pt-2 text-xs font-medium text-muted-foreground">
                Unrouted
              </p>
              {unrouted.map((m) => (
                <Entry
                  key={m.id}
                  message={m}
                  mark={done[m.id]}
                  onClick={() => select(m.id)}
                />
              ))}
            </div>
          </ScrollArea>
        </section>
        <section
          aria-label="Reply"
          className="min-h-0 min-w-0 md:overflow-y-auto"
        >
          {!slack.data.status.connected && (
            <Banner tone="stop" icon={<Unplug />}>
              <span className="font-medium">Slack isn&apos;t connected</span>
              <p className="mt-1 text-xs opacity-80">
                Connect the Slack connector in Claude Code for this profile. The
                watcher checks again on its next run.
              </p>
            </Banner>
          )}
          {selected ? (
            isRouted(selected) ? (
              <RoutedDetail
                key={selected.id}
                project={project}
                message={selected}
                onDone={(mark) =>
                  setDone((current) => ({ ...current, [selected.id]: mark }))
                }
              />
            ) : (
              <UnroutedDetail
                key={selected.id}
                project={project}
                message={selected}
                onDone={(mark) =>
                  setDone((current) => ({ ...current, [selected.id]: mark }))
                }
              />
            )
          ) : (
            <EmptyState
              title="No Slack replies waiting."
              body="When someone asks you something on Slack, the watcher brings it here with a drafted reply."
            />
          )}
        </section>
      </div>
    </>
  )
}
