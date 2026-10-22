import { Check } from "lucide-react"
import { useEffect, useState } from "react"
import { useSearchParams } from "react-router"
import { type QueryClient, useQueryClient } from "@tanstack/react-query"
import { toast } from "sonner"
import { ApiError, isConflictMarkers, sendJson } from "@/api/client"
import { paths } from "@/api/paths"
import { keys, useAllLoops, useDraftText, useSlack } from "@/api/queries"
import type { AnswerResponse, LoopOption, ProjectLoop } from "@/api/types"
import {
  EmptyState,
  ErrorState,
  LoadingState,
  queryFailed,
  RefreshNotice,
  refreshFailed,
} from "@/components/page-state"
import {
  isTyping,
  ListDetail,
  useListSelection,
  useNarrow,
} from "@/components/list-detail"
import { replyOf } from "@/components/slack-reply-editor"
import { Badge } from "@/components/ui/badge"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Button } from "@/components/ui/button"
import { Skeleton } from "@/components/ui/skeleton"
import { setConflict } from "@/lib/conflict"
import { errorMessage } from "@/lib/errors"
import { age } from "@/lib/format"
import {
  groupOf,
  isAnswered,
  kindOf,
  type LoopGroup,
  primaryOf,
  secondaryOf,
} from "@/lib/loops"
import {
  HOLD_MS,
  holdAnswer,
  undoAnswer,
  usePending,
} from "@/lib/pending-answers"
import { cn } from "@/lib/utils"
import { LoopDetail } from "./needs-detail"

type Chip = "all" | LoopGroup
const GROUPS: Array<{ id: LoopGroup; chip: string; heading: string }> = [
  { id: "hold", chip: "Holds up work", heading: "Holds up work" },
  { id: "slack", chip: "Slack", heading: "Slack replies" },
  { id: "other", chip: "Other", heading: "Other" },
]

const keyOf = (loop: ProjectLoop) => `${loop.project}/${loop.id}`
const plural = (n: number, one: string, many: string) =>
  `${n} ${n === 1 ? one : many}`
const upperFirst = (text: string) => text.replace(/^./, (c) => c.toUpperCase())

/** Posts an answer outside any component, so a held tap still lands after its row is gone. Same effects as useAnswer. */
async function postAnswer(
  qc: QueryClient,
  loop: ProjectLoop,
  text: string
): Promise<void> {
  const { project, id } = loop
  try {
    // keepalive: a hold flushed on pagehide must still reach STAR after the page is gone.
    await sendJson<AnswerResponse>("POST", paths.answer(project, id), { text }, { keepalive: true })
  } catch (error) {
    if (isConflictMarkers(error)) setConflict(project)
    else {
      if (error instanceof ApiError && error.status === 409) {
        void qc.invalidateQueries({ queryKey: keys.loops(project) })
        void qc.invalidateQueries({ queryKey: keys.allLoops })
      }
      toast.error(`Couldn't send the answer: ${errorMessage(error)}`)
    }
    return
  }
  setConflict(null)
  // The row reads Sent to STAR at once, with no gap before the refetch.
  qc.setQueryData<ProjectLoop[]>(keys.allLoops, (old) =>
    old?.map((l) =>
      l.project === project && l.id === id ? { ...l, answer: text } : l
    )
  )
  void qc.invalidateQueries({ queryKey: keys.loops(project) })
  void qc.invalidateQueries({ queryKey: keys.allLoops })
  void qc.invalidateQueries({ queryKey: keys.projects })
}

const toastIds = new Map<string, string | number>()

/** A one-tap answer: held for HOLD_MS with an Undo toast, then posted once. */
function tapAnswer(
  qc: QueryClient,
  loop: ProjectLoop,
  option: LoopOption,
  label: string
) {
  const key = keyOf(loop)
  const id = toast(`"${label}" goes to STAR in 5 seconds.`, {
    duration: HOLD_MS,
    action: { label: "Undo", onClick: () => undoAnswer(key) },
  })
  toastIds.set(key, id)
  holdAnswer(key, async () => {
    toast.dismiss(toastIds.get(key))
    toastIds.delete(key)
    await postAnswer(qc, loop, option.answer)
  })
}

function undoTap(loop: ProjectLoop) {
  const key = keyOf(loop)
  if (undoAnswer(key)) toast.dismiss(toastIds.get(key))
  toastIds.delete(key)
}

const TAP = "h-11 min-w-0 flex-1 px-3 text-[15px] whitespace-normal"

