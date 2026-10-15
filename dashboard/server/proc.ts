import { execFile } from 'node:child_process'

export type Run = { code: number; stdout: string; stderr: string }

/** Run a command with an argv array (no shell). code is -1 when it could not start or timed out. */
export function run(cmd: string, args: readonly string[], timeoutMs = 15_000): Promise<Run> {
  return new Promise(resolve => {
    execFile(cmd, [...args], { timeout: timeoutMs, maxBuffer: 8 * 1024 * 1024 }, (err, stdout, stderr) => {
      const code = err ? (typeof (err as { code?: unknown }).code === 'number' ? ((err as { code: number }).code) : -1) : 0
      resolve({ code, stdout: String(stdout), stderr: String(stderr) })
    })
  })
}

export const lastLine = (text: string): string => text.trim().split('\n').pop()?.trim() ?? ''
