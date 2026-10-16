import assert from "node:assert/strict";
import fs from "node:fs";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { setTimeout as sleep } from "node:timers/promises";
import { openEvents, setup } from "./helpers.ts";
import type { AddressInfo } from "node:net";

test("listens on 127.0.0.1 only, and every /api/ request needs the token", async () => {
  const env = await setup();
  try {
    assert.equal(
      (env.app.server.address() as AddressInfo).address,
      "127.0.0.1",
    );
    for (const p of [
      "/api/projects",
      "/api/events",
      "/api/nope",
      "/api/projects/app/loops",
    ]) {
      const bare = await fetch(env.url(p));
      assert.equal(bare.status, 401, p);
      assert.deepEqual(await bare.json(), {
        error: "missing or wrong X-Star-Token",
      });
      const wrong = await fetch(env.url(p), {
        headers: { "x-star-token": "f".repeat(32) },
      });
      assert.equal(wrong.status, 401, p);
      assert.equal(
        (
          await fetch(env.url(p), {
            headers: { "x-star-token": "abc" },
          })
        ).status,
        401,
        p,
      );
    }
    const viaQuery = await fetch(
      env.url("/api/projects?t=0123456789abcdef0123456789abcdef"),
    );
    assert.equal(viaQuery.status, 401);
    assert.equal((await env.api("/api/nope")).status, 404);
    assert.equal(
      (await env.api("/api/projects", { method: "POST", body: "{}" })).status,
      405,
    );
    assert.equal((await env.api("/api/projects/ghost/loops")).status, 404);
  } finally {
    await env.close();
  }
});

test("/ serves the build-first page with no dist, and the app with one, for every non-API path", async () => {
  const env = await setup();
  try {
    const page = await fetch(env.url("/?t=abc"));
    assert.equal(page.status, 200);
    assert.match(await page.text(), /Build the web app first/);
  } finally {
    await env.close();
  }
  const box = fs.mkdtempSync(path.join(os.tmpdir(), "star-dist-"));
  const dist = path.join(box, "dist");
  fs.mkdirSync(dist);
  fs.mkdirSync(path.join(dist, "assets"));
  fs.writeFileSync(
    path.join(dist, "index.html"),
    "<!doctype html><title>STAR</title><div id=root></div>",
  );
  fs.writeFileSync(path.join(dist, "assets", "app.js"), "console.log(1)");
  const withDist = await setup({ webDist: dist });
  try {
    for (const p of [
      "/",
      "/app/needs",
      "/app/progress?item=issue-1",
      "/assets/missing.js",
    ]) {
      const r = await fetch(withDist.url(p));
      assert.equal(r.status, 200, p);
      assert.match(await r.text(), /<title>STAR<\/title>/, p);
    }
    const js = await fetch(withDist.url("/assets/app.js"));
    assert.match(js.headers.get("content-type") ?? "", /javascript/);
    assert.equal(await js.text(), "console.log(1)");
    fs.writeFileSync(path.join(box, "secret.json"), '{"token":"leak"}');
    fs.mkdirSync(path.join(box, "dist-evil"));
    fs.writeFileSync(path.join(box, "dist-evil", "x.txt"), "leak");
    for (const raw of [
      "/..%2fsecret.json",
      "/%2e%2e%2fsecret.json",
      "/..%2fdist-evil%2fx.txt",
      "/../secret.json",
    ]) {
      const body = await new Promise<string>((resolve, reject) => {
        http
          .get(
            {
              host: "127.0.0.1",
              port: withDist.app.port,
              path: raw,
            },
            (r) => {
              let text = "";
              r.on("data", (d) => (text += String(d)));
              r.on("end", () => resolve(text));
            },
          )
          .on("error", reject);
      });
      assert.doesNotMatch(body, /leak/, raw);
    }
    fs.symlinkSync(path.join(box, "secret.json"), path.join(dist, "assets", "link.js"));
    const linked = await fetch(withDist.url("/assets/link.js"));
    assert.equal(linked.status, 200);
    assert.doesNotMatch(await linked.text(), /leak/);
  } finally {
    await withDist.close();
    fs.rmSync(box, { recursive: true, force: true });
  }

  const box2 = fs.mkdtempSync(path.join(os.tmpdir(), "star-dist-"));
  const dist2 = path.join(box2, "dist");
  fs.mkdirSync(path.join(dist2, "assets"), { recursive: true });
  fs.writeFileSync(path.join(box2, "secret.json"), '{"token":"leak"}');
  fs.symlinkSync(path.join(box2, "secret.json"), path.join(dist2, "index.html"));
  const linkedIndex = await setup({ webDist: dist2 });
  try {
    for (const p of ["/", "/app/needs", "/assets/missing.js"]) {
      const r = await fetch(linkedIndex.url(p));
      assert.equal(r.status, 200, p);
      const body = await r.text();
      assert.doesNotMatch(body, /leak/, p);
      assert.match(body, /Build the web app first/, p);
    }
  } finally {
    await linkedIndex.close();
    fs.rmSync(box2, { recursive: true, force: true });
  }
});

