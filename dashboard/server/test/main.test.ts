import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import type { ChildProcess } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { setTimeout as sleep } from "node:timers/promises";
import { isFree } from "../config.ts";

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
  return {
    tmp,
    home,
    env: {
      ...process.env,
      HOME: home,
      PATH: `${bin}:${process.env["PATH"] ?? ""}`,
      FAKE_ORCA_DIR: tmp,
    },
  };
}

async function config(
  home: string,
  pid: number | undefined,
  ms = 10_000,
): Promise<{ port: number; token: string; pid: number }> {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    try {
      const c = JSON.parse(
        fs.readFileSync(path.join(home, ".juel", "dashboard.json"), "utf8"),
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
    const c = await config(home, first.pid);
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
    assert.equal((await config(home, first.pid)).pid, first.pid);
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
    const c = await config(home, child.pid);
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
    assert.equal((await config(home, survivor.pid)).pid, survivor.pid);
  } finally {
    await stop(a);
    await stop(b);
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});
