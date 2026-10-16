import type { LucideIcon } from "lucide-react"
import {
  CircleCheck,
  FileText,
  Flag,
  GitMerge,
  GitPullRequest,
  Play,
  ShieldCheck,
  UserCheck,
} from "lucide-react"
import { useState } from "react"
import { useFileBlob } from "@/api/files"
import { useEvidenceItem } from "@/api/queries"
import type { EvidenceFile, EvidenceRecord } from "@/api/types"
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
import { errorMessage } from "@/lib/errors"
import { prLabel } from "@/lib/status"

// The four check cards read the release record the server sends (API contract, 2026-10-16).
// Go, Codex gate, CI and Approval, one card per release-record key, each "Not recorded" when missing (brief D11). No Claude review card: the release record has no such line.
const RECORD: Record<
  keyof EvidenceRecord,
  { icon: LucideIcon; label: string }
> = {
  go: { icon: Flag, label: "Go" },
  gate: { icon: ShieldCheck, label: "Codex gate" },
  ci: { icon: CircleCheck, label: "CI" },
  approval: { icon: UserCheck, label: "Approval" },
}
const RECORD_KEYS = Object.keys(RECORD) as Array<keyof EvidenceRecord>

function Thumb({
  file,
  onOpen,
}: {
  file: EvidenceFile
  onOpen: (file: EvidenceFile) => void
}) {
  const content = useFileBlob(file.url, file.kind)
  const [mediaError, setMediaError] = useState(false)
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
        {file.kind === "image" && content.url && !mediaError && (
          <img
            src={content.url}
            alt=""
            className="size-full object-cover object-top"
            onError={() => setMediaError(true)}
          />
        )}
        {file.kind === "video" && content.url && !mediaError && (
          <video
            src={content.url}
            muted
            preload="metadata"
            aria-hidden="true"
            className="size-full object-cover"
            onError={() => setMediaError(true)}
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
        {mediaError && (
          <span className="absolute inset-0 grid place-items-center p-2 text-center text-xs text-stop-fg">
            {file.name} could not be shown.
          </span>
        )}
        {content.error && (
          <span className="absolute inset-0 grid place-items-center p-2 text-center text-xs text-stop-fg">
            <span className="flex flex-col items-center gap-1">
              <span>Couldn&apos;t load it</span>
              <span
                className="cursor-pointer underline underline-offset-2"
                onClick={(event) => {
                  event.stopPropagation()
                  void content.refetch()
                }}
              >
                Try again
              </span>
            </span>
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
  const [mediaError, setMediaError] = useState(false)
  if (content.isLoading) return <Skeleton className="aspect-video w-full" />
  if (content.error)
    return (
      <div
        role="alert"
        className="flex flex-wrap items-center gap-3 text-sm text-stop-fg"
      >
        <span>{`Couldn't load ${file.name}: ${errorMessage(content.error)}`}</span>
        <Button
          variant="outline"
          size="sm"
          onClick={() => void content.refetch()}
        >
          Try again
        </Button>
      </div>
    )
  if (mediaError)
    return (
      <p className="text-sm text-stop-fg">{file.name} could not be shown.</p>
    )
  if (file.kind === "image")
    return (
      <img
        src={content.url ?? ""}
        alt={file.name}
        className="max-h-[75vh] w-full rounded-lg border object-contain"
        onError={() => setMediaError(true)}
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
        onError={() => setMediaError(true)}
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

  return (
    <div className="mx-auto flex max-w-4xl flex-col gap-6 p-4 sm:p-6 lg:p-8">
      <div className="flex flex-col gap-3">
        <div className="flex flex-wrap items-center gap-2">
          <Badge variant="done">
            <GitMerge className="size-3" />
            Merged
          </Badge>
          <span className="font-mono text-xs break-all text-muted-foreground">
            {d.item}
          </span>
          {d.sha && (
            <span className="font-mono text-xs break-all text-muted-foreground">
              {d.sha}
            </span>
          )}
          <span className="text-xs text-muted-foreground">
            {d.mergedAt === null
              ? "Unknown"
              : `${dayLabel(d.mergedAt)}, ${clock(d.mergedAt)}`}
          </span>
        </div>
        <h2 className="text-xl font-semibold tracking-tight break-words sm:text-2xl">
          {d.title ?? d.item}
        </h2>
        <p className="text-sm text-muted-foreground">
          {d.mergedAt === null
            ? "Merge time unknown."
            : d.sha
              ? `Merged ${d.sha} at ${dateTime(d.mergedAt)}.`
              : `Merged at ${dateTime(d.mergedAt)}.`}
        </p>
        <div className="flex flex-wrap gap-2">
          {d.pr ? (
            <Button variant="outline" size="sm" asChild>
              <a href={d.pr} target="_blank" rel="noreferrer">
                <GitPullRequest className="size-3.5" />
                PR {prLabel({ pr: "-", prUrl: d.pr }) ?? "link"}
              </a>
            </Button>
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
        {RECORD_KEYS.map((key) => {
          const { icon: Icon, label } = RECORD[key]
          return (
            <Card key={key} className="gap-1 p-3">
              <span className="flex items-center gap-1.5 text-xs text-muted-foreground">
                <Icon className="size-3.5" />
                {label}
              </span>
              <span className="text-sm font-medium">
                {d.record[key] ?? "Not recorded"}
              </span>
            </Card>
          )
        })}
      </div>
      <div className="flex flex-col gap-3">
        <h3 className="text-sm font-medium">Acceptance criteria</h3>
        {d.groups.map((group) => (
          <div
            key={group.criterion ?? "files"}
            className="flex flex-col gap-3 rounded-xl border p-4"
          >
            {group.criterion === null ? (
              <p className="text-sm font-medium">Files</p>
            ) : (
              <p className="flex items-start gap-2 text-sm font-medium">
                <CircleCheck className="mt-0.5 size-4 shrink-0 text-done" />
                <span className="min-w-0 break-words">
                  <span className="sr-only">Passed: </span>
                  {group.criterion}
                </span>
              </p>
            )}
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
            <DialogDescription>
              {d.mergedAt === null
                ? `${d.item}, merge time unknown`
                : `${d.item}, merged ${dateTime(d.mergedAt)}`}
            </DialogDescription>
          </DialogHeader>
          <dl className="grid grid-cols-[auto_minmax(0,1fr)] gap-x-4 gap-y-2 text-sm">
            {RECORD_KEYS.filter((key) => d.record[key] !== undefined).map(
              (key) => (
                <div key={key} className="contents">
                  <dt className="text-muted-foreground">{RECORD[key].label}</dt>
                  <dd className="break-words">{d.record[key]}</dd>
                </div>
              )
            )}
          </dl>
        </DialogContent>
      </Dialog>
    </div>
  )
}
