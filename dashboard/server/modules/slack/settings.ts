// The module's settings: config.json beside this file (the run's pinned tools and defaults) and the
// `slack` keys of <JUEL_DIR>/dashboard.json (I-12), read from disk at every call so an edit applies
// without a restart. A missing or damaged file, or a key of the wrong type, reads as its default.
import { readFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

import { isObject, juelDir } from './state.ts'

const HERE = dirname(fileURLToPath(import.meta.url))

export type Config = { plugin: string; linearPlugin: string; model: string; timeoutMin: number; allowedTools: string[]; disallowedTools: string[]; drafter: { allowedTools: string[]; linearTools: string[]; disallowedTools: string[] } }
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

/**
 * The first id, in file order, of `plugins` in <CLAUDE_CONFIG_DIR, else ~/.claude>/plugins/installed_plugins.json
 * whose part before `@` is `name` and that has an install. Null when there is none (#146).
 */
export function installedPlugin(name: string): string | null {
  try {
    const dir = process.env.CLAUDE_CONFIG_DIR || join(homedir(), '.claude')
    const data = JSON.parse(readFileSync(join(dir, 'plugins', 'installed_plugins.json'), 'utf8')) as unknown
    const plugins = isObject(data) ? data.plugins : undefined
    if (!isObject(plugins)) return null
    for (const [id, installs] of Object.entries(plugins)) {
      if (id.split('@')[0] === name && Array.isArray(installs) && installs.length > 0) return id
    }
  } catch {
    // no readable file: no installed plugin
  }
  return null
}

export type PluginIds = { slack: string; linear: string }

/** dashboard.json first, then the installed plugin, then config.json (I-12, spec 3.11). */
export function pluginIds(config: Pick<Config, 'plugin' | 'linearPlugin'>, settings: Pick<SlackSettings, 'plugin' | 'linearPlugin'>): PluginIds {
  return {
    slack: settings.plugin ?? installedPlugin('slack') ?? config.plugin,
    linear: settings.linearPlugin ?? installedPlugin('linear') ?? config.linearPlugin,
  }
}
