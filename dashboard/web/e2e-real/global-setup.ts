import { execFileSync, spawnSync } from "node:child_process"
import {
  chmodSync,
  cpSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  realpathSync,
  rmSync,
  writeFileSync,
} from "node:fs"
import { join, resolve } from "node:path"
import { tmpdir } from "node:os"

type DashboardConfig = { pid: number; port: number; token: string }

const REPO_ROOT = resolve(import.meta.dirname, "../../..")

function readConfig(home: string): DashboardConfig | null {
  try {
    return JSON.parse(
      readFileSync(join(home, ".juel", "dashboard.json"), "utf8"),
    ) as DashboardConfig
  } catch {
    return null
  }
}

function stop(pid: number | undefined): void {
  if (pid === undefined) return
  try {
    process.kill(pid, "SIGTERM")
  } catch {
    return
  }
  const end = Date.now() + 5_000
  while (Date.now() < end) {
    try {
      process.kill(pid, 0)
    } catch {
      return
    }
    Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 100)
  }
  try {
    process.kill(pid, "SIGKILL")
  } catch {
    // The process exited between the last poll and SIGKILL.
  }
}

function logTail(home: string): string {
  try {
    return readFileSync(join(home, ".juel", "dashboard.log"), "utf8")
      .trim()
      .split("\n")
      .slice(-20)
      .join("\n")
  } catch {
    return "(dashboard.log unavailable)"
  }
}

function launchError(
  root: string,
  home: string,
  status: number | null,
  stdout: string,
  stderr: string,
): Error {
  const tail = logTail(home)
  stop(readConfig(home)?.pid)
  if (process.env.STAR_E2E_KEEP !== "1") rmSync(root, { recursive: true, force: true })
  return new Error(
    [
      `dashboard launcher failed (status ${status ?? "null"})`,
      `stdout:\n${stdout}`,
      `stderr:\n${stderr}`,
      `dashboard.log tail:\n${tail}`,
    ].join("\n"),
  )
}

export default async function globalSetup(): Promise<() => Promise<void>> {
  const root = realpathSync(mkdtempSync(join(tmpdir(), "star-e2e-")))
  const home = join(root, "home")
  const star = join(root, "star")
  const fakes = join(root, "fakes")
  const bin = join(root, "bin")
  const repo = join(root, "repo")
  mkdirSync(join(home, ".juel"), { recursive: true })
  mkdirSync(fakes)
  mkdirSync(bin)
  mkdirSync(repo)

  try {
    cpSync(join(import.meta.dirname, "fixture", "star"), star, { recursive: true })
    execFileSync("git", ["init", "-q"], { cwd: repo })
    writeFileSync(join(repo, "README.md"), "# sample\n")
    execFileSync("git", ["add", "README.md"], { cwd: repo })
    execFileSync(
      "git",
      ["-c", "user.name=e2e", "-c", "user.email=e2e@example.com", "commit", "-qm", "init"],
      { cwd: repo },
    )
    writeFileSync(
      join(fakes, "terminals.json"),
      '{"result":{"terminals":[{"handle":"term_e2e_star"}]}}\n',
    )

    const copyFake = (source: string, name: string): void => {
      const target = join(bin, name)
      cpSync(source, target)
      chmodSync(target, 0o755)
    }
    copyFake(join(REPO_ROOT, "dashboard", "server", "test", "fake-orca.sh"), "orca")
    for (const name of ["claude", "gh", "open"]) {
      copyFake(join(import.meta.dirname, "bin", name), name)
    }
    writeFileSync(
      join(home, ".juel", "star-homes.json"),
      `${JSON.stringify([{ name: "sample", repo, home: star }])}\n`,
    )

    const env: NodeJS.ProcessEnv = {
      ...process.env,
      HOME: home,
      PATH: `${bin}:${process.env.PATH ?? ""}`,
      FAKE_ORCA_DIR: fakes,
      STAR_E2E_FAKES: fakes,
    }
    let result: ReturnType<typeof spawnSync>
    try {
      result = spawnSync(
        "sh",
        [join(REPO_ROOT, "skills/star/dashboard.sh")],
        { cwd: REPO_ROOT, env, encoding: "utf8", timeout: 600_000 },
      )
    } catch (error) {
      throw launchError(root, home, null, "", String(error))
    }
    const stdout = typeof result.stdout === "string" ? result.stdout : ""
    const stderr = typeof result.stderr === "string" ? result.stderr : ""
    writeFileSync(join(root, "launch-1.out"), stdout)
    const match = /^STAR dashboard: (http:\/\/127\.0\.0\.1:(\d+)\/\?t=([0-9a-f]{32}))$/m.exec(stdout)
    if (result.status !== 0 || !match) {
      throw launchError(root, home, result.status, stdout, stderr)
    }
    const [, url, portText, token] = match
    const config = readConfig(home)
    if (!config || String(config.port) !== portText || config.token !== token) {
      throw launchError(root, home, result.status, stdout, stderr)
    }
    const origin = `http://127.0.0.1:${portText}`
    process.env.STAR_E2E_ROOT = root
    process.env.STAR_E2E_URL = url
    process.env.STAR_E2E_ORIGIN = origin
    process.env.STAR_E2E_TOKEN = token

    return async () => {
      stop(config.pid)
      if (process.env.STAR_E2E_KEEP === "1") console.log(`STAR_E2E_KEEP=1 kept ${root}`)
      else rmSync(root, { recursive: true, force: true })
    }
  } catch (error) {
    if (error instanceof Error && error.message.startsWith("dashboard launcher failed")) throw error
    const config = readConfig(home)
    stop(config?.pid)
    if (process.env.STAR_E2E_KEEP !== "1") rmSync(root, { recursive: true, force: true })
    if (error instanceof Error) throw error
    throw new Error(String(error), { cause: error })
  }
}
