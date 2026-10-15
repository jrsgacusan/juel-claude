import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { setTimeout as sleep } from 'node:timers/promises'
import { startApp } from '../app.ts'
import type { App, AppOptions } from '../app.ts'
import { makeLog } from '../log.ts'

export const TOKEN = '0123456789abcdef0123456789abcdef'
export const FIXTURE = path.join(import.meta.dirname, 'fixtures', 'star')
const FAKE_ORCA = path.join(import.meta.dirname, 'fake-orca.sh')

export type Env = { tmp: string; juel: string; star: string; app: App; url(p: string): string; api(p: string, init?: RequestInit): Promise<Response>; setTerminals(handles: string[] | null): void; orcaCalls(): string[]; addProject(name: string, edit?: (home: string) => void): Promise<string>; close(): Promise<void> }

export async function setup(opts: Partial<AppOptions> = {}): Promise<Env> {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'star-dash-'))
  const juel = path.join(tmp, 'home', '.juel')
  fs.mkdirSync(juel, { recursive: true })
  const bin = path.join(tmp, 'bin'); fs.mkdirSync(bin); fs.copyFileSync(FAKE_ORCA, path.join(bin, 'orca')); fs.chmodSync(path.join(bin, 'orca'), 0o755)
  process.env['PATH'] = `${bin}:${process.env['PATH'] ?? ''}`; process.env['FAKE_ORCA_DIR'] = tmp
  const registry: { name: string; repo: string; home: string }[] = []
  const writeRegistry = (): void => fs.writeFileSync(path.join(juel, 'star-homes.json'), JSON.stringify(registry, null, 2))
  const copy = (name: string): string => { const home = path.join(tmp, name, 'star'); fs.cpSync(FIXTURE, home, { recursive: true }); return home }
  const setTerminals = (handles: string[] | null): void => { const file = path.join(tmp, 'terminals.json'); if (handles === null) fs.rmSync(file, { force: true }); else fs.writeFileSync(file, JSON.stringify({ result: { terminals: handles.map(handle => ({ handle })) } })) }
  setTerminals(['term_star'])
  const star = copy('app'); registry.push({ name: 'app', repo: path.join(tmp, 'app'), home: star }); writeRegistry()
  const app = await startApp({ port: 0, token: TOKEN, juelDir: juel, log: makeLog(juel), webDist: path.join(tmp, 'no-dist'), modulesDir: path.join(tmp, 'no-modules'), pollMs: 200, rescanMs: 200, ...opts })
  const url = (p: string): string => `http://127.0.0.1:${app.port}${p}`
  return {
    tmp, juel, star, app, url,
    api: (p, init = {}) => fetch(url(p), { ...init, headers: { 'x-star-token': TOKEN, 'content-type': 'application/json', ...(init.headers as Record<string, string> | undefined) } }),
    setTerminals, orcaCalls: () => { try { return fs.readFileSync(path.join(tmp, 'orca-calls.log'), 'utf8').split('\n').filter(Boolean) } catch { return [] } },
    addProject: async (name, edit) => { const home = copy(name); const starJson = JSON.parse(fs.readFileSync(path.join(home, 'star.json'), 'utf8')) as Record<string, unknown>; starJson['project'] = { name, repo: path.join(tmp, name) }; starJson['terminal'] = `term_${name}`; fs.writeFileSync(path.join(home, 'star.json'), JSON.stringify(starJson)); fs.renameSync(path.join(home, 'briefs', 'app'), path.join(home, 'briefs', name)); edit?.(home); registry.push({ name, repo: path.join(tmp, name), home }); writeRegistry(); await app.registry.refresh(); return home },
    close: async () => { await app.close(); try { for (const rel of fs.readdirSync(tmp, { recursive: true }) as string[]) { try { fs.chmodSync(path.join(tmp, rel), 0o755) } catch {} } } catch {} fs.rmSync(tmp, { recursive: true, force: true }) },
  }
}

export async function openEvents(env: Env): Promise<{ next(match: (e: Record<string, unknown>) => boolean, ms?: number): Promise<Record<string, unknown>>; close(): void }> {
  const ac = new AbortController(); const res = await fetch(env.url('/api/events'), { headers: { 'x-star-token': TOKEN }, signal: ac.signal }); assert.equal(res.status, 200); assert.match(res.headers.get('content-type') ?? '', /text\/event-stream/)
  const reader = res.body!.getReader(); const decoder = new TextDecoder(); let buf = ''; const seen: Record<string, unknown>[] = []; let pending: Promise<{ done: boolean; value?: Uint8Array }> | undefined
  return { async next(match, ms = 5000) { const end = Date.now() + ms; for (;;) { const i = seen.findIndex(match); if (i >= 0) return seen.splice(i, 1)[0] as Record<string, unknown>; const left = end - Date.now(); if (left <= 0) throw new Error(`no matching event in ${ms} ms; saw ${JSON.stringify(seen)}`); pending ??= reader.read() as Promise<{ done: boolean; value?: Uint8Array }>; const chunk = await Promise.race([pending, sleep(left).then(() => null)]); if (chunk === null) continue; pending = undefined; if (chunk.done) throw new Error('the event stream ended'); buf += decoder.decode(chunk.value, { stream: true }); for (let at = buf.indexOf('\n\n'); at >= 0; at = buf.indexOf('\n\n')) { const block = buf.slice(0, at); buf = buf.slice(at + 2); for (const line of block.split('\n')) if (line.startsWith('data: ')) seen.push(JSON.parse(line.slice(6)) as Record<string, unknown>) } } }, close: () => ac.abort() }
}
