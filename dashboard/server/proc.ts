import { execFile } from "node:child_process";

export type Run = { code: number; stdout: string; stderr: string };

/**
 * Run a command with an argv array (no shell). code is -1 when it could not start, timed out, was
 * killed by a signal, or printed more than 8 MB; stderr then ends with the reason.
 */
export function run(
  cmd: string,
  args: readonly string[],
  timeoutMs = 15_000,
): Promise<Run> {
  return new Promise((resolve) => {
    execFile(
      cmd,
      [...args],
      { timeout: timeoutMs, maxBuffer: 8 * 1024 * 1024 },
      (err, stdout, stderr) => {
        let code = 0;
        let reason = "";
        if (err) {
          const raw = (err as { code?: unknown }).code;
          code = typeof raw === "number" ? raw : -1;
          if (typeof raw !== "number") {
            const e = err as {
              killed?: unknown;
              signal?: unknown;
              code?: unknown;
            };
            if (e.killed) reason = `timed out after ${timeoutMs / 1000}s`;
            else if (typeof e.signal === "string")
              reason = `killed by ${e.signal}`;
            else if (e.code === "ENOENT") reason = `${cmd}: not found`;
            else if (e.code === "ERR_CHILD_PROCESS_STDIO_MAXBUFFER")
              reason = "printed more than 8 MB";
            else reason = String((err as Error).message ?? err);
          }
        }
        const outErr = `${String(stderr)}${reason ? `${String(stderr).endsWith("\n") ? "" : "\n"}${reason}\n` : ""}`;
        resolve({ code, stdout: String(stdout), stderr: outErr });
      },
    );
  });
}

export const lastLine = (text: string): string =>
  text.trim().split("\n").pop()?.trim() ?? "";
