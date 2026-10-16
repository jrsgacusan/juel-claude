import os from 'node:os'
import path from 'node:path'

/** The plugin checkout this server ships in: two folders above dashboard/server/. */
export const REPO_ROOT = path.resolve(import.meta.dirname, '..', '..')
/** STAR's one writer of open-loops.md (besides the owner's own hand). */
export const LOOPS_SH = path.join(REPO_ROOT, 'skills', 'star', 'loops.sh')
export const WEB_DIST = path.join(REPO_ROOT, 'dashboard', 'web', 'dist')
export const MODULES_DIR = path.join(REPO_ROOT, 'dashboard', 'server', 'modules')

/** JUEL_DIR when it is set and not empty (master plan I-1), else ~/.juel from $HOME, so a test points it at a temporary folder. */
export const juelDir = (): string => {
  const set = process.env.JUEL_DIR
  return set ? path.resolve(set) : path.join(os.homedir(), '.juel')
}
