import type { LucideIcon } from "lucide-react"
import {
  CircleAlert,
  CircleDot,
  CirclePause,
  FileCheck,
  FilePen,
  GitMerge,
  Hourglass,
  KeyRound,
  MessageCircleQuestion,
  MessageSquare,
  Play,
  RotateCcw,
} from "lucide-react"
import type { Loop } from "@/api/types"

export type LoopGroup = "blocked" | "slack" | "others"

// The kinds the server lists first. The page keeps the server's order; these only pick the tab.
const BLOCKED = new Set([
  "go-batch",
  "question",
  "person",
  "escalation",
  "restart-or-drop",
  "go-merge",
])

export const groupOf = (kind: string): LoopGroup =>
  BLOCKED.has(kind) ? "blocked" : kind === "slack-reply" ? "slack" : "others"

const KINDS: Record<string, { label: string; icon: LucideIcon }> = {
  "go-batch": { label: "Go for a batch", icon: Play },
  question: { label: "Question", icon: MessageCircleQuestion },
  person: { label: "Your step", icon: KeyRound },
  escalation: { label: "Stopped", icon: CircleAlert },
  "restart-or-drop": { label: "Restart or drop", icon: RotateCcw },
  "go-merge": { label: "Go to merge", icon: GitMerge },
  "slack-reply": { label: "Slack reply", icon: MessageSquare },
  "accept-report": { label: "Report to accept", icon: FileCheck },
  held: { label: "Held until later", icon: CirclePause },
  draft: { label: "Draft to check", icon: FilePen },
  waiting: { label: "Waiting on others", icon: Hourglass },
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
