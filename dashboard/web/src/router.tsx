import { createBrowserRouter, Navigate, type RouteObject } from "react-router"
import { AppLayout } from "@/components/app-layout"
import { RouteError } from "@/components/route-error"
import { AccountsPage } from "@/pages/accounts"
import { BriefingPage } from "@/pages/briefing"
import { ChatPage } from "@/pages/chat"
import { EvidencePage } from "@/pages/evidence"
import { MorePage } from "@/pages/more"
import { NeedsPage } from "@/pages/needs"
import { NeedsRedirect } from "@/pages/needs-redirect"
import { NotFound } from "@/pages/not-found"
import { ProgressPage } from "@/pages/progress"
import { RootRedirect } from "@/pages/root-redirect"

// Real page paths per project (brief D1). The dashboard server answers index.html for every
// non-/api path, so a reload of /<project>/progress lands here.
export const routes: RouteObject[] = [
  { path: "/", Component: RootRedirect, errorElement: <RouteError /> },
  {
    path: "/needs",
    Component: AppLayout,
    errorElement: <RouteError />,
    children: [
      { index: true, Component: NeedsPage, errorElement: <RouteError /> },
      { path: "*", Component: NotFound, errorElement: <RouteError /> },
    ],
  },
  {
    path: "/:project",
    Component: AppLayout,
    errorElement: <RouteError />,
    children: [
      {
        index: true,
        element: <Navigate to="progress" replace />,
        errorElement: <RouteError />,
      },
      { path: "needs", Component: NeedsRedirect, errorElement: <RouteError /> },
      {
        path: "progress",
        Component: ProgressPage,
        errorElement: <RouteError />,
      },
      { path: "chat", Component: ChatPage, errorElement: <RouteError /> },
      {
        path: "briefing",
        Component: BriefingPage,
        errorElement: <RouteError />,
      },
      {
        path: "evidence",
        Component: EvidencePage,
        errorElement: <RouteError />,
      },
      { path: "more", Component: MorePage, errorElement: <RouteError /> },
      {
        path: "accounts",
        Component: AccountsPage,
        errorElement: <RouteError />,
      },
      { path: "*", Component: NotFound, errorElement: <RouteError /> },
    ],
  },
  { path: "*", Component: NotFound, errorElement: <RouteError /> },
]

export const createAppRouter = () => createBrowserRouter(routes)
