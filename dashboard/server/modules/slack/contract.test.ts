import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import { test } from 'node:test'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const read = (name: string): Promise<string> => readFile(join(HERE, name), 'utf8')

// D1's contract, word for word.
const CONTRACT = `export type Project = { name: string; repo: string; home: string; terminal: string | null; state: 'running' | 'idle' | 'stopped' }
export type Req = { params: Record<string, string>; query: URLSearchParams; body: unknown }
export type Res = { status?: number; json?: unknown }
export type ModuleApi = {
  route(method: 'GET' | 'POST' | 'PUT', path: string, handler: (req: Req) => Promise<Res>): void
  emit(event: { type: string; project?: string; [k: string]: unknown }): void
  projects(): Project[]
  nudge(project: string): Promise<boolean>
  log(line: string): void
}
export function register(api: ModuleApi): void
`

const WRITE_WORDS = ['send', 'post', 'update', 'edit', 'delete', 'react', 'schedule', 'create']

test('types.ts is the module contract of D1, unchanged', async () => {
  const code = (await read('types.ts'))
    .split('\n')
    .filter(line => !line.startsWith('//'))
    .join('\n')
  assert.equal(code, CONTRACT)
})

test('config.json pins read-only Slack tools and denies every other tool the connector exposes', async () => {
  const config = JSON.parse(await read('config.json')) as {
    plugin: string
    model: string
    timeoutMin: number
    allowedTools: string[]
    disallowedTools: string[]
  }
  assert.equal(config.plugin, 'slack@anthropic-plugin-directory')
  assert.equal(config.model, 'haiku')
  assert.equal(config.timeoutMin, 4)
  for (const tool of config.allowedTools) {
    assert.match(tool, /^mcp__plugin_slack_slack__slack_/)
    for (const word of WRITE_WORDS) assert.ok(!tool.includes(word), `${tool} looks like a write tool (${word})`)
  }
  for (const need of ['slack_search_public_and_private', 'slack_read_channel', 'slack_read_thread', 'slack_read_user_profile']) {
    assert.ok(config.allowedTools.some(tool => tool.endsWith(`__${need}`)), `no ${need}`)
  }
  for (const write of ['slack_send_message', 'slack_send_message_draft', 'slack_schedule_message', 'slack_add_reaction', 'slack_create_canvas', 'slack_update_canvas']) {
    assert.ok(config.disallowedTools.some(tool => tool.endsWith(`__${write}`)), `${write} is not denied`)
  }
  assert.deepEqual(config.allowedTools.filter(tool => config.disallowedTools.includes(tool)), [])
  assert.equal(config.allowedTools.length + config.disallowedTools.length, 27, 'the spike listed 27 Slack tools')
})

test('prompt.md asks for exactly the messages, exclusions and fields of the item, in the window', async () => {
  const prompt = await read('prompt.md')
  for (const field of ['"channelId"', '"channel"', '"ts"', '"threadTs"', '"from"', '"text"', '"permalink"', '"thread"']) {
    assert.ok(prompt.includes(field), `no field ${field}`)
  }
  for (const phrase of [
    "a DM or a group DM whose latest message is not the owner's",
    'a mention of the owner',
    'a thread the owner is in, a new question for the owner',
    'bots',
    'thank-yous',
    'FYIs',
    'reactions',
    'up to 5 earlier messages',
    '"name: text"',
    '{"connected": false',
    '"workspace"',
    'never send',
    '{{since_ts}}',
    '{{since_iso}}',
    '{{now_ts}}',
    '{{now_iso}}',
  ]) {
    assert.ok(prompt.includes(phrase), `prompt.md does not say: ${phrase}`)
  }
})
