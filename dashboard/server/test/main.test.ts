import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import type { ChildProcess } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { setTimeout as sleep } from "node:timers/promises";
import net from "node:net";
import { PORT_BUSY_EXIT, PortBusy, isFree, pickPort } from "../config.ts";
import { juelDir } from "../paths.ts";

const MAIN = path.join(import.meta.dirname, "..", "main.ts");

function sandbox(): { tmp: string; home: string; env: NodeJS.ProcessEnv } {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "star-main-"));
  const home = path.join(tmp, "home");
  const bin = path.join(tmp, "bin");
  fs.mkdirSync(home);
  fs.mkdirSync(bin);
  fs.copyFileSync(
    path.join(import.meta.dirname, "fake-orca.sh"),
    path.join(bin, "orca"),
  );
  fs.chmodSync(path.join(bin, "orca"), 0o755);
  // a feature module that wakes a model must never reach a real one from a test
  fs.writeFileSync(path.join(bin, "claude"), "#!/bin/sh\nexit 1\n");
  fs.chmodSync(path.join(bin, "claude"), 0o755);
  // the accounts module (lane F, Task 7) must never read the owner's real cswap
  fs.writeFileSync(path.join(bin, "cswap"), "#!/bin/sh\nexit 127\n");
  fs.chmodSync(path.join(bin, "cswap"), 0o755);
  const env: NodeJS.ProcessEnv = {
    ...process.env,
    HOME: home,
    PATH: `${bin}:${process.env["PATH"] ?? ""}`,
    FAKE_ORCA_DIR: tmp,
  };
  // a test never follows an inherited JUEL_DIR into someone's real dashboard folder
  delete env["JUEL_DIR"];
  return { tmp, home, env };
}

async function config(
  juel: string,
  pid: number | undefined,
  ms = 10_000,
): Promise<{ port: number; token: string; pid: number }> {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    try {
      const c = JSON.parse(
        fs.readFileSync(path.join(juel, "dashboard.json"), "utf8"),
      ) as { port: number; token: string; pid: number };
      if (c.pid === pid) return c;
    } catch {
      // not written yet
    }
    await sleep(100);
  }
  throw new Error("dashboard.json never named the server");
}

const stop = async (child: ChildProcess): Promise<void> => {
  if (child.exitCode !== null) return;
  child.kill("SIGTERM");
  await new Promise((resolve) => child.once("exit", resolve));
};