function RowActions({
  loop,
  onOpen,
}: {
  loop: ProjectLoop
  onOpen: () => void
}) {
  const qc = useQueryClient()
  const primary = primaryOf(loop)
  const secondary = secondaryOf(loop)
  const isSlack = loop.kind === "slack-reply"
  const slack = useSlack()
  const message = isSlack
    ? slack.data?.routed.find(
        (m) => m.loopId === loop.id && m.project === loop.project
      )
    : undefined
  const draft = useDraftText(loop.project, message?.draftPath ?? null)
  const reply = draft.data !== undefined ? replyOf(draft.data).trim() : ""
  if (!primary && !isSlack) return null
  return (
    <div className="flex flex-col gap-2 px-3 pb-3">
      {isSlack && reply && (
        <div className="rounded-lg border bg-muted px-3 py-2 text-sm leading-5">
          <span className="mb-0.5 block text-xs font-medium text-muted-foreground">
            Your reply, drafted by STAR
          </span>
          <span className="line-clamp-3 break-words">{reply}</span>
        </div>
      )}
      <div className="flex gap-2">
        {isSlack ? (
          <>
            {primary && reply && (
              <Button
                variant="answer"
                className={TAP}
                onClick={() => tapAnswer(qc, loop, primary, "Send reply")}
              >
                Send reply
              </Button>
            )}
            <Button variant="outline" className={TAP} onClick={onOpen}>
              Edit
            </Button>
          </>
        ) : (
          <>
            {primary && (
              <Button
                variant="answer"
                className={TAP}
                onClick={() =>
                  tapAnswer(qc, loop, primary, upperFirst(primary.label))
                }
              >
                {upperFirst(primary.label)}
              </Button>
            )}
            {secondary === "open" ? (
              <Button variant="outline" className={TAP} onClick={onOpen}>
                Open
              </Button>
            ) : (
              secondary && (
                <Button
                  variant="outline"
                  className={TAP}
                  onClick={() =>
                    tapAnswer(qc, loop, secondary, upperFirst(secondary.label))
                  }
                >
                  {upperFirst(secondary.label)}
                </Button>
              )
            )}
          </>
        )}
      </div>
    </div>
  )
}

function LoopRow({
  loop,
  on,
  narrow,
  answered,
  onSelect,
}: {
  loop: ProjectLoop
  on: boolean
  narrow: boolean
  answered: boolean
  onSelect: () => void
}) {
  const { label, icon: Icon } = kindOf(loop.kind)
  const pending = usePending(keyOf(loop))
  return (
    <li
      className={cn(
        "flex flex-col rounded-lg border transition-colors",
        on
          ? "border-border bg-card shadow-sm"
          : "border-transparent hover:bg-muted"
      )}
    >
      <button
        type="button"
        onClick={onSelect}
        aria-current={on ? "true" : undefined}
        className="flex w-full min-w-0 flex-col gap-1.5 rounded-lg px-3 py-2.5 text-left"
      >
        <span className="flex min-w-0 items-center gap-2 text-xs text-muted-foreground">
          <Icon className="size-3.5 shrink-0" />
          <span className="shrink-0">{label}</span>
          <Badge variant="outline" className="shrink-0">
            {loop.project}
          </Badge>
          <span
            className={cn(
              "truncate font-mono",
              loop.askedAt === null && "ml-auto"
            )}
          >
            {loop.item}
          </span>
          {loop.askedAt !== null && (
            <span className="ml-auto shrink-0 tabular-nums">
              {age(loop.askedAt)}
            </span>
          )}
        </span>
        <span className="line-clamp-2 text-sm leading-snug font-medium break-words">
          {loop.title}
        </span>
        {pending ? (
          <Badge variant="run">Sending…</Badge>
        ) : (
          answered && (
            <Badge variant="done">
              <Check className="size-3" />
              Sent to STAR
            </Badge>
          )
        )}
      </button>
      {narrow && pending === "held" && (
        <div className="px-3 pb-3">
          <Button
            variant="outline"
            className="h-11 w-full"
            onClick={() => undoTap(loop)}
          >
            Undo
          </Button>
        </div>
      )}
      {narrow && !pending && !answered && loop.kind !== "error" && (
        <RowActions loop={loop} onOpen={onSelect} />
      )}
    </li>
  )
}

