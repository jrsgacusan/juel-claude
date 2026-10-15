import { Plus } from "lucide-react"
import { useParams, useSearchParams } from "react-router"
import { toast } from "sonner"
import { useBriefings, useNewBriefing } from "@/api/queries"
import {
  EmptyState,
  ErrorState,
  LoadingState,
  queryFailed,
  RefreshNotice,
  refreshFailed,
} from "@/components/page-state"
import { Button } from "@/components/ui/button"
import { Skeleton } from "@/components/ui/skeleton"
import { errorMessage } from "@/lib/errors"
import { Conversation } from "./briefing-chat"
import { DraftPanel } from "./briefing-draft"

export function BriefingPage() {
  const { project = "" } = useParams()
  const briefings = useBriefings(project)
  const newBriefing = useNewBriefing(project)
  const [params, setParams] = useSearchParams()

  const create = async () => {
    try {
      const { id } = await newBriefing.mutateAsync()
      setParams({ briefing: id })
    } catch (error) {
      toast.error(`Couldn't start a briefing: ${errorMessage(error)}`)
    }
  }
  const newButton = (
    <Button
      variant="outline"
      size="sm"
      onClick={() => void create()}
      disabled={newBriefing.isPending}
    >
      <Plus className="size-3.5" />
      New briefing
    </Button>
  )

  if (briefings.isPending) {
    return (
      <LoadingState label="the briefings">
        <div className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_400px]">
          <div className="flex flex-col gap-4">
            <Skeleton className="h-9 w-56" />
            {[0, 1, 2].map((i) => (
              <Skeleton key={i} className="h-16 w-full" />
            ))}
          </div>
          <Skeleton className="h-96 w-full" />
        </div>
      </LoadingState>
    )
  }
  if (queryFailed(briefings))
    return (
      <ErrorState
        what="the briefings"
        error={briefings.error}
        onRetry={() => void briefings.refetch()}
      />
    )
  if (briefings.data!.length === 0) {
    return (
      <>
        {refreshFailed(briefings) && (
          <RefreshNotice
            what="the briefings"
            error={briefings.error}
            onRetry={() => void briefings.refetch()}
          />
        )}
        <EmptyState
          title="No briefings yet."
          body="Start one to shape a piece of work with the briefing agent; it ends in a ticket STAR picks up."
          action={newButton}
        />
      </>
    )
  }

  const id = params.get("briefing") ?? briefings.data![0]?.id ?? null
  return (
    <>
      {refreshFailed(briefings) && (
        <RefreshNotice
          what="the briefings"
          error={briefings.error}
          onRetry={() => void briefings.refetch()}
        />
      )}
      <div className="grid min-h-0 min-w-0 flex-1 md:h-full md:overflow-y-auto lg:grid-cols-[minmax(0,1fr)_400px] lg:overflow-hidden">
        <Conversation
          key={id ?? "none"}
          project={project}
          id={id}
          briefings={briefings.data!}
          onPick={(next) => setParams({ briefing: next })}
          newButton={newButton}
        />
        <DraftPanel key={`draft-${id ?? "none"}`} project={project} id={id} />
      </div>
    </>
  )
}
