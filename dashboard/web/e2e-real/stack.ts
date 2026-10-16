// The suite's layout under one temp root: home/ is the launcher's HOME, star/ the copy of
// fixture/star, fakes/ the fakes' logs and terminals.json, bin/ the fakes first on PATH, and
// repo/ the project's throwaway git repo. globalSetup hands the specs STAR_E2E_ROOT and STAR_E2E_URL.
import { spawnSync, type SpawnSyncReturns } from "node:child_process"
import { readFileSync } from "node:fs"
import { join, resolve } from "node:path"
import { setTimeout as sleep } from "node:timers/promises"

export const REPO_ROOT = resolve(import.meta.dirname, "../../..")

export type DashboardConfig = { pid: number; port: number; token: string }

export type StackPaths = {
  root: string
  home: string
  star: string
  fakes: string
  bin: string
  repo: string
}

export function paths(root: string): StackPaths {
  return {
    root,
    home: join(root, "home"),
    star: join(root, "star"),
    fakes: join(root, "fakes"),
    bin: join(root, "bin"),
    repo: join(root, "repo"),
  }
}

/**
 * The launcher's and the server's environment: process.env without JUEL_DIR (an inherited one would
 * point the suite at someone's real dashboard folder) and XDG_DATA_HOME (the menu bar reader's
 * folder). PATH is the fakes in <root>/bin, then this folder's bin/ (cswap, tailscale, crontab, ps,
 * which globalSetup does not copy), then the inherited PATH.
 */
export function launchEnv(root: string): NodeJS.ProcessEnv {
  const stack = paths(root)
  const inherited = { ...process.env }
  delete inherited.JUEL_DIR
  delete inherited.XDG_DATA_HOME
  return {
    ...inherited,
    HOME: stack.home,
    PATH: [stack.bin, join(import.meta.dirname, "bin"), process.env.PATH].filter(Boolean).join(":"),
    FAKE_ORCA_DIR: stack.fakes,
    STAR_E2E_FAKES: stack.fakes,
    JUEL_STAR_HOME: stack.star,
  }
}

export function runLauncher(
  root: string,
  timeoutMs: number
): SpawnSyncReturns<string> {
  return spawnSync("sh", [join(REPO_ROOT, "skills/star/dashboard.sh")], {
    cwd: REPO_ROOT,
    env: launchEnv(root),
    encoding: "utf8",
    timeout: timeoutMs,
  })
}

export function readConfig(home: string): DashboardConfig | null {
  try {
    return JSON.parse(
      readFileSync(join(home, ".juel", "dashboard.json"), "utf8")
    ) as DashboardConfig
  } catch (error) {
    if (
      error instanceof SyntaxError ||
      (error as NodeJS.ErrnoException).code === "ENOENT"
    ) {
      return null
    }
    throw error
  }
}

export function dashboardLog(home: string): string {
  try {
    return readFileSync(join(home, ".juel", "dashboard.log"), "utf8")
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return ""
    throw error
  }
}

export const LOG_PROBLEM =
  /skipped|ignored|failed|could not|error|uncaught|unhandled|not reached|: 5\d\d /i

export function logProblems(home: string): string[] {
  return dashboardLog(home)
    .split("\n")
    .filter((line) => LOG_PROBLEM.test(line))
}

export async function stopServer(
  pid: number
): Promise<"stopped" | "gone" | "killed"> {
  try {
    process.kill(pid, "SIGTERM")
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ESRCH") return "gone"
    throw error
  }

  for (let elapsed = 0; elapsed < 5_000; elapsed += 100) {
    await sleep(100)
    try {
      process.kill(pid, 0)
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "ESRCH") return "stopped"
      throw error
    }
  }

  try {
    process.kill(pid, "SIGKILL")
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ESRCH") throw error
  }
  return "killed"
}