test("GET /api/projects lists each project with its state; a broken or deleted one never breaks the list", async () => {
  const env = await setup();
  try {
    await env.addProject("quiet", (home) => {
      const q = fs
        .readFileSync(path.join(home, "open-loops.md"), "utf8")
        .replace("state: running", "state: idle");
      fs.writeFileSync(path.join(home, "open-loops.md"), q);
    });
    const gone = await env.addProject("gone");
    fs.rmSync(gone, { recursive: true, force: true });
    const locked = await env.addProject("locked");
    fs.chmodSync(path.join(locked, "open-loops.md"), 0o000);
    env.setTerminals(["term_star", "term_quiet", "term_locked"]);
    await env.app.registry.refresh();
    const list = (await (await env.api("/api/projects")).json()) as Record<
      string,
      unknown
    >[];
    assert.deepEqual(list[0], {
      name: "app",
      repo: path.join(env.tmp, "app"),
      state: "running",
      terminal: "term_star",
      lastTick: "2026-10-15T08:00:00Z",
      needsYou: 4,
    });
    assert.equal(list.find((p) => p["name"] === "quiet")?.["state"], "idle");
    assert.deepEqual(
      list.find((p) => p["name"] === "gone"),
      {
        name: "gone",
        repo: path.join(env.tmp, "gone"),
        state: "stopped",
        terminal: null,
        lastTick: null,
        needsYou: null,
      },
    );
    assert.deepEqual(
      [
        list.find((p) => p["name"] === "locked")?.["lastTick"],
        list.find((p) => p["name"] === "locked")?.["needsYou"],
      ],
      [null, null],
    );
    const goneLoops = await env.api("/api/projects/gone/loops");
    assert.equal(goneLoops.status, 502);
    assert.match(
      ((await goneLoops.json()) as { error: string }).error,
      /^open-loops\.md: not found/,
    );
    env.setTerminals([]);
    await env.app.registry.refresh();
    const stopped = (await (await env.api("/api/projects")).json()) as Record<
      string,
      unknown
    >[];
    assert.equal(stopped[0]?.["state"], "stopped");
    assert.equal(
      (await env.api("/api/projects/app/overview")).status,
      200,
      "a stopped STAR still answers from its files",
    );
  } finally {
    await env.close();
  }
});

test("GET /api/projects/:p/overview has the resume block, counts, pools and flags", async () => {
  const env = await setup();
  try {
    const o = await (await env.api("/api/projects/app/overview")).json();
    assert.deepEqual(o, {
      resume: {
        state: "running",
        pools: "brief 0/4 · build 1/3 · babysit 1/3",
        next: "issue-6 waits for a build slot",
        lastTick: "2026-10-15T08:00:00Z",
      },
      counts: {
        building: 1,
        "brief-ready": 1,
        babysitting: 1,
        done: 1,
        failed: 1,
        queued: 1,
      },
      workers: { brief: [0, 4], build: [1, 3], babysit: [1, 3] },
      gateDown: null,
      away: null,
      quietHours: { tz: "Asia/Manila", start: "22:00", end: "07:00" },
    });
    const s = JSON.parse(
      fs.readFileSync(path.join(env.star, "star.json"), "utf8"),
    ) as Record<string, unknown>;
    s["gateDown"] = {
      since: "2026-10-15T09:00:00Z",
      why: "sol at capacity",
      checked: "2026-10-15T09:30:00Z",
    };
    s["away"] = "2026-10-15T10:00:00Z";
    fs.writeFileSync(path.join(env.star, "star.json"), JSON.stringify(s));
    const o2 = (await (
      await env.api("/api/projects/app/overview")
    ).json()) as Record<string, unknown>;
    assert.deepEqual(o2["gateDown"], {
      since: "2026-10-15T09:00:00Z",
      why: "sol at capacity",
    });
    assert.equal(o2["away"], "2026-10-15T10:00:00Z");
  } finally {
    await env.close();
  }
});