test("main.ts starts one server on 127.0.0.1 with a token, and a second start starts nothing", async () => {
  const { tmp, home, env } = sandbox();
  const first = spawn(process.execPath, [MAIN], {
    env,
    stdio: ["ignore", "pipe", "pipe"],
  });
  try {
    const c = await config(path.join(home, ".juel"), first.pid);
    assert.match(c.token, /^[0-9a-f]{32}$/);
    assert.ok(c.port >= 4767 && c.port < 4867, String(c.port));
    assert.equal(
      (
        fs.statSync(path.join(home, ".juel", "dashboard.json")).mode & 0o777
      ).toString(8),
      "600",
    );
    assert.equal(
      (await fetch(`http://127.0.0.1:${c.port}/api/projects`)).status,
      401,
    );
    const ok = await fetch(`http://127.0.0.1:${c.port}/api/projects`, {
      headers: { "x-star-token": c.token },
    });
    assert.deepEqual(await ok.json(), []);
    assert.equal((await fetch(`http://127.0.0.1:${c.port}/`)).status, 200);
    const second = spawnSync(process.execPath, [MAIN], {
      env,
      encoding: "utf8",
      timeout: 20_000,
    });
    assert.equal(second.status, 0, second.stderr);
    assert.match(
      second.stdout,
      new RegExp(
        `already runs \\(pid ${first.pid}\\): http://127\\.0\\.0\\.1:${c.port}/\\?t=${c.token}`,
      ),
    );
    assert.equal((await config(path.join(home, ".juel"), first.pid)).pid, first.pid);
    assert.match(
      fs.readFileSync(path.join(home, ".juel", "dashboard.log"), "utf8"),
      /started on 127\.0\.0\.1:\d+/,
    );
    assert.equal(
      fs.existsSync(path.join(home, ".juel", "dashboard.lock")),
      false,
    );
  } finally {
    await stop(first);
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test("a start after a dead one reuses its token and port", async () => {
  const { tmp, home, env } = sandbox();
  fs.mkdirSync(path.join(home, ".juel"));
  const token = "abcdefabcdefabcdefabcdefabcdef12";
  let port = 0;
  for (let candidate = 4800; candidate < 4900; candidate += 1) {
    if (await isFree(candidate)) {
      port = candidate;
      break;
    }
  }
  assert.notEqual(port, 0, "no free test port");
  fs.writeFileSync(
    path.join(home, ".juel", "dashboard.json"),
    JSON.stringify({ port, token, pid: 999_999 }),
  );
  const child = spawn(process.execPath, [MAIN], { env, stdio: "ignore" });
  try {
    const c = await config(path.join(home, ".juel"), child.pid);
    assert.equal(c.token, token);
    assert.equal(c.port, port);
  } finally {
    await stop(child);
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test("two starts at the same moment leave one server, and the other says it already runs", async () => {
  const { tmp, home, env } = sandbox();
  const a = spawn(process.execPath, [MAIN], {
    env,
    stdio: ["ignore", "pipe", "pipe"],
  });
  const b = spawn(process.execPath, [MAIN], {
    env,
    stdio: ["ignore", "pipe", "pipe"],
  });
  const out = new Map<ChildProcess, string>([
    [a, ""],
    [b, ""],
  ]);
  for (const c of [a, b])
    c.stdout?.on("data", (d) => out.set(c, (out.get(c) ?? "") + String(d)));
  try {
    const first = await Promise.race(
      [a, b].map(
        (c) =>
          new Promise<ChildProcess>((resolve) =>
            c.once("exit", () => resolve(c)),
          ),
      ),
    );
    assert.equal(first.exitCode, 0);
    assert.match(out.get(first) ?? "", /already runs/);
    const survivor = first === a ? b : a;
    assert.equal((await config(path.join(home, ".juel"), survivor.pid)).pid, survivor.pid);
  } finally {
    await stop(a);
    await stop(b);
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test("juelDir is JUEL_DIR when it is set and not empty, else ~/.juel", () => {
  const saved = { home: process.env["HOME"], juel: process.env["JUEL_DIR"] };
  try {
    process.env["HOME"] = "/Users/me";
    process.env["JUEL_DIR"] = "/tmp/star-live/juel";
    assert.equal(juelDir(), "/tmp/star-live/juel");
    process.env["JUEL_DIR"] = "rel/juel";
    assert.equal(juelDir(), path.resolve("rel/juel"));
    process.env["JUEL_DIR"] = "";
    assert.equal(juelDir(), "/Users/me/.juel");
    delete process.env["JUEL_DIR"];
    assert.equal(juelDir(), "/Users/me/.juel");
  } finally {
    for (const [k, v] of [["HOME", saved.home], ["JUEL_DIR", saved.juel]] as const) {
      if (v === undefined) delete process.env[k];
      else process.env[k] = v;
    }
  }
});

test("main.ts keeps dashboard.json and its log under JUEL_DIR when it is set", async () => {
  const { tmp, home, env } = sandbox();
  const juel = path.join(tmp, "juel-alt");
  const child = spawn(process.execPath, [MAIN], { env: { ...env, JUEL_DIR: juel }, stdio: "ignore" });
  try {
    const c = await config(juel, child.pid);
    assert.match(c.token, /^[0-9a-f]{32}$/);
    assert.match(fs.readFileSync(path.join(juel, "dashboard.log"), "utf8"), /started on 127\.0\.0\.1:\d+/);
    assert.equal(fs.existsSync(path.join(home, ".juel", "dashboard.json")), false);
  } finally {
    await stop(child);
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

const BUSY = (p: number): string =>
  `port ${p} is busy: the dashboard keeps its port so tailscale serve keeps reaching it. Stop what listens on 127.0.0.1:${p} (lsof -nP -iTCP:${p} -sTCP:LISTEN), then start it again`;

/** A listener on a free 127.0.0.1 port, standing in for whatever else took the dashboard's port. */
async function blocker(): Promise<{ port: number; close(): Promise<void> }> {
  const server = net.createServer();
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const port = (server.address() as net.AddressInfo).port;
  return { port, close: () => new Promise<void>((resolve) => server.close(() => resolve())) };
}

/** main.ts run to its exit: code, stdout, stderr. */
async function runMain(env: NodeJS.ProcessEnv): Promise<{ code: number | null; stdout: string; stderr: string }> {
  const child = spawn(process.execPath, [MAIN], { env, stdio: ["ignore", "pipe", "pipe"] });
  let stdout = "";
  let stderr = "";
  child.stdout?.on("data", (d) => (stdout += String(d)));
  child.stderr?.on("data", (d) => (stderr += String(d)));
  const code = await new Promise<number | null>((resolve) => child.once("exit", resolve));
  return { code, stdout, stderr };
}

test("pickPort keeps a recorded port and refuses a busy one; with none recorded it picks from 4767 up", async () => {
  const b = await blocker();
  await assert.rejects(pickPort(b.port), (err: unknown) => err instanceof PortBusy && err.port === b.port && err.message === BUSY(b.port));
  await b.close();
  assert.equal(await pickPort(b.port), b.port);
  assert.ok((await pickPort(undefined)) >= 4767);
  assert.ok((await pickPort("4800")) >= 4767); // not a number: no recorded port
});

test("a recorded port that is busy stops main.ts with exit 3 and says why; dashboard.json is left as it was", async () => {
  const { tmp, home, env } = sandbox();
  const b = await blocker();
  const recorded = { port: b.port, token: "abcdefabcdefabcdefabcdefabcdef12", pid: 999_999 };
  fs.mkdirSync(path.join(home, ".juel"));
  fs.writeFileSync(path.join(home, ".juel", "dashboard.json"), JSON.stringify(recorded));
  try {
    const r = await runMain(env);
    assert.equal(PORT_BUSY_EXIT, 3);
    assert.equal(r.code, PORT_BUSY_EXIT);
    assert.ok(r.stderr.split("\n").includes(`star dashboard: could not start: ${BUSY(b.port)}`), r.stderr);
    assert.deepEqual(JSON.parse(fs.readFileSync(path.join(home, ".juel", "dashboard.json"), "utf8")), recorded);
    assert.match(fs.readFileSync(path.join(home, ".juel", "dashboard.log"), "utf8"), new RegExp(`could not start: port ${b.port} is busy`));
  } finally {
    await b.close();
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test("a start keeps every other key of dashboard.json", async () => {
  const { tmp, home, env } = sandbox();
  let port = 0;
  for (let candidate = 4800; candidate < 4900; candidate += 1) {
    if (await isFree(candidate)) {
      port = candidate;
      break;
    }
  }
  assert.notEqual(port, 0, "no free test port");
  const others = { claudeConfigDir: "/Users/me/.claude-personal", slack: { everyMin: 30 } };
  fs.mkdirSync(path.join(home, ".juel"));
  fs.writeFileSync(path.join(home, ".juel", "dashboard.json"),
    JSON.stringify({ port, token: "abcdefabcdefabcdefabcdefabcdef12", pid: 999_999, ...others }));
  const child = spawn(process.execPath, [MAIN], { env, stdio: "ignore" });
  try {
    const c = await config(path.join(home, ".juel"), child.pid);
    assert.equal(c.port, port);
    const all = JSON.parse(fs.readFileSync(path.join(home, ".juel", "dashboard.json"), "utf8")) as Record<string, unknown>;
    assert.equal(all["claudeConfigDir"], others.claudeConfigDir);
    assert.deepEqual(all["slack"], others.slack);
  } finally {
    await stop(child);
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});
