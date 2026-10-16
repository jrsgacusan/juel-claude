// D2: which project a message names. Each project's signals come from its STAR folder (ledger.md
// through hooks/star.ts, the briefs' item.ref and branch lines), its repository's origin remote, and
// its project and repo folder names; rule 5, a learned channel, comes from routes.json. The rules
// run in order and the first that matches any project decides: one project is routed, two or more
// are a tie, and a tie is never guessed.
import { execFile } from 'node:child_process'
import { readdir, readFile } from 'node:fs/promises'
import { basename, join } from 'node:path'

import { parseLedger } from '../../../../hooks/star.ts'
import type { Message, Routes } from './state.ts'
import type { Project } from './types.ts'

export type Signals = { project: string; refs: string[]; prs: number[]; slug: string | null; branches: string[]; names: string[] }
export type Decision = { project: string } | { project: null; why: 'none' | 'tie' }

const readText = (file: string): Promise<string> => readFile(file, 'utf8').catch(() => '')
const unquote = (value: string): string =>
  value
    .trim()
    .replace(/^(['"])(.*)\1$/, '$2')
    .trim()
const isValue = (value: string): boolean => value !== '' && value !== 'null' && value !== '~' && value !== '-'

/** The unquoted value `re` captures from the line, or null when it does not match or is empty. */
const valueIn = (re: RegExp, line: string): string | null => {
  const value = unquote(re.exec(line)?.[1] ?? '')
  return isValue(value) ? value : null
}

/** A brief's item.ref and branch, read from its front matter only. */
export function briefSignals(text: string): { ref: string | null; branch: string | null } {
  const lines = text.split('\n')
  if ((lines[0] ?? '').trim() !== '---') return { ref: null, branch: null }
  let ref: string | null = null
  let branch: string | null = null
  let inItem = false
  for (const line of lines.slice(1)) {
    if (line.trim() === '---') break
    if (/^\S/.test(line)) {
      inItem = /^item:\s*$/.test(line)
      branch = valueIn(/^branch:(.*)$/, line) ?? branch
    } else if (inItem) {
      ref = valueIn(/^\s+ref:(.*)$/, line) ?? ref
    }
  }
  return { ref, branch }
}

/** owner/repo, lowercased, of a GitHub remote URL; null for any other. */
export function slugOf(url: string): string | null {
  const m = /github\.com[:/]+([^/\s]+)\/([^/\s]+?)(?:\.git)?\/?$/i.exec(url.trim())
  return m ? `${m[1]}/${m[2]}`.toLowerCase() : null
}

function originOf(repo: string): Promise<string | null> {
  return new Promise(resolve => {
    execFile('git', ['-C', repo, 'remote', 'get-url', 'origin'], { timeout: 5000 }, (err, stdout) => {
      resolve(err ? null : slugOf(String(stdout)))
    })
  })
}

/** What can name this project; a file that is missing or unreadable gives no signal. */
export async function signalsOf(project: Project): Promise<Signals> {
  const refs: string[] = []
  const prs: number[] = []
  const branches: string[] = []
  const ledger = parseLedger(await readText(join(project.home, 'ledger.md')))
  if (ledger.ok) {
    for (const row of ledger.value) {
      if (isValue(row.item)) refs.push(row.item)
      const pr = /\/pull\/(\d+)/.exec(row.pr)
      if (pr) prs.push(Number(pr[1]))
    }
  }
  const dir = join(project.home, 'briefs', project.name)
  const files = (await readdir(dir).catch((): string[] => [])).filter(name => name.endsWith('.md')).sort()
  for (const file of files) {
    const { ref, branch } = briefSignals(await readText(join(dir, file)))
    if (ref) refs.push(ref)
    if (branch) branches.push(branch)
  }
  return {
    project: project.name,
    refs,
    prs,
    slug: await originOf(project.repo),
    branches,
    names: [...new Set([project.name, basename(project.repo)].filter(Boolean))],
  }
}

const escape = (text: string): string => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')

/** S9: a ref or a name, not inside a longer word of letters, digits, _ or -. */
export const hasWord = (text: string, word: string): boolean =>
  word !== '' && new RegExp(`(?<![A-Za-z0-9_-])${escape(word)}(?![A-Za-z0-9_-])`, 'i').test(text)

/** S9: a branch name, not inside a longer path; a sentence's closing dot is fine. */
export const hasBranch = (text: string, branch: string): boolean =>
  branch !== '' && new RegExp(`(?<![A-Za-z0-9_./-])${escape(branch)}(?![A-Za-z0-9_/-])(?!\\.[A-Za-z0-9_])`, 'i').test(text)

const PR_URL = /https?:\/\/github\.com\/([A-Za-z0-9_.-]+)\/([A-Za-z0-9_.-]+)\/pull\/(\d+)/gi
const PR_REF = /(?:(?<![A-Za-z0-9_&])#|\bPR\s*#?)(\d+)(?!\d)/gi

function namesPr(text: string, s: Signals): boolean {
  for (const m of text.matchAll(PR_URL)) {
    const slug = `${m[1]}/${(m[2] ?? '').replace(/\.git$/i, '')}`.toLowerCase()
    if (s.slug !== null && slug === s.slug) return true
  }
  for (const m of text.replace(PR_URL, ' ').matchAll(PR_REF)) {
    if (s.prs.includes(Number(m[1]))) return true
  }
  return false
}

export function routeMessage(message: Message, signals: Signals[], routes: Routes): Decision {
  const text = [message.text, ...message.thread].join('\n')
  const rules: ((s: Signals) => boolean)[] = [
    s => s.refs.some(ref => hasWord(text, ref)),
    s => namesPr(text, s),
    s => s.branches.some(branch => hasBranch(text, branch)),
    s => s.names.some(name => hasWord(text, name)),
  ]
  for (const rule of rules) {
    const hit = [...new Set(signals.filter(rule).map(s => s.project))]
    if (hit.length === 1) return { project: hit[0] as string }
    if (hit.length > 1) return { project: null, why: 'tie' }
  }
  const learned = Object.hasOwn(routes, message.channelId) ? routes[message.channelId] : undefined
  if (learned !== undefined && signals.some(s => s.project === learned)) return { project: learned }
  return { project: null, why: 'none' }
}
