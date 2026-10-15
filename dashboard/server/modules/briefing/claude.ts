// Runs a CLI (claude, gh) the way the briefing module needs it: an argv array and no shell, so no
// text is ever read by a shell, and stdin is /dev/null unless input is given (claude -p waits on an
// open stdin). Every stdout line goes to onLine, and each that parses as a JSON object to onEvent.
import { spawn } from 'node:child_process'

export type CliEvent = Record<string, unknown>
export type CliExit = {
  code: number | null
  signal: string | null
  stderr: string
  /** Why the process could not start (ENOENT when the binary is not on PATH), else null. */
  spawnError: string | null
  /** The first error an onLine or onEvent handler threw, else null. */
  handlerError: string | null
}
export type CliOptions = {
  bin: string
  args: string[]
  cwd: string
  input?: string
  onLine?: (line: string) => void
  onEvent?: (event: CliEvent) => void
}
export type CliRun = { kill: () => void; done: Promise<CliExit> }

const STDERR_MAX = 64 * 1024

export function runCli(opts: CliOptions): CliRun {
  const child = spawn(opts.bin, opts.args, {
    cwd: opts.cwd,
    stdio: [opts.input === undefined ? 'ignore' : 'pipe', 'pipe', 'pipe'],
  })
  let stdout = ''
  let stderr = ''
  let spawnError: string | null = null
  let handlerError: string | null = null

  const feed = (line: string): void => {
    try {
      opts.onLine?.(line)
      const trimmed = line.trim()
      if (!trimmed.startsWith('{')) return
      let value: unknown
      try {
        value = JSON.parse(trimmed)
      } catch {
        return
      }
      if (typeof value === 'object' && value !== null && !Array.isArray(value)) opts.onEvent?.(value as CliEvent)
    } catch (err) {
      handlerError ??= err instanceof Error ? err.message : String(err)
    }
  }

  child.stdout?.setEncoding('utf8')
  child.stdout?.on('data', (chunk: string) => {
    stdout += chunk
    let newline = stdout.indexOf('\n')
    while (newline !== -1) {
      feed(stdout.slice(0, newline))
      stdout = stdout.slice(newline + 1)
      newline = stdout.indexOf('\n')
    }
  })
  child.stderr?.setEncoding('utf8')
  child.stderr?.on('data', (chunk: string) => {
    stderr = (stderr + chunk).slice(-STDERR_MAX)
  })
  if (opts.input !== undefined && child.stdin) {
    // A process that exits before reading all of stdin breaks the pipe; its exit code says why.
    child.stdin.on('error', () => {})
    child.stdin.end(opts.input)
  }

  const done = new Promise<CliExit>(resolve => {
    let settled = false
    const finish = (code: number | null, signal: string | null): void => {
      if (settled) return
      settled = true
      if (stdout) feed(stdout)
      stdout = ''
      resolve({ code, signal, stderr, spawnError, handlerError })
    }
    child.on('error', err => {
      spawnError = err.message
      // A process that never started emits no close.
      if (child.pid === undefined) finish(null, null)
    })
    child.on('close', (code, signal) => finish(code, signal))
  })
  return {
    kill: () => {
      child.kill('SIGTERM')
    },
    done,
  }
}
