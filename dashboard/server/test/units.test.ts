import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { setTimeout as sleep } from "node:timers/promises";
import { signatures, watchHomes, whatOf } from "../events.ts";
import type { DashEvent, WatchFn } from "../events.ts";
import { loadModules } from "../modules.ts";
import { Router } from "../router.ts";

test("a changed path maps to what changed; lock and temp files map to nothing", () => {
  assert.deepEqual(whatOf("open-loops.md"), ["loops"]);
  assert.deepEqual(whatOf("ledger.md"), ["ledger"]);
  assert.deepEqual(whatOf("progress/issue-1.log"), ["progress"]);
  assert.deepEqual(whatOf("evidence/issue-4/a/b.png"), ["evidence"]);
  assert.deepEqual(whatOf("drafts"), ["drafts"]);
  assert.deepEqual(whatOf("slack/x.json"), ["slack"]);
  assert.deepEqual(whatOf("briefings/b1/draft.json"), ["briefings"]);
  assert.deepEqual(whatOf("open-loops.md.lock"), []);
  assert.deepEqual(whatOf("open-loops.md.tmp.123"), []);
  assert.deepEqual(whatOf("open-loops.md.seq"), []);
  assert.deepEqual(whatOf("star.json"), []);
  assert.deepEqual(whatOf(null), [
    "loops",
    "ledger",
    "progress",
    "evidence",
    "drafts",
    "slack",
    "briefings",
    "chat",
  ]);
});

function tempHome(): string {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "star-watch-"));
  fs.writeFileSync(path.join(home, "ledger.md"), "one\n");
  fs.writeFileSync(path.join(home, "open-loops.md"), "one\n");
  return home;
}

async function until(
  events: DashEvent[],
  want: (e: DashEvent) => boolean,
  ms = 5000,
): Promise<DashEvent> {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    const hit = events.find(want);
    if (hit) return hit;
    await sleep(50);
  }
  throw new Error(
    `no matching event in ${ms} ms; got ${JSON.stringify(events)}`,
  );
}

test("a watch that throws falls back to polling, and the poll sees a change", async () => {
  const home = tempHome();
  const lines: string[] = [];
  const events: DashEvent[] = [];
  const failing: WatchFn = () => {
    throw new Error("watch is off");
  };
  const w = watchHomes(
    () => [{ name: "p", repo: "/r", home }],
    (e) => events.push(e),
    (l) => lines.push(l),
    { watch: failing, pollMs: 100 },
  );
  try {
    await sleep(150);
    fs.writeFileSync(path.join(home, "ledger.md"), "two, longer\n");
    assert.deepEqual(await until(events, (e) => e["what"] === "ledger"), {
      type: "change",
      project: "p",
      what: "ledger",
    });
    assert.ok(
      lines.some((l) =>
        l.includes("watch p failed (watch is off): polling every 0.1s"),
      ),
      lines.join("\n"),
    );
  } finally {
    w.close();
    fs.rmSync(home, { recursive: true, force: true });
  }
});

test("a watch that errors later falls back to polling too", async () => {
  const home = tempHome();
  const events: DashEvent[] = [];
  const lines: string[] = [];
  const erroring: WatchFn = () => {
    const w = new EventEmitter() as EventEmitter & { close(): void };
    w.close = () => {};
    setTimeout(() => w.emit("error", new Error("gone")), 20);
    return w as unknown as fs.FSWatcher;
  };
  const w = watchHomes(
    () => [{ name: "p", repo: "/r", home }],
    (e) => events.push(e),
    (l) => lines.push(l),
    { watch: erroring, pollMs: 100 },
  );
  try {
    await sleep(200);
    fs.mkdirSync(path.join(home, "drafts"));
    fs.writeFileSync(path.join(home, "drafts", "d.md"), "to: pr x\nhi\n");
    await until(events, (e) => e["what"] === "drafts");
    assert.ok(
      lines.some((l) => l.includes("watch p failed (gone)")),
      lines.join("\n"),
    );
  } finally {
    w.close();
    fs.rmSync(home, { recursive: true, force: true });
  }
});

test("the real fs.watch reports a change to open-loops.md", async () => {
  const home = tempHome();
  const events: DashEvent[] = [];
  const w = watchHomes(
    () => [{ name: "p", repo: "/r", home }],
    (e) => events.push(e),
    () => {},
    { pollMs: 5000 },
  );
  try {
    await sleep(300);
    fs.writeFileSync(path.join(home, "open-loops.md"), "two\n");
    assert.deepEqual(await until(events, (e) => e["what"] === "loops"), {
      type: "change",
      project: "p",
      what: "loops",
    });
  } finally {
    w.close();
    fs.rmSync(home, { recursive: true, force: true });
  }
});

