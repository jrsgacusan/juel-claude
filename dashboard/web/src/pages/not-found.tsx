import { Link, useLocation } from "react-router"
import { EmptyState } from "@/components/page-state"
import { Button } from "@/components/ui/button"

export function NotFound() {
  const { pathname } = useLocation()
  return (
    <EmptyState
      title={`There is no page at ${pathname}.`}
      body="The dashboard has Needs you, Progress, Chat, Briefing, Evidence and More for each project, and Claude accounts."
      action={
        <Button asChild variant="outline" size="sm">
          <Link to="/">Go to the dashboard</Link>
        </Button>
      }
    />
  )
}
