// Runs the claude CLI the way the watcher needs it: an argv array and no shell (no text is ever read
// by a shell), the prompt on stdin, a time limit after which the process is stopped, and a cap on
// what it may print. It never rejects: every way a run can go wrong comes back in the result.
import { spawn } from 'node:child_process'
import type { ChildProcessWithoutNullStreams } from 'node:child_process'

export type CliOptions = { bin: string; args: string[]; cwd: string; input: string; timeoutMs: number; maxStdout?: number }
export type CliResult = {
  code: number | null
  signal: string | null
  stdout: string
  stderr: string
  /** Why the process could not start (ENOENT when the binary is not on PATH), else null. */
  spawnError: string | null
  timedOut: boolean
  /** stdout went past maxStdout: the run was stopped and its stdout dropped. */
  tooLarge: boolean
}

const STDOUT_MAX = 4 * 1024 * 1024
const STDERR_MAX = 16 * 1024
const KILL_AFTER_MS = 5000

export const errorText = (err: unknown): string => (err instanceof Error ? err.message : String(err))

export function runCli(opts: CliOptions): Promise<CliResult> {
  return new Promise(resolve => {
    let child: ChildProcessWithoutNullStreams
    try {
      child = spawn(opts.bin, opts.args, { cwd: opts.cwd, stdio: ['pipe', 'pipe', 'pipe'] })
    } catch (err) {
      // spawn throws at once for an argument it refuses: a run that could not start, never a throw.
      resolve({ code: null, signal: null, stdout: '', stderr: '', spawnError: errorText(err), timedOut: false, tooLarge: false })
      return
    }
    const max = opts.maxStdout ?? STDOUT_MAX
    let stdout = ''
    let stderr = ''
    let spawnError: string | null = null
    let timedOut = false
    let tooLarge = false
    let settled = false
    let killer: ReturnType<typeof setTimeout> | undefined
    const stop = (): void => {
      child.kill('SIGTERM')
      killer ??= setTimeout(() => child.kill('SIGKILL'), KILL_AFTER_MS)
    }
    const limit = setTimeout(() => {
      timedOut = true
      stop()
    }, opts.timeoutMs)

    child.stdout.setEncoding('utf8')
    child.stdout.on('data', (chunk: string) => {
      if (tooLarge) return
      stdout += chunk
      if (stdout.length > max) {
        tooLarge = true
        stdout = ''
        stop()
      }
    })
    child.stderr.setEncoding('utf8')
    child.stderr.on('data', (chunk: string) => {
      stderr = (stderr + chunk).slice(-STDERR_MAX)
    })
    // A process that exits before reading all of stdin breaks the pipe; its exit code says why.
    child.stdin.on('error', () => {})
    child.stdin.end(opts.input)

    const finish = (code: number | null, signal: string | null): void => {
      if (settled) return
      settled = true
      clearTimeout(limit)
      if (killer) clearTimeout(killer)
      resolve({ code, signal, stdout, stderr, spawnError, timedOut, tooLarge })
    }
    child.on('error', err => {
      spawnError = err.message
      // A process that never started has no pid: finish now. Node emits close after it too.
      if (child.pid === undefined) finish(null, null)
    })
    child.on('close', (code, signal) => finish(code, signal))
  })
}
