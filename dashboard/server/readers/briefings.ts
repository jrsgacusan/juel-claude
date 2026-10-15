import fs from 'node:fs'
import path from 'node:path'

/** briefings/<id>/ folders (the briefing module's), titled by their draft.json, else by the id. */
export function readBriefings(home: string): { id: string; title: string }[] {
  let ids: string[]
  try {
    ids = fs.readdirSync(path.join(home, 'briefings'), { withFileTypes: true }).filter(d => d.isDirectory()).map(d => d.name).sort()
  } catch {
    return []
  }
  return ids.map(id => {
    try {
      const draft = JSON.parse(fs.readFileSync(path.join(home, 'briefings', id, 'draft.json'), 'utf8')) as { title?: unknown }
      return { id, title: typeof draft.title === 'string' && draft.title.trim() ? draft.title.trim() : id }
    } catch {
      return { id, title: id }
    }
  })
}
