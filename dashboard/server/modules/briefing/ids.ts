// Briefing ids and inbox file names share STAR's inbox form (brief D8, skills/star/SKILL.md:244):
// <UTC YYYYMMDDTHHMMSSZ>-<4 hex>.
import { randomBytes } from 'node:crypto'

export const ID_RE = /^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{4}$/

/** UTC YYYYMMDDTHHMMSSZ. */
export function stamp(date: Date = new Date()): string {
  return date.toISOString().replace(/\.\d{3}Z$/, 'Z').replace(/[-:]/g, '')
}

export function hex4(): string {
  return randomBytes(2).toString('hex')
}

export function newId(date: Date = new Date()): string {
  return `${stamp(date)}-${hex4()}`
}

/** True only for the id form, so an id can never name a path outside briefings/. */
export function isId(value: unknown): value is string {
  return typeof value === 'string' && ID_RE.test(value)
}
