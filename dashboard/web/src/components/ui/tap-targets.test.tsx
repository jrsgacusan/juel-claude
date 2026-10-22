import { render, screen } from "@testing-library/react"
import { QueryClientProvider } from "@tanstack/react-query"
import { MemoryRouter } from "react-router"
import { describe, expect, it } from "vitest"
import { createQueryClient } from "@/api/queries"
import { SiteHeader } from "../site-header"
import { ThemeProvider } from "../theme-provider"
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "./dialog"
import { Sheet, SheetContent, SheetDescription, SheetTitle } from "./sheet"
import { SidebarMenu, SidebarMenuButton, SidebarMenuItem, SidebarProvider, SidebarTrigger } from "./sidebar"
import { TooltipProvider } from "./tooltip"
import { Tabs, TabsList, TabsTrigger } from "./tabs"

describe("tap targets on a coarse pointer, desktop sizes kept", () => {
  it("the sidebar trigger and menu items", () => {
    render(
      <SidebarProvider>
        <SidebarTrigger />
        <SidebarMenu>
          <SidebarMenuItem><SidebarMenuButton>Needs you</SidebarMenuButton></SidebarMenuItem>
          <SidebarMenuItem><SidebarMenuButton size="sm">Small</SidebarMenuButton></SidebarMenuItem>
        </SidebarMenu>
      </SidebarProvider>
    )
    expect(screen.getByRole("button", { name: "Toggle Sidebar" })).toHaveClass("size-8", "pointer-coarse:size-11")
    expect(screen.getByRole("button", { name: "Needs you" })).toHaveClass("h-8", "pointer-coarse:h-11")
    expect(screen.getByRole("button", { name: "Small" })).toHaveClass("h-7", "pointer-coarse:h-11")
  })
  it("the sheet and dialog close buttons", () => {
    render(
      <>
        <Sheet open><SheetContent><SheetTitle>Item</SheetTitle><SheetDescription>d</SheetDescription></SheetContent></Sheet>
        <Dialog open><DialogContent><DialogTitle>Shot</DialogTitle><DialogDescription>d</DialogDescription></DialogContent></Dialog>
      </>
    )
    const closes = screen.getAllByRole("button", { name: "Close", hidden: true })
    expect(closes).toHaveLength(2)
    for (const close of closes)
      expect(close).toHaveClass("size-8", "top-4", "right-4", "pointer-coarse:size-11", "pointer-coarse:top-2", "pointer-coarse:right-2")
  })
  it("the tabs", () => {
    render(<Tabs defaultValue="a"><TabsList><TabsTrigger value="a">Running</TabsTrigger></TabsList></Tabs>)
    expect(screen.getByRole("tablist")).toHaveClass("group-data-horizontal/tabs:h-9", "pointer-coarse:group-data-horizontal/tabs:h-auto")
    expect(screen.getByRole("tab", { name: "Running" })).toHaveClass("pointer-coarse:min-h-11")
  })
  it("the header search button and the theme button", () => {
    render(
      <QueryClientProvider client={createQueryClient()}>
        <MemoryRouter>
          <ThemeProvider>
            <SidebarProvider>
              <TooltipProvider><SiteHeader project="sphere-app" page="needs" onSearch={() => {}} /></TooltipProvider>
            </SidebarProvider>
          </ThemeProvider>
        </MemoryRouter>
      </QueryClientProvider>
    )
    expect(screen.getByRole("button", { name: "Search (⌘K)" })).toHaveClass("h-8", "pointer-coarse:size-11", "sm:pointer-coarse:w-64")
    expect(screen.getByRole("button", { name: "Theme: System" })).toHaveClass("h-8", "pointer-coarse:size-11")
  })
})
