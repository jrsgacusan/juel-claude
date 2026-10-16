// The Slack module (STAR dashboard, part 4): watches the connected Slack workspace, read-only, for
// messages that wait on the owner's reply, and hands each to the STAR project it names. The server
// imports dashboard/server/modules/*/index.ts and calls register(api).
import type { ModuleApi } from './types.ts'
import { createSlack } from './watcher.ts'

export function register(api: ModuleApi): void {
  createSlack(api).start()
}
