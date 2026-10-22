import { Check, CircleAlert } from "lucide-react"
import { useState } from "react"
import { toast } from "sonner"
import { ApiError } from "@/api/client"
import {
  useBriefing,
  useBriefings,
  useCreateTicket,
  useSetTracker,
  useTracker,
} from "@/api/queries"
import type { Tracker } from "@/api/types"
import { Button } from "@/components/ui/button"
import { Label } from "@/components/ui/label"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"
import { Skeleton } from "@/components/ui/skeleton"
import { errorMessage } from "@/lib/errors"
import { agoText } from "@/lib/format"
import { cn } from "@/lib/utils"

const TRACKER_LABEL: Record<Tracker, string> = {
  synapse: "Synapse",
  linear: "Linear",
  jira: "Jira",
  github: "GitHub Issues",
  none: "No tracker, a spec file STAR keeps",
}
const TRACKERS: Tracker[] = ["synapse", "linear", "jira", "github", "none"]

export function DraftPanel({
  project,
  id,
  className,
}: {
  project: string
  id: string | null
  className?: string
}) {
  const briefing = useBriefing(project, id)
  const briefings = useBriefings(project)
  const tracker = useTracker(project)
  const setTracker = useSetTracker(project)
  const create = useCreateTicket(project, id ?? "")
  const [createError, setCreateError] = useState<string | null>(null)
  const [createConflict, setCreateConflict] = useState(false)
  const chosen = tracker.data?.tracker ?? null
  // Synapse has no connector, so it always becomes a spec. Linear and Jira are found out only
  // when the create runs (briefing brief D5): say they may become a spec. GitHub and none never warn.
  const notConnected = chosen === "synapse"
  const mayBeSpec = chosen === "linear" || chosen === "jira"
  const where =
    chosen !== null && chosen !== "none" && !notConnected
      ? TRACKER_LABEL[chosen]
      : null
  const draft = briefing.data?.draft ?? null
  const updatedAt = briefings.data?.find((b) => b.id === id)?.updatedAt
  const existingRef = briefings.data?.find((b) => b.id === id)?.ref ?? null

  const createIn = async (target: Tracker) => {
    if (!id) return
    try {
      const res = await create.mutateAsync({ tracker: target })
      setCreateError(null)
      setCreateConflict(false)
      toast.success(
        "ref" in res
          ? `${res.ref} created in ${TRACKER_LABEL[target]}. STAR is briefing it now.`
          : target === "linear" || target === "jira"
            ? `${TRACKER_LABEL[target]} isn't connected in Claude Code, so it was saved as a spec file. STAR is briefing it now.`
            : "Saved as a spec file. STAR is briefing it now."
      )
    } catch (error) {
      setCreateError(errorMessage(error))
      setCreateConflict(error instanceof ApiError && error.status === 409)
    }
  }

  const label =
    chosen === null
      ? "Pick where the ticket goes first"
      : where
        ? `Create in ${where} and hand to STAR`
        : "Save as a spec and hand to STAR"

  return (
    <section
      aria-label="Ticket draft"
      className={cn(
        "min-h-0 min-w-0 bg-card max-md:overflow-y-auto lg:overflow-y-auto",
        className
      )}
    >
      <div className="flex flex-col gap-5 p-4 sm:p-6">
        <div className="flex items-center justify-between gap-2">
          <h2 className="text-sm font-medium">Ticket draft</h2>
          {updatedAt && (
            <span className="text-xs text-muted-foreground">
              Updated {agoText(updatedAt)}
            </span>
          )}
        </div>
        <div className="flex flex-col gap-2">
          <Label htmlFor="tracker">{`Where do ${project}'s tickets live?`}</Label>
          {tracker.isError ? (
            <div
              role="alert"
              className="flex items-center justify-between gap-3 text-xs text-stop-fg"
            >
              <span>
                Couldn&apos;t read where {project}&apos;s tickets live:{" "}
                {errorMessage(tracker.error)}
              </span>
              <Button
                variant="outline"
                size="sm"
                className="pointer-coarse:h-11"
                onClick={() => void tracker.refetch()}
              >
                Try again
              </Button>
            </div>
          ) : (
            <Select
              value={chosen ?? undefined}
              disabled={tracker.isPending}
              onValueChange={(value) =>
                setTracker.mutate({ tracker: value as Tracker })
              }
            >
              <SelectTrigger
                id="tracker"
                aria-label="Tracker"
                className={cn("h-9 w-full", chosen === null && "ring-2 ring-wait")}
              >
                <SelectValue placeholder="Pick one" />
              </SelectTrigger>
              <SelectContent>
                {TRACKERS.map((t) => (
                  <SelectItem key={t} value={t}>
                    {TRACKER_LABEL[t]}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          )}
          {chosen === null && !tracker.isPending && !tracker.isError && (
            <p className="text-xs font-medium text-wait-fg">
              Needed before the ticket can be created.
            </p>
          )}
          <p className="text-xs text-muted-foreground">{`Asked once, then saved for ${project}.`}</p>
          {setTracker.isError && (
            <p role="alert" className="text-xs text-stop-fg">
              Couldn't save it: {errorMessage(setTracker.error)}
            </p>
          )}
        </div>
        {notConnected && chosen && (
          <div
            role="note"
            className="flex gap-2 rounded-lg border border-wait-line bg-wait-bg p-3 text-sm text-wait-fg"
          >
            <CircleAlert className="mt-0.5 size-4 shrink-0" />
            <span>{`${TRACKER_LABEL[chosen]} isn't connected yet. Connect it in Claude Code to create the ticket there. Until then, this becomes a spec file STAR keeps.`}</span>
          </div>
        )}
        {mayBeSpec && chosen && (
          <div
            role="note"
            className="flex gap-2 rounded-lg border border-wait-line bg-wait-bg p-3 text-sm text-wait-fg"
          >
            <CircleAlert className="mt-0.5 size-4 shrink-0" />
            <span>{`${TRACKER_LABEL[chosen]} is used when its connector is connected in Claude Code. If it isn't, this becomes a spec file STAR keeps.`}</span>
          </div>
        )}
        {briefing.isPending && id ? (
          <Skeleton className="h-48 w-full" />
        ) : draft ? (
          <>
            <div className="flex flex-col gap-2 border-t pt-5">
              <h3 className="text-lg leading-snug font-semibold break-words">
                {draft.title}
              </h3>
              <p className="text-sm leading-6 break-words text-muted-foreground">
                {draft.description}
              </p>
            </div>
            <div className="flex flex-col gap-2">
              <h3 className="text-sm font-medium">Acceptance criteria</h3>
              <ul className="flex flex-col gap-2 text-sm leading-6">
                {draft.criteria.map((c) => (
                  <li key={c} className="flex gap-2">
                    <Check className="mt-1 size-4 shrink-0 text-muted-foreground" />
                    <span className="min-w-0 break-words">{c}</span>
                  </li>
                ))}
              </ul>
            </div>
            {draft.outOfScope.length > 0 && (
              <div className="flex flex-col gap-1">
                <h3 className="text-sm font-medium">Out of scope</h3>
                <p className="text-sm leading-6 break-words text-muted-foreground">
                  {draft.outOfScope.join(" ")}
                </p>
              </div>
            )}
          </>
        ) : (
          <p className="border-t pt-5 text-sm text-muted-foreground">
            The draft shows here once the agent has enough to propose a ticket.
          </p>
        )}
        {createError && (
          <div
            role="alert"
            className="flex flex-col gap-2 rounded-lg border border-stop-line bg-stop-bg p-3 text-sm text-stop-fg"
          >
            <span className="break-words">{`Couldn't create the ticket: ${createError}`}</span>
            {!createConflict && (
              <Button
                variant="outline"
                size="sm"
                className="self-start pointer-coarse:h-11"
                onClick={() => void createIn("none")}
              >
                Save as a spec instead
              </Button>
            )}
          </div>
        )}
        <Button
          size="lg"
          variant={chosen === null ? "outline" : "answer"}
          className={cn("w-full", chosen === null && "disabled:opacity-100")}
          disabled={
            chosen === null ||
            !draft ||
            create.isPending ||
            tracker.isPending ||
            tracker.isError ||
            existingRef !== null
          }
          onClick={() => chosen && void createIn(chosen)}
        >
          {existingRef ? `Created ${existingRef}` : label}
        </Button>
        <p className="-mt-2 text-center text-xs text-muted-foreground">
          STAR builds it once the brief is drafted, and asks you only for what a person must supply.
        </p>
      </div>
    </section>
  )
}
