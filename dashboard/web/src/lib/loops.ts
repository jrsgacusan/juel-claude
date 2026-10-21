import type { LucideIcon } from "lucide-react"
import {
  CircleAlert,
  CircleDot,
  CirclePause,
  FilePen,
  KeyRound,
  MessageSquare,
} from "lucide-react"
import type { Loop } from "@/api/types"

export type LoopGroup = "blocked" | "slack" | "others"

// The kinds the server lists first. The page keeps the server's order; these only pick the tab.
const BLOCKED = new Set(["person"])

export const groupOf = (kind: string): LoopGroup =>
  BLOCKED.has(kind) ? "blocked" : kind === "slack-reply" ? "slack" : "others"

const KINDS: Record<string, { label: string; icon: LucideIcon }> = {
  person: { label: "Your step", icon: KeyRound },
  "set-aside": { label: "Set aside", icon: CirclePause },
  "slack-reply": { label: "Slack reply", icon: MessageSquare },
  draft: { label: "Draft to check", icon: FilePen },
  error: { label: "Unreadable", icon: CircleAlert },
}

export function kindOf(kind: string): { label: string; icon: LucideIcon } {
  return (
    KINDS[kind] ?? {
      label: kind.replace(/-/g, " ").replace(/^./, (c) => c.toUpperCase()),
      icon: CircleDot,
    }
  )
}

/** The body lines to show: never blank, Options: or Suggest: lines; for a slack-reply, never its draft: and message: lines (the page shows the draft and the message itself). */
export function visibleBody(loop: Loop): string[] {
  return loop.body.filter((line) => {
    const text = line.trim()
    if (/^(options|suggest):/i.test(text)) return false
    if (loop.kind === "slack-reply" && /^(draft|message):/i.test(text))
      return false
    return text.length > 0
  })
}

export const isAnswered = (loop: Loop): boolean => Boolean(loop.answer?.trim())
