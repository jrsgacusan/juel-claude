import type { LucideIcon } from "lucide-react"
import {
  CircleAlert,
  CircleDot,
  CirclePause,
  FilePen,
  KeyRound,
  MessageSquare,
} from "lucide-react"
import type { Loop, LoopOption } from "@/api/types"

export type LoopGroup = "hold" | "slack" | "other"

// Kinds that hold up work come first in Needs you; the page keeps the server's order inside a group.
const HOLD = new Set(["person", "set-aside"])

export const groupOf = (kind: string): LoopGroup =>
  HOLD.has(kind) ? "hold" : kind === "slack-reply" ? "slack" : "other"

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

const KIND_LINE = /^kind:\s*(\S+)/i
const ALSO_LINE = /^also:\s*(\S+)/i

/** The word of a person item's `kind: <word>` body line. */
export function subkindOf(body: string[]): string | null {
  for (const line of body) {
    const word = KIND_LINE.exec(line.trim())?.[1]
    if (word) return word.toLowerCase()
  }
  return null
}

const SUBKINDS: Record<string, string> = {
  secret: "Secret",
  account: "Account",
  screen: "At your screen",
  approval: "Approval",
  access: "Access",
}

export const subkindLabel = (word: string): string =>
  SUBKINDS[word] ?? word.replace(/^./, (c) => c.toUpperCase())

/** The item of each `also: <item> <brief path> #<n> <kind>` body line. */
export function alsoItems(body: string[]): string[] {
  return body.flatMap((line) => {
    const item = ALSO_LINE.exec(line.trim())?.[1]
    return item ? [item] : []
  })
}

/** The body lines to show: never blank, kind:, also:, Options: or Suggest: lines; for a slack-reply, never its draft: and message: lines (the page shows the draft and the message itself). */
export function visibleBody(loop: Loop): string[] {
  return loop.body.filter((line) => {
    const text = line.trim()
    if (/^(options|suggest|kind|also):/i.test(text)) return false
    if (loop.kind === "slack-reply" && /^(draft|message):/i.test(text))
      return false
    return text.length > 0
  })
}

/** The one-tap answer: the recommended option, else the first. */
export const primaryOf = (loop: Loop): LoopOption | null =>
  loop.options.find((o) => o.recommended) ?? loop.options[0] ?? null

/** The second one-tap button: the other option when there are exactly two, "open" when there are more. */
export function secondaryOf(loop: Loop): LoopOption | "open" | null {
  if (loop.options.length > 2) return "open"
  if (loop.options.length < 2) return null
  const primary = primaryOf(loop)
  return loop.options.find((o) => o !== primary) ?? null
}

export const isAnswered = (loop: Loop): boolean => Boolean(loop.answer?.trim())
