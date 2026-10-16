import {
  CircleCheck,
  CirclePause,
  CircleX,
  ExternalLink,
  Images,
  LoaderCircle,
} from "lucide-react"
import { Link } from "react-router"
import { useItem, useLoops } from "@/api/queries"
import { ErrorState } from "@/components/page-state"
import { StateBadge } from "@/components/status"
import { Button } from "@/components/ui/button"
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet"
import { Skeleton } from "@/components/ui/skeleton"
import { age, clock } from "@/lib/format"
import { itemLabel } from "@/lib/items"
import { isAnswered } from "@/lib/loops"
import { projectPath } from "@/lib/routes"
import { prLabel, statusOf, stepText, TAB_OF } from "@/lib/status"

type StepTone = "done" | "run" | "wait" | "stop"

function StepIcon({ tone }: { tone: StepTone }) {
  if (tone === "done")
    return <CircleCheck className="size-4 text-done" aria-label="Done" />
  if (tone === "run")
    return (
      <LoaderCircle
        className="size-4 animate-spin text-run motion-reduce:animate-none"
        aria-label="Running"
      />
    )
  if (tone === "wait")
    return (
      <CirclePause className="size-4 text-wait" aria-label="Waiting on you" />
    )
  return <CircleX className="size-4 text-stop" aria-label="Stopped" />
}

function BulletList({ title, lines }: { title: string; lines: string[] }) {
  if (lines.length === 0) return null
  return (
    <div className="flex flex-col gap-2">
      <h3 className="text-sm font-medium">{title}</h3>
      <ul className="list-disc pl-5 text-sm leading-6">
        {lines.map((line) => (
          <li key={line}>{line}</li>
        ))}
      </ul>
    </div>
  )
}

export function ItemSheet({
  project,
  item,
  onClose,
}: {
  project: string
  item: string | null
  onClose: () => void
}) {
  const detail = useItem(project, item)
  const loops = useLoops(project)
  const row = detail.data?.row
  const tone = row ? statusOf(row.status).tone : "run"
  const lastTone: StepTone = tone === "muted" ? "run" : tone
  const waiting = row && TAB_OF[row.status] === "needs"
  // The item's own open loop first; else the go-batch that holds it (a go-batch loop's item is the batch, and its body lines name the items).
  const names = row ? [row.item, row.ref].filter(Boolean) : []
  const inBatch = (body: string[]) =>
    body.some((line) =>
      line.split(/[\s,]+/).some((word) => names.includes(word))
    )
  const loop = row
    ? (loops.data?.find((l) => l.item === row.item && !isAnswered(l)) ??
      loops.data?.find(
        (l) => l.kind === "go-batch" && !isAnswered(l) && inBatch(l.body)
      ))
    : undefined
  const pr = row ? prLabel(row) : null

  return (
    <Sheet open={item !== null} onOpenChange={(open) => !open && onClose()}>
      <SheetContent
        side="right"
        className="w-full gap-6 overflow-y-auto p-6 sm:max-w-md"
      >
        <SheetHeader className="p-0">
          <span className="font-mono text-xs text-muted-foreground">
            {row ? itemLabel(row) : item}
          </span>
          <SheetTitle className="text-lg leading-snug">
            {row?.title ?? row?.item ?? item ?? ""}
          </SheetTitle>
          <SheetDescription className="sr-only">
            The item's branch, PR and step log
          </SheetDescription>
          {row && <StateBadge status={row.status} />}
        </SheetHeader>
        {detail.isPending && item !== null && (
          <div className="flex flex-col gap-3">
            <Skeleton className="h-16 w-full" />
            <Skeleton className="h-40 w-full" />
          </div>
        )}
        {detail.isError && (
          <ErrorState
            what="this item"
            error={detail.error}
            onRetry={() => void detail.refetch()}
          />
        )}
        {detail.data && row && (
          <>
            <dl className="grid grid-cols-[96px_minmax(0,1fr)] gap-x-4 gap-y-2 text-sm">
              <dt className="text-muted-foreground">Worktree</dt>
              <dd className="truncate font-mono text-xs leading-5">
                {row.worktree && row.worktree !== "-"
                  ? row.worktree
                  : "Not created yet"}
              </dd>
              <dt className="text-muted-foreground">PR</dt>
              <dd className="font-mono text-xs leading-5">
                {pr ?? "None yet"}
              </dd>
              <dt className="text-muted-foreground">Updated</dt>
              <dd className="tabular-nums">
                {row.updated ? age(row.updated) : "Unknown"}
              </dd>
            </dl>
            <div className="flex flex-col gap-3">
              <h3 className="text-sm font-medium">Steps</h3>
              <ol className="relative flex flex-col gap-4 before:absolute before:top-2 before:bottom-2 before:left-[7.5px] before:w-px before:bg-border">
                {detail.data.progress.map((line, i, all) => (
                  <li
                    key={`${line.time}-${i}`}
                    className="relative flex items-start gap-3"
                  >
                    <span className="z-10 bg-background">
                      <StepIcon
                        tone={i === all.length - 1 ? lastTone : "done"}
                      />
                    </span>
                    <span className="min-w-0 flex-1 text-sm leading-5 break-words">
                      {stepText(line.text)}
                    </span>
                    <span className="font-mono text-xs text-muted-foreground tabular-nums">
                      {clock(line.time)}
                    </span>
                  </li>
                ))}
              </ol>
            </div>
            <BulletList
              title="Acceptance criteria"
              lines={detail.data.criteria}
            />
            <BulletList title="Decisions" lines={detail.data.decisions} />
            <div className="mt-auto flex flex-wrap gap-2">
              {waiting && (
                <Button asChild>
                  <Link
                    to={projectPath(
                      project,
                      "needs",
                      loop ? { loop: loop.id } : undefined
                    )}
                  >
                    Answer in Needs you
                  </Link>
                </Button>
              )}
              {row.prUrl && pr && (
                <Button variant="outline" asChild>
                  <a href={row.prUrl} target="_blank" rel="noreferrer">
                    <ExternalLink />
                    Open PR {pr}
                  </a>
                </Button>
              )}
              {row.status === "merged" && (
                <Button variant="outline" asChild>
                  <Link
                    to={projectPath(project, "evidence", { item: row.item })}
                  >
                    <Images />
                    Evidence
                  </Link>
                </Button>
              )}
            </div>
          </>
        )}
      </SheetContent>
    </Sheet>
  )
}
