import type { LucideIcon } from "lucide-react"
import {
  Bot,
  CircleCheck,
  FileText,
  GitMerge,
  GitPullRequest,
  Play,
  ShieldCheck,
  UserCheck,
} from "lucide-react"
import { useState } from "react"
import { useFileBlob } from "@/api/files"
import { useEvidenceItem, useItems } from "@/api/queries"
import type { EvidenceFile } from "@/api/types"
import { ErrorState } from "@/components/page-state"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { Skeleton } from "@/components/ui/skeleton"
import { clock, dateTime, dayLabel } from "@/lib/format"

const CHECKS: Array<[icon: LucideIcon, label: string, key: string]> = [
  [Bot, "Claude review", "review"],
  [ShieldCheck, "Codex gate", "gate"],
  [CircleCheck, "CI", "ci"],
  [UserCheck, "Approval", "approval"],
]

export function Thumb({
  file,
  onOpen,
}: {
  file: EvidenceFile
  onOpen: (file: EvidenceFile) => void
}) {
  const content = useFileBlob(file.url, file.kind)
  return (
    <button
      type="button"
      onClick={() => onOpen(file)}
      aria-label={`Open ${file.name}`}
      className="group flex min-w-0 flex-col gap-1.5 text-left focus-visible:outline-none"
    >
      <span className="relative block aspect-video w-full overflow-hidden rounded-lg border bg-shot transition-shadow group-hover:shadow-md group-focus-visible:ring-2 group-focus-visible:ring-ring">
        {content.isLoading && (
          <Skeleton className="absolute inset-0 rounded-none" />
        )}
        {file.kind === "image" && content.url && (
          <img
            src={content.url}
            alt=""
            className="size-full object-cover object-top"
          />
        )}
        {file.kind === "video" && content.url && (
          <video
            src={content.url}
            muted
            preload="metadata"
            aria-hidden="true"
            className="size-full object-cover"
          />
        )}
        {file.kind === "text" && content.text !== null && (
          <span className="absolute inset-0 flex flex-col gap-1 overflow-hidden p-3 font-mono text-[10px] leading-4 text-muted-foreground">
            {content.text
              .split("\n")
              .slice(0, 6)
              .map((line, i) => (
                <span key={i} className="truncate">
                  {line}
                </span>
              ))}
          </span>
        )}
        {file.kind === "video" && (
          <span className="absolute inset-0 grid place-items-center bg-black/25">
            <span className="grid size-9 place-items-center rounded-full bg-background/90 text-foreground shadow">
              <Play className="size-4" />
            </span>
          </span>
        )}
        {content.error && (
          <span className="absolute inset-0 grid place-items-center p-2 text-center text-xs text-stop-fg">
            Couldn't load it
          </span>
        )}
      </span>
      <span className="truncate font-mono text-[11px] text-muted-foreground">
        {file.name}
      </span>
    </button>
  )
}

function FullSize({ file }: { file: EvidenceFile }) {
  const content = useFileBlob(file.url, file.kind)
  if (content.isLoading) return <Skeleton className="aspect-video w-full" />
  if (content.error)
    return (
      <p role="alert" className="text-sm text-stop-fg">
        Couldn't load {file.name}.
      </p>
    )
  if (file.kind === "image")
    return (
      <img
        src={content.url ?? ""}
        alt={file.name}
        className="max-h-[75vh] w-full rounded-lg border object-contain"
      />
    )
  if (file.kind === "video")
    return (
      <video
        src={content.url ?? ""}
        controls
        autoPlay
        aria-label={file.name}
        className="max-h-[75vh] w-full rounded-lg border bg-black"
      />
    )
  return (
    <pre className="max-h-[75vh] overflow-auto rounded-lg border bg-muted p-4 font-mono text-xs leading-5 break-words whitespace-pre-wrap">
      {content.text}
    </pre>
  )
}

