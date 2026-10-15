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

// The server's order (star-dashboard-server.md): blocked work, then slack-reply, then the rest.
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

/** The body lines to show: never the Options or Suggest lines; for a slack-reply, never its file lines. */
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
