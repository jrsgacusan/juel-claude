import { Plus } from "lucide-react"
import { useState } from "react"
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
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { errorMessage } from "@/lib/errors"
import { cn } from "@/lib/utils"
import { FILL_HEIGHT } from "./chat"
import { Conversation } from "./briefing-chat"
import { DraftPanel } from "./briefing-draft"

export function BriefingPage() {
  const { project = "" } = useParams()
  const briefings = useBriefings(project)
  const newBriefing = useNewBriefing(project)
  const [params, setParams] = useSearchParams()
  const [tab, setTab] = useState<"chat" | "draft">("chat")

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

  // The page's own links use ?briefing=; search results use ?id= (the server's route).
  const id =
    params.get("briefing") ?? params.get("id") ?? briefings.data![0]?.id ?? null
  return (
    <>
      {refreshFailed(briefings) && (
        <RefreshNotice
          what="the briefings"
          error={briefings.error}
          onRetry={() => void briefings.refetch()}
        />
      )}
      <div className={cn(FILL_HEIGHT, "flex min-w-0 flex-col")}>
        <Tabs
          value={tab}
          onValueChange={(value) => setTab(value === "draft" ? "draft" : "chat")}
          className="shrink-0 border-b px-3 py-2 md:hidden"
        >
          <TabsList className="w-full">
            <TabsTrigger value="chat">Chat</TabsTrigger>
            <TabsTrigger value="draft">Draft</TabsTrigger>
          </TabsList>
        </Tabs>
        <div className="grid min-h-0 min-w-0 flex-1 max-md:grid-rows-[minmax(0,1fr)] md:overflow-y-auto lg:grid-cols-[minmax(0,1fr)_400px] lg:overflow-hidden">
          <Conversation
            key={id ?? "none"}
            className={cn(tab !== "chat" && "max-md:hidden")}
            project={project}
            id={id}
            briefings={briefings.data!}
            onPick={(next) => setParams({ briefing: next })}
            newButton={newButton}
            onDeleted={() => setParams({}, { replace: true })}
          />
          <DraftPanel
            key={`draft-${id ?? "none"}`}
            className={cn(tab !== "draft" && "max-md:hidden")}
            project={project}
            id={id}
          />
        </div>
      </div>
    </>
  )
}
