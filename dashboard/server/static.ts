import fs from 'node:fs'
import type { IncomingMessage, ServerResponse } from 'node:http'
import path from 'node:path'

const TYPES: Readonly<Record<string, string>> = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.map': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
  '.ico': 'image/x-icon',
  '.woff': 'font/woff',
  '.woff2': 'font/woff',
  '.txt': 'text/plain; charset=utf-8',
  '.md': 'text/plain; charset=utf-8',
  '.log': 'text/plain; charset=utf-8',
  '.webm': 'video/webm',
  '.mp4': 'video/mp4',
  '.m4v': 'video/mp4',
  '.mov': 'video/quicktime',
}

export const typeOf = (file: string): string => TYPES[path.extname(file).toLowerCase()] ?? 'application/octet-stream'

export const BUILD_FIRST = [
  '<!doctype html>',
  '<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">',
  '<title>STAR dashboard</title>',
  '<style>body{font:16px/1.5 system-ui,sans-serif;margin:3rem auto;max-width:36rem;padding:0 1rem;color:#1f2328;background:#fff}',
  '@media (prefers-color-scheme: dark){body{color:#e6edf3;background:#0d1117}}code{font-size:.95em}</style>',
  '</head><body><h1>Build the web app first</h1>',
  '<p>The STAR dashboard server is running, but <code>dashboard/web/dist</code> is not there yet.',
  'Run <code>/juel:star dashboard</code> again once the web app is in this checkout: it builds it, then opens this page.</p>',
  '</body></html>',
].join('\n')

function sendFile(res: ServerResponse, file: string, head: boolean): void {
  const size = fs.statSync(file).size
  res.writeHead(200, { 'content-type': typeOf(file), 'content-length': size, 'cache-control': 'no-cache' })
  if (head) {
    res.end()
    return
  }
  fs.createReadStream(file).on('error', () => res.destroy()).pipe(res)
}

/**
 * dashboard/web/dist: a file by its path; index.html for every other path, so the web app's deep
 * links and reloads work; the build-first page while dist/index.html is missing.
 * Every file it serves, index.html included, has its real path, symbolic links resolved, inside dist; an index.html that is missing or links out of dist answers the build-first page.
 */
/** The real path of p when it is a regular file inside the real folder root; undefined otherwise (missing, a folder, or a link out). */
function inside(root: string, p: string): string | undefined {
  try {
    const real = fs.realpathSync(p)
    return real.startsWith(root + path.sep) && fs.statSync(real).isFile() ? real : undefined
  } catch {
    return undefined
  }
}

export function serveStatic(req: IncomingMessage, res: ServerResponse, dist: string): void {
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.writeHead(405, { allow: 'GET, HEAD' })
    res.end()
    return
  }
  const head = req.method === 'HEAD'
  const buildFirst = () => {
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' })
    res.end(head ? undefined : BUILD_FIRST)
  }
  let root: string
  try { root = fs.realpathSync(dist) } catch { buildFirst(); return }
  const index = inside(root, path.join(root, 'index.html'))
  if (!index) { buildFirst(); return }
  let pathname: string
  try { pathname = decodeURIComponent(new URL(req.url ?? '/', 'http://127.0.0.1').pathname) } catch { pathname = '/' }
  const requested = inside(root, path.resolve(root, `.${pathname}`))
  sendFile(res, requested ?? index, head)
}