test("GET /api/projects/:p/loops: blocked work first, then Slack, then the rest, oldest first, picks parsed", async () => {
  const env = await setup();
  try {
    const loops = (await (
      await env.api("/api/projects/app/loops")
    ).json()) as Record<string, unknown>[];
    assert.deepEqual(
      loops.map((l) => l["id"]),
      ["N-5", "N-6", "N-7", "N-4", "N-3"],
    );
    assert.deepEqual(loops[0], {
      id: "N-5",
      kind: "go-batch",
      item: "B-2",
      title: "go for batch B-2: 1 items",
      body: ["issue-2"],
      options: [
        { label: "go", answer: "go", recommended: true },
        { label: "go except …", answer: "go except ", recommended: false },
        { label: "drop …", answer: "drop ", recommended: false },
      ],
      suggestion: "go: the brief is small and every check is automated",
      answer: "",
      askedAt: null,
    });
    const secret = loops[1] as Record<string, unknown>;
    assert.equal(secret["suggestion"], null);
    assert.deepEqual(
      (secret["options"] as { recommended: boolean }[]).map(
        (o) => o.recommended,
      ),
      [false, false],
    );
    assert.deepEqual(secret["body"], [
      "brief: briefs/app/issue-7.md",
      "step: 1",
      "> kind: secret",
    ]);
    assert.equal(loops[2]?.["answer"], "ISO 8601");
    const slack = loops[3] as Record<string, unknown>;
    assert.equal(slack["suggestion"], "Not today. It's in final review now.");
    assert.deepEqual(slack["options"], [
      { label: "send", answer: "send", recommended: true },
      { label: "rewrite: …", answer: "rewrite: ", recommended: false },
      { label: "skip", answer: "skip", recommended: false },
    ]);
    const q = path.join(env.star, "open-loops.md");
    fs.writeFileSync(
      q,
      fs
        .readFileSync(q, "utf8")
        .replace(
          "## Waiting on others",
          [
            "### N-12 · app · issue-3 · q",
            "kind: question",
            "msg: m-3",
            "Answer:",
            "",
            "### N-10 · app · issue-6 · h",
            "kind: held",
            "Options: done",
            "Answer:",
            "",
            "## Waiting on others",
          ].join("\n"),
        ),
    );
    const ordered = (await (
      await env.api("/api/projects/app/loops")
    ).json()) as { id: string }[];
    assert.deepEqual(
      ordered.map((l) => l.id),
      ["N-5", "N-6", "N-7", "N-12", "N-4", "N-3", "N-10"],
    );
    fs.appendFileSync(path.join(env.star, "open-loops.md"), "<<<<<<< HEAD\n");
    const broken = await env.api("/api/projects/app/loops");
    assert.equal(broken.status, 502);
    assert.match(
      ((await broken.json()) as { error: string }).error,
      /open-loops\.md: unresolved git conflict markers/,
    );
  } finally {
    await env.close();
  }
});

test("the event stream sends a change for open-loops.md and ledger.md, and module events", async () => {
  const env = await setup();
  const events = await openEvents(env);
  try {
    await sleep(300);
    fs.appendFileSync(path.join(env.star, "open-loops.md"), "\n");
    assert.deepEqual(await events.next((e) => e["what"] === "loops"), {
      type: "change",
      project: "app",
      what: "loops",
    });
    fs.appendFileSync(path.join(env.star, "ledger.md"), "\n");
    assert.deepEqual(await events.next((e) => e["what"] === "ledger"), {
      type: "change",
      project: "app",
      what: "ledger",
    });
    env.app.hub.emit({
      type: "briefing",
      project: "app",
      id: "b1",
      turn: "hi",
    });
    assert.deepEqual(await events.next((e) => e["type"] === "briefing"), {
      type: "briefing",
      project: "app",
      id: "b1",
      turn: "hi",
    });
  } finally {
    events.close();
    await env.close();
  }
});