export function EvidenceDetailView({
  project,
  item,
}: {
  project: string
  item: string
}) {
  const detail = useEvidenceItem(project, item)
  const items = useItems(project)
  const [zoom, setZoom] = useState<EvidenceFile | null>(null)
  const [recordOpen, setRecordOpen] = useState(false)

  if (detail.isPending)
    return (
      <div className="flex flex-col gap-4 p-4 sm:p-6 lg:p-8">
        <Skeleton className="h-8 w-2/3" />
        <Skeleton className="h-24 w-full" />
        <Skeleton className="h-48 w-full" />
      </div>
    )
  if (detail.isError)
    return (
      <ErrorState
        what="this item's evidence"
        error={detail.error}
        onRetry={() => void detail.refetch()}
      />
    )
  const d = detail.data
  const prUrl = items.data?.find((r) => r.item === d.item)?.prUrl ?? null
  const go = d.record.go ? `: "${d.record.go}"` : ""

  return (
    <div className="mx-auto flex max-w-4xl flex-col gap-6 p-4 sm:p-6 lg:p-8">
      <div className="flex flex-col gap-3">
        <div className="flex flex-wrap items-center gap-2">
          <Badge variant="done">
            <GitMerge className="size-3" />
            Merged
          </Badge>
          <span className="font-mono text-xs text-muted-foreground">
            {d.item}
          </span>
          {d.sha && (
            <span className="font-mono text-xs text-muted-foreground">
              {d.sha}
            </span>
          )}
          <span className="text-xs text-muted-foreground">{`${dayLabel(d.mergedAt)}, ${clock(d.mergedAt)}`}</span>
        </div>
        <h2 className="text-xl font-semibold tracking-tight break-words sm:text-2xl">
          {d.title}
        </h2>
        {d.goAt && (
          <p className="text-sm text-muted-foreground">{`Merged under your go of ${dateTime(d.goAt)}${go}.`}</p>
        )}
        <div className="flex flex-wrap gap-2">
          {d.pr && prUrl ? (
            <Button variant="outline" size="sm" asChild>
              <a href={prUrl} target="_blank" rel="noreferrer">
                <GitPullRequest className="size-3.5" />
                PR {d.pr}
              </a>
            </Button>
          ) : d.pr ? (
            <Badge variant="outline">
              <GitPullRequest className="size-3" />
              PR {d.pr}
            </Badge>
          ) : null}
          <Button
            variant="outline"
            size="sm"
            onClick={() => setRecordOpen(true)}
          >
            <FileText className="size-3.5" />
            Release record
          </Button>
        </div>
      </div>
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        {CHECKS.map(([Icon, label, key]) => (
          <Card key={key} className="gap-1 p-3">
            <span className="flex items-center gap-1.5 text-xs text-muted-foreground">
              <Icon className="size-3.5" />
              {label}
            </span>
            <span className="text-sm font-medium">
              {d.record[key] ?? "Not recorded"}
            </span>
          </Card>
        ))}
      </div>
      <div className="flex flex-col gap-3">
        <h3 className="text-sm font-medium">Acceptance criteria</h3>
        {d.groups.map((group) => (
          <div
            key={group.criterion || "files"}
            className="flex flex-col gap-3 rounded-xl border p-4"
          >
            <p className="flex items-start gap-2 text-sm font-medium">
              <CircleCheck className="mt-0.5 size-4 shrink-0 text-done" />
              <span className="min-w-0 break-words">
                <span className="sr-only">Passed: </span>
                {group.criterion || "Files"}
              </span>
            </p>
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
              {group.files.map((file) => (
                <Thumb key={file.url} file={file} onOpen={setZoom} />
              ))}
            </div>
          </div>
        ))}
      </div>
      <Dialog
        open={zoom !== null}
        onOpenChange={(open) => !open && setZoom(null)}
      >
        <DialogContent className="sm:max-w-4xl">
          <DialogHeader>
            <DialogTitle className="truncate font-mono text-xs">
              {zoom?.name}
            </DialogTitle>
            <DialogDescription className="sr-only">
              The file at full size
            </DialogDescription>
          </DialogHeader>
          {zoom && <FullSize file={zoom} />}
        </DialogContent>
      </Dialog>
      <Dialog open={recordOpen} onOpenChange={setRecordOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Release record</DialogTitle>
            <DialogDescription>{`${d.item}, merged ${dateTime(d.mergedAt)}`}</DialogDescription>
          </DialogHeader>
          <dl className="grid grid-cols-[auto_minmax(0,1fr)] gap-x-4 gap-y-2 text-sm">
            {Object.entries(d.record).map(([key, value]) => (
              <div key={key} className="contents">
                <dt className="text-muted-foreground">{key}</dt>
                <dd className="break-words">{value}</dd>
              </div>
            ))}
          </dl>
        </DialogContent>
      </Dialog>
    </div>
  )
}
