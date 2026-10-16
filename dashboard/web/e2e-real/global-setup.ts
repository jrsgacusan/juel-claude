import { execFileSync } from "node:child_process"
import {
  chmodSync,
  cpSync,
  mkdirSync,
  mkdtempSync,
  realpathSync,
  rmSync,
  writeFileSync,
} from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { setTimeout as sleep } from "node:timers/promises"
import {
  dashboardLog,
  logProblems,
  paths,
  readConfig,
  REPO_ROOT,
  runLauncher,
  stopServer,
  type DashboardConfig,
} from "./stack.js"

const keepTemp = (): boolean => process.env.STAR_E2E_KEEP === "1"

function removeRoot(root: string): void {
  if (!keepTemp()) rmSync(root, { recursive: true, force: true })
}

async function stopLateServer(home: string): Promise<void> {
  for (let i = 0; i < 100; i += 1) {
    const config = readConfig(home)
    if (typeof config?.pid === "number") {
      await stopServer(config.pid)
      return
    }
    await sleep(250)
  }
}

function launchFailure(
  root: string,
  reason: string,
  stdout: string,
  stderr: string,
  logTail: string,
): Error {
  removeRoot(root)
  return new Error(
    [
      `dashboard launcher failed: ${reason}`,
      `stdout:\n${stdout}`,
      `stderr:\n${stderr}`,
      `dashboard.log tail:\n${logTail}`,
      keepTemp()
        ? `temp folder ${root} (kept)`
        : `temp folder ${root} (removed; STAR_E2E_KEEP=1 keeps it)`,
    ].join("\n"),
  )
}

export default async function globalSetup(): Promise<() => Promise<void>> {
  // realpath: the macOS tmpdir is a symlink, and the server reports real paths.
  const root = realpathSync(mkdtempSync(join(tmpdir(), "star-e2e-")))
  let launcherRan = false

  try {
    const stack = paths(root)
    mkdirSync(join(stack.home, ".juel"), { recursive: true })
    mkdirSync(stack.fakes)
    mkdirSync(stack.bin)
    mkdirSync(stack.repo)
    cpSync(join(import.meta.dirname, "fixture", "star"), stack.star, {
      recursive: true,
    })

    execFileSync("git", ["init", "-q"], { cwd: stack.repo })
    writeFileSync(join(stack.repo, "README.md"), "# sample\n")
    execFileSync("git", ["add", "README.md"], { cwd: stack.repo })
    execFileSync(
      "git",
      [
        "-c",
        "user.name=e2e",
        "-c",
        "user.email=e2e@example.com",
        "commit",
        "-qm",
        "init",
      ],
      { cwd: stack.repo },
    )
    writeFileSync(
      join(stack.fakes, "terminals.json"),
      '{"result":{"terminals":[{"handle":"term_e2e_star"}]}}\n',
    )

    const copyFake = (source: string, name: string): void => {
      const target = join(stack.bin, name)
      cpSync(source, target)
      chmodSync(target, 0o755)
    }
    copyFake(join(REPO_ROOT, "dashboard", "server", "test", "fake-orca.sh"), "orca")
    for (const name of ["claude", "gh", "open"]) {
      copyFake(join(import.meta.dirname, "bin", name), name)
    }
    writeFileSync(
      join(stack.home, ".juel", "star-homes.json"),
      `${JSON.stringify([{ name: "sample", repo: stack.repo, home: stack.star }])}\n`,
    )

    launcherRan = true
    const result = runLauncher(root, 600_000)
    const stdout = result.stdout ?? ""
    const stderr = result.stderr ?? ""
    writeFileSync(join(root, "launch-1.out"), stdout)
    const match = /^STAR dashboard: (http:\/\/127\.0\.0\.1:\d+\/\?t=([0-9a-f]{32}))$/m.exec(
      stdout,
    )
    let reason: string | undefined
    if (result.error) reason = result.error.message
    else if (result.signal) reason = `killed by ${result.signal}`
    else if (result.status !== 0) reason = `exit ${result.status}`
    else if (!match) reason = "no STAR dashboard line"
    else if (stdout.includes("serving the web app built before")) {
      reason =
        "dashboard.sh served the previous build of dashboard/web: too little free memory to rebuild it, so the suite would test old code"
    } else {
      const printed = new URL(match[1])
      const config = readConfig(stack.home)
      if (
        !config ||
        String(config.port) !== printed.port ||
        config.token !== printed.searchParams.get("t")
      ) {
        reason = "dashboard.json does not match the printed URL"
      }
    }
    if (reason || !match) {
      const tail = dashboardLog(stack.home).split("\n").slice(-20).join("\n")
      await stopLateServer(stack.home)
      throw launchFailure(root, reason ?? "no STAR dashboard line", stdout, stderr, tail)
    }

    const url = match[1]
    const config = readConfig(stack.home) as DashboardConfig
    process.env.STAR_E2E_ROOT = root
    process.env.STAR_E2E_URL = url

    return async () => {
      const problems: string[] = []
      const result = await stopServer(config.pid)
      if (result === "gone") {
        problems.push(`the dashboard server (pid ${config.pid}) exited during the run`)
      } else if (result === "killed") {
        problems.push(
          `the dashboard server (pid ${config.pid}) did not stop on SIGTERM within 5 s`,
        )
      }
      const now = readConfig(stack.home)?.pid
      if (typeof now === "number" && now !== config.pid) {
        problems.push(
          `dashboard.json names pid ${now}, not the pid ${config.pid} the first launch started`,
        )
        await stopServer(now)
      }
      for (const line of logProblems(stack.home)) {
        problems.push(`dashboard.log: ${line}`)
      }
      if (keepTemp()) console.log(`STAR_E2E_KEEP=1 kept ${root}`)
      else rmSync(root, { recursive: true, force: true })
      if (problems.length > 0) throw new Error(problems.join("\n"))
    }
  } catch (error) {
    if (!launcherRan) {
      removeRoot(root)
    }
    throw error
  }
}