test("a client that goes away mid-stream does not break the server", async () => {
  const env = await setup();
  try {
    const first = await openEvents(env);
    first.close();
    const end = Date.now() + 2000;
    while (env.app.hub.size() !== 0 && Date.now() < end) await sleep(50);
    assert.equal(env.app.hub.size(), 0);
    env.app.hub.emit({ type: "change", project: "app", what: "loops" });
    const second = await openEvents(env);
    env.app.hub.emit({ type: "ping-test" });
    assert.deepEqual(await second.next((e) => e["type"] === "ping-test"), {
      type: "ping-test",
    });
    second.close();
    assert.equal((await env.api("/api/projects")).status, 200);
  } finally {
    await env.close();
  }
});

test("the poll fallback still sends change events when fs.watch is not available", async () => {
  const env = await setup({
    watch: () => {
      throw new Error("watch is off");
    },
  });
  const events = await openEvents(env);
  try {
    fs.appendFileSync(path.join(env.star, "ledger.md"), "\n");
    assert.deepEqual(await events.next((e) => e["what"] === "ledger"), {
      type: "change",
      project: "app",
      what: "ledger",
    });
    assert.match(
      fs.readFileSync(path.join(env.juel, "dashboard.log"), "utf8"),
      /watch app failed \(watch is off\): polling every 0\.2s/,
    );
  } finally {
    events.close();
    await env.close();
  }
});

test("a module that throws is logged and skipped while a working one serves, sees projects and emits", async () => {
  const mods = fs.mkdtempSync(
    path.join(fs.realpathSync(process.env["TMPDIR"] ?? "/tmp"), "star-mods-"),
  );
  fs.mkdirSync(path.join(mods, "bad"));
  fs.writeFileSync(
    path.join(mods, "bad", "index.ts"),
    "export function register(api) {\n  api.route('GET', '/api/bad/ping', async () => ({ json: {} }))\n  throw new Error('boom')\n}\n",
  );
  fs.mkdirSync(path.join(mods, "good"));
  fs.writeFileSync(
    path.join(mods, "good", "index.ts"),
    [
      "export function register(api) {",
      "  api.route('GET', '/api/good/projects', async () => ({ json: api.projects().map(p => [p.name, p.state]) }))",
      "  api.route('GET', '/api/good/nudge', async () => ({ json: [await api.nudge('app'), await api.nudge('ghost')] }))",
      "  api.route('POST', '/api/good/emit', async () => { api.emit({ type: 'good', project: 'app' }); return { status: 202 } })",
      "}",
      "",
    ].join("\n"),
  );
  const env = await setup({ modulesDir: mods });
  const events = await openEvents(env);
  try {
    assert.deepEqual(await (await env.api("/api/good/projects")).json(), [
      ["app", "running"],
    ]);
    assert.deepEqual(await (await env.api("/api/good/nudge")).json(), [
      true,
      false,
    ]);
    assert.ok(
      env
        .orcaCalls()
        .includes(
          "terminal send --terminal term_star --text inbox --enter --json",
        ),
    );
    assert.equal((await fetch(env.url("/api/good/projects"))).status, 401);
    assert.equal((await env.api("/api/bad/ping")).status, 404);
    assert.equal(
      (await env.api("/api/good/emit", { method: "POST" })).status,
      202,
    );
    assert.deepEqual(await events.next((e) => e["type"] === "good"), {
      type: "good",
      project: "app",
    });
    assert.match(
      fs.readFileSync(path.join(env.juel, "dashboard.log"), "utf8"),
      /module bad skipped: boom/,
    );
  } finally {
    events.close();
    await env.close();
    fs.rmSync(mods, { recursive: true, force: true });
  }
});