function Chips({
  value,
  onChange,
  count,
}: {
  value: Chip
  onChange: (value: Chip) => void
  count: (value: Chip) => number
}) {
  const chips: Array<{ id: Chip; label: string }> = [
    { id: "all", label: "All" },
    ...GROUPS.map((g) => ({ id: g.id, label: g.chip })),
  ]
  return (
    <div
      role="group"
      aria-label="Filter"
      className="-mx-4 flex gap-2 overflow-x-auto px-4 pb-1 [scrollbar-width:none] md:flex-wrap md:overflow-x-visible [&::-webkit-scrollbar]:hidden"
    >
      {chips.map((chip) => (
        <button
          key={chip.id}
          type="button"
          aria-pressed={value === chip.id}
          onClick={() => onChange(chip.id)}
          className={cn(
            "inline-flex h-9 shrink-0 items-center gap-1.5 rounded-full border px-3.5 text-sm font-medium transition-colors pointer-coarse:h-11",
            value === chip.id
              ? "border-foreground bg-foreground text-background"
              : "bg-background hover:bg-muted"
          )}
        >
          {chip.label}{" "}
          {chip.id === "hold" ? (
            <Badge variant="count">{count(chip.id)}</Badge>
          ) : (
            <span className="tabular-nums opacity-70">{count(chip.id)}</span>
          )}
        </button>
      ))}
    </div>
  )
}

function Kbd({ children }: { children: string }) {
  return (
    <kbd className="rounded border bg-muted px-1.5 py-0.5 font-mono text-[11px] text-foreground">
      {children}
    </kbd>
  )
}

function KeyHints() {
  return (
    <p className="flex flex-wrap items-center gap-x-4 gap-y-1 border-t px-4 py-2 text-xs text-muted-foreground">
      <span className="flex items-center gap-1">
        <Kbd>J</Kbd>
        <Kbd>K</Kbd> move
      </span>
      <span className="flex items-center gap-1">
        <Kbd>1</Kbd>
        <Kbd>2</Kbd> pick
      </span>
      <span className="flex items-center gap-1">
        <Kbd>⌘↵</Kbd> send
      </span>
    </p>
  )
}

