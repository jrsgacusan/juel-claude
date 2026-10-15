import { CircleAlert, CircleStop, Unplug, X } from "lucide-react"
import type { ReactNode } from "react"
import { useConnection } from "@/api/events"
import { useProjects } from "@/api/queries"
import { Button } from "@/components/ui/button"
import { setConflict, useConflict } from "@/lib/conflict"
import { cn } from "@/lib/utils"

export function Banner({
  tone,
  icon,
  children,
  action,
}: {
  tone: "wait" | "stop"
  icon: ReactNode
  children: ReactNode
  action?: ReactNode
}) {
  return (
    <div
      role="status"
      className={cn(
        "flex items-start gap-2 border-b px-4 py-2.5 text-sm [&_svg]:mt-0.5 [&_svg]:size-4 [&_svg]:shrink-0",
        tone === "wait"
          ? "border-wait-line bg-wait-bg text-wait-fg"
          : "border-stop-line bg-stop-bg text-stop-fg"
      )}
    >
      {icon}
      <div className="min-w-0 flex-1">{children}</div>
      {action}
    </div>
  )
}

export function StoppedBanner({ project }: { project: string }) {
  const projects = useProjects()
  if (projects.data?.find((p) => p.name === project)?.state !== "stopped")
    return null
  return (
    <Banner tone="stop" icon={<CircleStop />}>
      {`STAR is stopped for ${project}. Start it with /juel:star in that project. Your answers wait in its queue.`}
    </Banner>
  )
}

export function ConflictBanner({ project }: { project: string }) {
  if (useConflict() !== project) return null
  return (
    <Banner
      tone="wait"
      icon={<CircleAlert />}
      action={
        <Button
          variant="ghost"
          size="icon"
          className="size-6"
          aria-label="Dismiss"
          onClick={() => setConflict(null)}
        >
          <X />
        </Button>
      }
    >
      open-loops.md has conflict markers. Resolve them, then answer here.
    </Banner>
  )
}

export function ConnectionBanner() {
  if (useConnection() !== "lost") return null
  return (
    <Banner tone="stop" icon={<Unplug />}>
      <span>Lost the connection to the dashboard server</span>
      <span className="opacity-80">. Reconnecting every 5 seconds.</span>
    </Banner>
  )
}