test("a burst of changes makes one event per what; a change fs.watch did not name is every what", async () => {
  let listener:
    | ((event: string, filename: string | Buffer | null) => void)
    | undefined;
  const fake: WatchFn = (_dir, _opts, l) => {
    listener = l;
    const w = new EventEmitter() as EventEmitter & { close(): void };
    w.close = () => {};
    return w as unknown as fs.FSWatcher;
  };
  const events: DashEvent[] = [];
  const w = watchHomes(
    () => [{ name: "p", repo: "/r", home: "/nowhere" }],
    (e) => events.push(e),
    () => {},
    { watch: fake, pollMs: 5000 },
  );
  try {
    for (let i = 0; i < 5; i += 1) listener?.("change", "open-loops.md");
    listener?.("rename", "open-loops.md.tmp.42");
    listener?.("change", null);
    await sleep(400);
    assert.equal(events.filter((e) => e["what"] === "loops").length, 1);
    assert.deepEqual(events.map((e) => e["what"]).sort(), [
      "briefings",
      "chat",
      "drafts",
      "evidence",
      "ledger",
      "loops",
      "progress",
      "slack",
    ]);
  } finally {
    w.close();
  }
});

test("signatures change when a file under a watched folder changes", () => {
  const home = tempHome();
  const before = signatures(home);
  fs.mkdirSync(path.join(home, "progress"));
  fs.writeFileSync(path.join(home, "progress", "a.log"), "x\n");
  const after = signatures(home);
  assert.notEqual(before["progress"], after["progress"]);
  assert.equal(before["ledger"], after["ledger"]);
  fs.rmSync(home, { recursive: true, force: true });
});

test("lane 0: a file under chat/ is a chat change, for the watch and for the poll", () => {
  assert.deepEqual(whatOf("chat/20261017T101500Z-me-a1b2.md"), ["chat"]);
  const home = tempHome();
  const before = signatures(home);
  fs.mkdirSync(path.join(home, "chat"));
  fs.writeFileSync(
    path.join(home, "chat", "20261017T101500Z-me-a1b2.md"),
    "id: 20261017T101500Z-me-a1b2\n",
  );
  const after = signatures(home);
  assert.equal(typeof after["chat"], "string");
  assert.notEqual(before["chat"], after["chat"]);
  fs.rmSync(home, { recursive: true, force: true });
});

test("modules load in name order; one that throws is skipped with its routes, and logged", async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "star-mods-"));
  const write = (name: string, body: string): void => {
    fs.mkdirSync(path.join(dir, name));
    fs.writeFileSync(path.join(dir, name, "index.ts"), body);
  };
  write(
    "bad",
    [
      "export function register(api) {",
      "  api.route('GET', '/api/bad/ping', async () => ({ json: { bad: true } }))",
      "  throw new Error('boom')",
      "}",
      "",
    ].join("\n"),
  );
  write(
    "good",
    [
      "export function register(api) {",
      "  api.route('GET', '/api/good/:name', async req => ({ json: { hello: req.params.name } }))",
      "  api.log('good is up')",
      "}",
      "",
    ].join("\n"),
  );
  write("none", "export const x = 1\n");
  fs.mkdirSync(path.join(dir, "empty"));
  const router = new Router();
  const lines: string[] = [];
  const loaded = await loadModules(
    dir,
    router,
    { emit: () => {}, projects: () => [], nudge: async () => false },
    (l) => lines.push(l),
  );
  assert.deepEqual(loaded, ["good"]);
  assert.equal(router.match("GET", "/api/bad/ping"), undefined);
  const hit = router.match("GET", "/api/good/world");
  assert.ok(hit && hit !== "method");
  assert.deepEqual(
    await hit.handler({
      params: hit.params,
      query: new URLSearchParams(),
      body: undefined,
    }),
    { json: { hello: "world" } },
  );
  assert.ok(lines.includes("module bad skipped: boom"), lines.join("\n"));
  assert.ok(
    lines.includes("module none skipped: index.ts exports no register(api)"),
    lines.join("\n"),
  );
  assert.ok(lines.includes("[good] good is up"), lines.join("\n"));
  assert.ok(lines.includes("module good loaded"), lines.join("\n"));
  fs.rmSync(dir, { recursive: true, force: true });
});

test("a module whose register never returns is skipped after the time limit, and later modules still load", async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "star-mods-"));
  fs.mkdirSync(path.join(dir, "aaa"));
  fs.writeFileSync(
    path.join(dir, "aaa", "index.ts"),
    "export function register(api) {\n  api.route('GET', '/api/aaa', async () => ({ json: 1 }))\n  return new Promise(() => {})\n}\n",
  );
  fs.mkdirSync(path.join(dir, "zzz"));
  fs.writeFileSync(
    path.join(dir, "zzz", "index.ts"),
    "export function register(api) {\n  api.route('GET', '/api/zzz', async () => ({ json: 2 }))\n}\n",
  );
  fs.mkdirSync(path.join(dir, "js-only"));
  fs.writeFileSync(
    path.join(dir, "js-only", "index.js"),
    "export function register() {}\n",
  );
  const router = new Router();
  const lines: string[] = [];
  const started = Date.now();
  const loaded = await loadModules(
    dir,
    router,
    { emit: () => {}, projects: () => [], nudge: async () => false },
    (l) => lines.push(l),
    300,
  );
  assert.ok(Date.now() - started < 3000);
  assert.deepEqual(loaded, ["zzz"]);
  assert.equal(router.match("GET", "/api/aaa"), undefined);
  assert.ok(
    lines.includes("module aaa skipped: register did not return in 0.3s"),
    lines.join("\n"),
  );
  assert.ok(
    lines.includes("module js-only skipped: no index.ts"),
    lines.join("\n"),
  );
  fs.rmSync(dir, { recursive: true, force: true });
});
