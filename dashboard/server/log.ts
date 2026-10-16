import fs from 'node:fs'
import path from 'node:path'

/** A logger that appends `<iso> <line>` to <dir>/dashboard.log. It never throws: a full disk must not stop the server. */
export function makeLog(dir: string): (line: string) => void {
  return line => {
    try {
      fs.mkdirSync(dir, { recursive: true })
      fs.appendFileSync(path.join(dir, 'dashboard.log'), `${new Date().toISOString()} ${line.replace(/\s*\n\s*/g, ' ')}\n`)
    } catch {
      // nothing to do: the log is for the owner's eyes only
    }
  }
}
