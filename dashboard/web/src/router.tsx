import { createBrowserRouter, Navigate, type RouteObject } from "react-router"
import { AppLayout } from "@/components/app-layout"
import { BriefingPage } from "@/pages/briefing"
import { EvidencePage } from "@/pages/evidence"
import { NeedsPage } from "@/pages/needs"
import { NotFound } from "@/pages/not-found"
import { ProgressPage } from "@/pages/progress"
import { RootRedirect } from "@/pages/root-redirect"
import { SlackPage } from "@/pages/slack"

// Real page paths per project (brief D1). The dashboard server answers index.html for every
// non-/api path, so a reload of /<project>/progress lands here.
export const routes: RouteObject[] = [
  { path: "/", Component: RootRedirect },
  {
    path: "/:project",
    Component: AppLayout,
    children: [
      { index: true, element: <Navigate to="needs" replace /> },
      { path: "needs", Component: NeedsPage },
      { path: "progress", Component: ProgressPage },
      { path: "slack", Component: SlackPage },
      { path: "briefing", Component: BriefingPage },
      { path: "evidence", Component: EvidencePage },
      { path: "*", Component: NotFound },
    ],
  },
  { path: "*", Component: NotFound },
]

export const createAppRouter = () => createBrowserRouter(routes)
