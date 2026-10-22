import { Check, CircleAlert, MessageSquare, Unplug } from "lucide-react"
import { useState } from "react"
import { useParams } from "react-router"
import { useSlack } from "@/api/queries"
import type { RoutedMessage, UnroutedMessage } from "@/api/types"
import { Banner } from "@/components/banners"
import { SlackCheckSwitch } from "@/components/slack-check-switch"
import {
  ListDetail,
  useListSelection,
  useNarrow,
} from "@/components/list-detail"
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
import { useSearchParam } from "@/lib/use-search-param"
import { type AskedRewrite, RoutedDetail, UnroutedDetail } from "./slack-detail"

const isRouted = (
  message: RoutedMessage | UnroutedMessage
): message is RoutedMessage => "thread" in message

function Entry({
  message,
  mark,
  selected,
  onClick,
}: {
  message: RoutedMessage | UnroutedMessage
  mark?: string
  selected: boolean
  onClick: () => void
}) {
  const routed = isRouted(message)
  return (
    <button
      type="button"
      onClick={onClick}
      aria-current={selected ? "true" : undefined}
      className={`flex w-full min-w-0 flex-col gap-1.5 rounded-lg border px-3 py-2.5 text-left ${selected ? "border-border bg-card shadow-sm" : "border-transparent hover:bg-muted"}`}
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
          <Badge variant="outline">Waiting for the draft</Badge>
        )}
      </span>
    </button>
  )
}

export function SlackPage() {
  const { project = "" } = useParams()
  const slack = useSlack()
  const {
    value: messageParam,
    select,
    back,
  } = useListSelection("message", ["loop", "draft"])
  const [loopParam] = useSearchParam("loop")
  // Search results name a draft file (the server's /<p>/slack?draft=<name>).
  const [draftParam] = useSearchParam("draft")
  const [, setMessage] = useSearchParam("message")
  const narrow = useNarrow()
  const [done, setDone] = useState<Record<string, string>>({})
  // Rewrites asked from this page, by message id. They live here so they survive the gap where
  // the server drops the finished message until STAR adds it again.
  const [rewrites, setRewrites] = useState<Record<string, AskedRewrite>>({})
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
  const routed = slack.data!.routed.filter((m) => m.project === project)
  const unrouted = slack.data!.unrouted
  const all = [...routed, ...unrouted]
  const named =
    all.find((m) => m.id === messageParam) ??
    (draftParam
      ? routed.find((m) => m.draftPath?.split("/").pop() === draftParam)
      : undefined) ??
    (loopParam ? routed.find((m) => m.loopId === loopParam) : undefined)
  const selected = named ?? routed[0] ?? unrouted[0]
  // A phone marks a row current only when the URL names it; a desktop shows the first one.
  const current = narrow ? named : selected
  const markDone = (id: string, mark: string) =>
    setDone((current) => ({ ...current, [id]: mark }))
  const model = slack.data!.status.model
    ? slack.data!.status.model[0]?.toUpperCase() +
      slack.data!.status.model.slice(1)
    : null
  const noneWaiting = (
    <EmptyState
      title="No Slack replies waiting."
      body="When someone asks you something on Slack, the watcher brings it here with a drafted reply."
    />
  )
  return (
    <>
      {refreshFailed(slack) && (
        <RefreshNotice
          what="the Slack replies"
          error={slack.error}
          onRetry={() => void slack.refetch()}
        />
      )}
      {!slack.data!.status.connected && (
        <Banner tone="stop" icon={<Unplug />}>
          <span className="font-medium">Slack isn&apos;t connected</span>
          <p className="mt-1 text-xs opacity-80">
            Connect the Slack connector in Claude Code for this profile. The
            watcher checks again on its next run.
          </p>
        </Banner>
      )}
      <ListDetail
        showDetail={named !== undefined}
        onBack={all.length === 0 ? undefined : back}
        backLabel="Slack replies"
        listLabel="Messages"
        detailLabel="Reply"
        columns="md:grid-cols-[minmax(300px,380px)_minmax(0,1fr)]"
        list={
          <>
            <div className="flex flex-col gap-2 p-4 pb-3">
              <div className="flex items-center gap-2">
                <MessageSquare className="size-4" />
                <h1 className="text-base font-semibold">Slack replies</h1>
              </div>
              {slack.data!.paused ? (
                <p className="flex items-center gap-1.5 text-xs text-wait-fg">
                  <Dot tone="wait" />
                  Paused. Slack is not checked until you turn it back on.
                </p>
              ) : slack.data!.status.connected ? (
                <p className="flex items-center gap-1.5 text-xs text-muted-foreground">
                  <Dot tone="done" pulse />
                  {model
                    ? `Watching ${slack.data!.status.workspace ?? "Slack"} with ${model}.`
                    : `Watching ${slack.data!.status.workspace ?? "Slack"}.`}{" "}
                  {slack.data!.status.lastCheck &&
                    `Checked ${agoText(slack.data!.status.lastCheck)}.`}
                </p>
              ) : (
                <p className="flex items-center gap-1.5 text-xs text-stop-fg">
                  <CircleAlert className="size-3.5" />
                  The watcher is not connected.
                </p>
              )}
              {slack.data!.status.error && (
                <p className="text-xs text-stop-fg">
                  The last check failed: {slack.data!.status.error}
                </p>
              )}
              <SlackCheckSwitch paused={slack.data!.paused} />
            </div>
            {all.length === 0 && narrow ? (
              noneWaiting
            ) : (
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
                      selected={current?.id === m.id}
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
                      selected={current?.id === m.id}
                      onClick={() => select(m.id)}
                    />
                  ))}
                </div>
              </ScrollArea>
            )}
          </>
        }
        detail={
          selected ? (
            isRouted(selected) ? (
              <RoutedDetail
                key={selected.id}
                project={project}
                message={selected}
                onDone={(mark) => markDone(selected.id, mark)}
                rewrite={rewrites[selected.id] ?? null}
                onRewrite={(asked) => {
                  setRewrites((r) => ({ ...r, [selected.id]: asked }))
                  // Pin the message, so a page opened by ?loop= or ?draft= stays on it when STAR renames the item.
                  if (messageParam !== selected.id)
                    setMessage(selected.id, { clear: ["loop", "draft"] })
                }}
              />
            ) : (
              <UnroutedDetail
                key={selected.id}
                project={project}
                message={selected}
                onDone={(mark) => markDone(selected.id, mark)}
              />
            )
          ) : (
            noneWaiting
          )
        }
      />
    </>
  )
}
