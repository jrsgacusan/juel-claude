import fs from 'node:fs'
import path from 'node:path'

export type SlackDraft = { name: string; to: string; reply: string }

/** drafts/*-slack-*.md: the first line (`to: slack <channel> <ts>`) and the reply after it. */
export function slackDrafts(home: string): SlackDraft[] {
  let names: string[]
  try {
    names = fs.readdirSync(path.join(home, 'drafts')).filter(n => /-slack-.+\.md$/.test(n)).sort()
  } catch {
    return []
  }
  const out: SlackDraft[] = []
  for (const name of names) {
    let text: string
    try {
      text = fs.readFileSync(path.join(home, 'drafts', name), 'utf8')
    } catch {
      continue
    }
    const at = text.indexOf('\n')
    out.push({ name, to: (at < 0 ? text : text.slice(0, at)).trim(), reply: at < 0 ? '' : text.slice(at + 1).trim() })
  }
  return out
}
