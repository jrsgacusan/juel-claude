// D17, I-13: what waits on the owner, decided again on the server from the model's `why` label, so a
// wrong label cannot raise a message that is not for the owner. Dropped messages are never stored.
import type { Message, Owner } from './state.ts'

const escape = (text: string): string => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')

/** The owner's display name, the first word of the real name, then the extra names; no case-insensitive repeat. */
export function ownerNames(owner: Owner | null, extra: readonly string[]): string[] {
  const names: string[] = []
  for (const raw of [owner?.displayName ?? '', (owner?.realName ?? '').trim().split(/\s+/)[0] ?? '', ...extra]) {
    const name = raw.trim()
    if (name !== '' && !names.some(n => n.toLowerCase() === name.toLowerCase())) names.push(name)
  }
  return names
}

/** The name as a whole word, in any case: `@Juel` and `Juel,` match, `Juelz` does not. */
export const hasName = (text: string, name: string): boolean =>
  name !== '' && new RegExp(`(?<![\\p{L}\\p{N}_])${escape(name)}(?![\\p{L}\\p{N}_])`, 'iu').test(text)

/** I-13: a "dm" only in a 1:1 DM (a D conversation), a "mention" only when the text names the owner, an "asks" anywhere. */
export function keeps(m: Message, ownerId: string | null, names: readonly string[]): boolean {
  if (m.why === 'dm') return m.channelId.startsWith('D')
  if (m.why === 'mention') return (ownerId !== null && m.text.includes(`<@${ownerId}>`)) || names.some(name => hasName(m.text, name))
  return m.why === 'asks'
}
