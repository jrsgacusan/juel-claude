import fs from 'node:fs'
import path from 'node:path'
import { readOptional } from './files.ts'

export type Decision = { id: string; title: string }
export type Brief = { title: string | null; approved: string | null; criteria: string[]; decisions: Decision[] }

const unquote = (v: string): string => {
  const t = v.trim()
  const bare = (t.startsWith('"') && t.endsWith('"') && t.length > 1) || (t.startsWith("'") && t.endsWith("'") && t.length > 1) ? t.slice(1, -1) : t
  return bare === 'null' || bare === '~' ? '' : bare
}

/** A brief's item.title and approved: from its frontmatter, its criteria and its `### D<n>` headings. */
export function parseBrief(text: string): Brief {
  const lines = text.split('\n')
  let title: string | null = null
  let approved: string | null = null
  let body = 0
  if ((lines[0] ?? '').trim() === '---') {
    let inItem = false
    for (let i = 1; i < lines.length; i += 1) {
      const l = lines[i] ?? ''
      if (l.trim() === '---') {
        body = i + 1
        break
      }
      if (/^item:\s*$/.test(l)) {
        inItem = true
        continue
      }
      if (/^\S/.test(l)) inItem = false
      const t = /^\s+title:\s*(.*)$/.exec(l)
      if (inItem && t) title = unquote(t[1] ?? '') || null
      const a = /^approved:\s*(.*)$/.exec(l)
      if (a) approved = unquote(a[1] ?? '') || null
    }
  }
  const criteria: string[] = []
  const decisions: Decision[] = []
  let inCriteria = false
  for (const l of lines.slice(body)) {
    if (/^## /.test(l)) inCriteria = l.trim() === '## Acceptance criteria'
    const c = /^\s*-\s*\[[ xX]\]\s*(.*)$/.exec(l)
    if (inCriteria && c) criteria.push((c[1] ?? '').trim())
    const d = /^### (D\d+)\s+(.*)$/.exec(l)
    if (d) decisions.push({ id: d[1] ?? '', title: (d[2] ?? '').trim() })
  }
  return { title, approved, criteria, decisions }
}

export const briefRel = (project: string, item: string): string => path.join('briefs', project, `${item}.md`)

/** The item's brief, or null when it has none. */
export function readBrief(home: string, project: string, item: string): Brief | null {
  const text = readOptional(home, briefRel(project, item))
  return text === undefined ? null : parseBrief(text)
}

/** Every decision heading in the project's briefs, with the item each belongs to. */
export function allDecisions(home: string, project: string): (Decision & { item: string })[] {
  let names: string[]
  try {
    names = fs.readdirSync(path.join(home, 'briefs', project)).filter(n => n.endsWith('.md')).sort()
  } catch {
    return []
  }
  const out: (Decision & { item: string })[] = []
  for (const name of names) {
    const item = name.slice(0, -3)
    const brief = readBrief(home, project, item)
    for (const d of brief?.decisions ?? []) out.push({ ...d, item })
  }
  return out
}
