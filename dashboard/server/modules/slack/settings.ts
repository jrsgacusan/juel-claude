// The module's settings: config.json beside this file (the run's pinned tools and defaults) and the
// `slack` keys of <JUEL_DIR>/dashboard.json (I-12), read from disk at every call so an edit applies
// without a restart. A missing or damaged file, or a key of the wrong type, reads as its default.
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

import { isObject, juelDir } from './state.ts'

const HERE = dirname(fileURLToPath(import.meta.url))

export type Config = { plugin: string; model: string; timeoutMin: number; allowedTools: string[]; disallowedTools: string[] }
export const loadConfig = (): Config => JSON.parse(readFileSync(join(HERE, 'config.json'), 'utf8')) as Config

export type SlackSettings = {
  everyMin: number
  plugin: string | null
  linearPlugin: string | null
  names: string[]
  drafter: { model: string; timeoutMin: number }
}

const text = (v: unknown): string | null => (typeof v === 'string' && v.trim() !== '' ? v.trim() : null)

/** The `slack` keys of <JUEL_DIR>/dashboard.json with every default (I-12). */
export function readSlackSettings(): SlackSettings {
  let slack: Record<string, unknown> = {}
  try {
    const data = JSON.parse(readFileSync(join(juelDir(), 'dashboard.json'), 'utf8')) as unknown
    if (isObject(data) && isObject(data.slack)) slack = data.slack
  } catch {
    // every default
  }
  const names: string[] = []
  if (Array.isArray(slack.names)) {
    for (const v of slack.names) {
      const name = text(v)
      if (name !== null && !names.some(n => n.toLowerCase() === name.toLowerCase())) names.push(name)
    }
  }
  const drafter = isObject(slack.drafter) ? slack.drafter : {}
  const every = slack.everyMin
  const timeout = drafter.timeoutMin
  return {
    everyMin: typeof every === 'number' && Number.isFinite(every) && every >= 0 ? every : 5,
    plugin: text(slack.plugin),
    linearPlugin: text(slack.linearPlugin),
    names,
    drafter: {
      model: text(drafter.model) ?? 'opus',
      timeoutMin: typeof timeout === 'number' && Number.isFinite(timeout) && timeout > 0 ? timeout : 10,
    },
  }
}
