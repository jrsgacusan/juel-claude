import os from 'node:os'
import path from 'node:path'

/** The plugin checkout this server ships in: two folders above dashboard/server/. */
export const REPO_ROOT = path.resolve(import.meta.dirname, '..', '..')
/** STAR's one writer of open-loops.md (besides the owner's own hand). */
export const LOOPS_SH = path.join(REPO_ROOT, 'skills', 'star', 'loops.sh')
export const WEB_DIST = path.join(REPO_ROOT, 'dashboard', 'web', 'dist')
export const MODULES_DIR = path.join(REPO_ROOT, 'dashboard', 'server', 'modules')

/** ~/.juel, from $HOME, so a test points it at a temporary folder. */
export const juelDir = (): string => path.join(os.homedir(), '.juel')