export function NeedsPage() {
  const [params, setParams] = useSearchParams()
  const project = params.get("project") ?? ""
  const all = useAllLoops()
  const { value: loopParam, select, back } = useListSelection("loop")
  const narrow = useNarrow()
  const [chip, setChip] = useState<Chip>("all")
  // Answers sent from this page, by loop id, until STAR closes the item.
  const [sent, setSent] = useState<
    Record<string, { text: string; nudged: boolean }>
  >({})
  const rows = all.data ?? []
  const scopedRows = rows.filter((l) => !project || l.project === project)
  const sections = GROUPS.map((g) => ({
    ...g,
    loops: scopedRows.filter((l) => groupOf(l.kind) === g.id),
  })).filter((g) => (chip === "all" || chip === g.id) && g.loops.length > 0)
  const ordered = sections.flatMap((g) => g.loops)
  const named =
    scopedRows.find((l) => keyOf(l) === loopParam) ??
    (project ? scopedRows.find((l) => l.id === loopParam) : undefined)
  const selected = named ?? ordered[0] ?? scopedRows[0]

  // J and K move the selection on a desktop; they do nothing while the user types.
  useEffect(() => {
    if (narrow) return
    const onKey = (event: KeyboardEvent) => {
      if (event.metaKey || event.ctrlKey || event.altKey) return
      if (event.key !== "j" && event.key !== "k") return
      if (isTyping(event.target)) return
      const at = ordered.findIndex(
        (l) => selected && keyOf(l) === keyOf(selected)
      )
      const next = ordered[at + (event.key === "j" ? 1 : -1)]
      if (next) select(keyOf(next))
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  })

  if (all.isPending) {
    return (
      <LoadingState label="the open loops">
        <div className="grid gap-4 md:grid-cols-[minmax(300px,380px)_minmax(0,1fr)]">
          <div className="flex flex-col gap-2">
            <Skeleton className="h-9 w-64" />
            {[0, 1, 2, 3].map((i) => (
              <Skeleton key={i} className="h-16 w-full" />
            ))}
          </div>
          <div className="flex flex-col gap-4">
            <Skeleton className="h-8 w-3/4" />
            <Skeleton className="h-24 w-full" />
            <Skeleton className="h-32 w-full" />
          </div>
        </div>
      </LoadingState>
    )
  }
  if (queryFailed(all)) {
    return (
      <ErrorState
        what="the open loops"
        error={all.error}
        onRetry={() => void all.refetch()}
      />
    )
  }
  if (all.data!.length === 0) {
    return (
      <>
        {refreshFailed(all) && (
          <RefreshNotice
            what="the open loops"
            error={all.error}
            onRetry={() => void all.refetch()}
          />
        )}
        <EmptyState
          title="Nothing needs you right now."
          body="When STAR waits on one of your steps, a draft or a Slack reply, it shows here."
        />
      </>
    )
  }

  const scoped = scopedRows
  const count = (c: Chip) =>
    c === "all"
      ? scoped.length
      : scoped.filter((l) => groupOf(l.kind) === c).length
  const projectCount = new Set(scoped.map((l) => l.project)).size
  const holds = count("hold")
  const showDetail = named !== undefined
  // A phone marks a row current only when the URL names it; a desktop shows the first one.
  const current = narrow ? named : selected
  const sentOf = (loop: ProjectLoop) =>
    sent[keyOf(loop)]?.text ?? (isAnswered(loop) ? loop.answer : null)
  const clearFilter = () =>
    setParams(
      (prev) => {
        const next = new URLSearchParams(prev)
        next.delete("project")
        return next
      },
      { replace: true }
    )

  return (
    <>
      {refreshFailed(all) && (
        <RefreshNotice
          what="the open loops"
          error={all.error}
          onRetry={() => void all.refetch()}
        />
      )}
      <ListDetail
        showDetail={showDetail}
        onBack={back}
        backLabel="Needs you"
        listLabel="Open loops"
        detailLabel="Answer"
        columns="md:grid-cols-[minmax(300px,380px)_minmax(0,1fr)]"
        list={
          <>
            <div className="flex flex-col gap-3 p-4 pb-3">
              <div className="flex flex-col gap-0.5">
                <h1 className="text-base font-semibold">Needs you</h1>
                <p className="text-xs text-muted-foreground">
                  {plural(scoped.length, "open", "open")}
                  {project
                    ? ""
                    : ` across ${plural(projectCount, "project", "projects")}`}
                  . {holds} {holds === 1 ? "holds" : "hold"} up work.
                </p>
              </div>
              {project && (
                <div className="flex items-center justify-between gap-2 text-xs text-muted-foreground">
                  <span className="min-w-0 truncate">Only {project}</span>
                  <Button
                    variant="ghost"
                    size="sm"
                    className="h-7 px-2 pointer-coarse:h-11"
                    onClick={clearFilter}
                  >
                    Show every project
                  </Button>
                </div>
              )}
              <Chips value={chip} onChange={setChip} count={count} />
            </div>
            <ScrollArea className="min-h-0 flex-1">
              {ordered.length === 0 && (
                <p className="px-4 py-6 text-center text-sm text-muted-foreground">
                  Nothing here.
                </p>
              )}
              <div
                key={chip}
                data-slot="loop-sections"
                className="motion-fade-in flex flex-col gap-4 px-2 pb-3"
              >
                {sections.map((section) => (
                  <section
                    key={section.id}
                    aria-labelledby={`needs-${section.id}`}
                    className="flex flex-col gap-1"
                  >
                    <h2
                      id={`needs-${section.id}`}
                      className="flex items-center gap-2 px-2 text-sm font-semibold"
                    >
                      {section.heading}{" "}
                      <span className="font-medium text-muted-foreground tabular-nums">
                        {section.loops.length}
                      </span>
                    </h2>
                    <ul className="flex flex-col gap-1">
                      {section.loops.map((loop) => (
                        <LoopRow
                          key={keyOf(loop)}
                          loop={loop}
                          narrow={narrow}
                          on={
                            current !== undefined &&
                            keyOf(loop) === keyOf(current)
                          }
                          answered={sentOf(loop) !== null}
                          onSelect={() => select(keyOf(loop))}
                        />
                      ))}
                    </ul>
                  </section>
                ))}
              </div>
            </ScrollArea>
            {!narrow && <KeyHints />}
          </>
        }
        detail={
          selected && (
            <LoopDetail
              key={keyOf(selected)}
              project={selected.project}
              loop={selected}
              sentText={sent[keyOf(selected)]?.text ?? null}
              sentNudged={sent[keyOf(selected)]?.nudged}
              serverAnswer={sent[keyOf(selected)] ? null : selected.answer}
              onSent={(text, nudged) =>
                setSent((s) => ({ ...s, [keyOf(selected)]: { text, nudged } }))
              }
            />
          )
        }
      />
    </>
  )
}
