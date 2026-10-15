import fs from 'node:fs'
import path from 'node:path'

export type Release = { title: string | null; pr: string | null; sha: string | null; mergedAt: string | null }

/** The newest release record (release-record.sh) for this item: the PR, the merge commit and when it merged. */
export function readRelease(home: string, project: string, item: string): Release {
  const none: Release = { title: null, pr: null, sha: null, mergedAt: null }
  let names: string[]
  try {
    names = fs.readdirSync(path.join(home, 'releases')).filter(n => n.endsWith('.md'))
  } catch {
    return none
  }
  let best: Release | undefined
  for (const name of names) {
    let text: string
    try {
      text = fs.readFileSync(path.join(home, 'releases', name), 'utf8')
    } catch {
      continue
    }
    const lines = text.split('\n')
    const head = /^# (.*?) · (.*?) · (.*)$/.exec(lines[0] ?? '')
    if (!head || head[1] !== project || head[2] !== item) continue
    const rec: Release = { title: (head[3] ?? '').trim() || null, pr: null, sha: null, mergedAt: null }
    for (const l of lines) {
      const pr = /^- PR: (\S+)/.exec(l)
      if (pr) rec.pr = pr[1] ?? null
      const merged = /^- Merged: (\S+) by .*?, merge commit (\S+)/.exec(l)
      if (merged) {
        rec.mergedAt = merged[1] ?? null
        rec.sha = merged[2] && merged[2] !== 'unknown' ? merged[2] : null
      }
    }
    if (!best || (rec.mergedAt ?? '') > (best.mergedAt ?? '')) best = rec
  }
  return best ?? none
}
