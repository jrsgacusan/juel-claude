// The ticket block every briefing reply ends with (brief D6): a fenced block whose info string is
// `ticket`, holding {title, description, criteria, outOfScope}.

export type Ticket = { title: string; description: string; criteria: string[]; outOfScope: string[] }

// A closed block: the opening fence line, the JSON, the closing fence line.
const BLOCK = /^```ticket[ \t]*\r?\n([\s\S]*?)\r?\n```[ \t]*$/gm
// An opening fence with no close yet: a reply cut mid-block.
const OPEN = /^```ticket[ \t]*$/m

const isStrings = (value: unknown): value is string[] => Array.isArray(value) && value.every(item => typeof item === 'string')

/** The ticket in a block's JSON, or null when it does not parse or a field has the wrong type. */
export function parseTicket(json: string): Ticket | null {
  let value: unknown
  try {
    value = JSON.parse(json)
  } catch {
    return null
  }
  if (typeof value !== 'object' || value === null || Array.isArray(value)) return null
  const { title, description, criteria, outOfScope } = value as Record<string, unknown>
  if (typeof title !== 'string' || title.trim() === '') return null
  if (typeof description !== 'string' || !isStrings(criteria) || !isStrings(outOfScope)) return null
  return { title: title.trim(), description, criteria, outOfScope }
}

/** The text with every ticket block removed, and an unclosed one cut from its fence to the end (B2). */
export function stripTickets(text: string): string {
  const closed = text.replace(BLOCK, '')
  const open = closed.search(OPEN)
  return (open === -1 ? closed : closed.slice(0, open)).replace(/\n{3,}/g, '\n\n').trim()
}

/** The reply as shown, and the last ticket block in it that is valid (D6, B1). */
export function extractTicket(reply: string): { shown: string; ticket: Ticket | null } {
  let ticket: Ticket | null = null
  for (const match of reply.matchAll(BLOCK)) ticket = parseTicket(match[1]) ?? ticket
  return { shown: stripTickets(reply), ticket }
}
