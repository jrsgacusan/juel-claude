import fs from 'node:fs'
import path from 'node:path'
import { Unreadable, whyOf } from '../http.ts'

/** A file in a STAR folder; anything but a read is an Unreadable naming it by its path in the folder. */
export function readText(home: string, rel: string): string {
  try {
    return fs.readFileSync(path.join(home, rel), 'utf8')
  } catch (err) {
    throw new Unreadable(rel, whyOf(err))
  }
}

/** The same, but undefined when the file is not there. */
export function readOptional(home: string, rel: string): string | undefined {
  try {
    return fs.readFileSync(path.join(home, rel), 'utf8')
  } catch (err) {
    if ((err as { code?: unknown }).code === 'ENOENT') return undefined
    throw new Unreadable(rel, whyOf(err))
  }
}

export function isDir(p: string): boolean {
  try {
    return fs.statSync(p).isDirectory()
  } catch {
    return false
  }
}

/** Every regular file under dir, as sorted paths relative to it; symbolic links are not followed. A missing dir is []. */
export function listFiles(dir: string): string[] {
  const out: string[] = []
  const walk = (rel: string): void => {
    let entries: fs.Dirent[]
    try {
      entries = fs.readdirSync(path.join(dir, rel), { withFileTypes: true })
    } catch {
      return
    }
    for (const e of entries) {
      const child = rel ? `${rel}/${e.name}` : e.name
      if (e.isDirectory()) walk(child)
      else if (e.isFile()) out.push(child)
    }
  }
  walk('')
  return out.sort()
}

/** A STAR item, draft or briefing name: letters, digits, dot, dash and underscore, not starting with a dot. */
export const isPlainName = (name: string): boolean => /^[A-Za-z0-9_-][A-Za-z0-9._-]*$/.test(name) && !name.includes('..')
