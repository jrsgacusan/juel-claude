import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { test } from "node:test";
import { setTimeout as sleep } from "node:timers/promises";
import { openEvents, setup } from "./helpers.ts";

const register = (
  env: Awaited<ReturnType<typeof setup>>,
  entries: unknown,
): void =>
  fs.writeFileSync(
    path.join(env.juel, "star-homes.json"),
    JSON.stringify(entries),
  );
const log = (env: Awaited<ReturnType<typeof setup>>): string => {
  try {
    return fs.readFileSync(path.join(env.juel, "dashboard.log"), "utf8");
  } catch {
    return "";
  }
};

test("two folders under one name: the one whose folder still exists wins, and the other is logged", async () => {
  const env = await setup();
  try {
    const gone = path.join(env.tmp, "old", "star");
    register(env, [
      { name: "app", repo: "/old", home: gone },
      { name: "app", repo: path.join(env.tmp, "app"), home: env.star },
      { name: "bad" },
    ]);
    await env.app.registry.refresh();
    const list = (await (await env.api("/api/projects")).json()) as {
      name: string;
      repo: string;
    }[];
    assert.deepEqual(
      list.map((p) => [p.name, p.repo]),
      [["app", path.join(env.tmp, "app")]],
    );
    assert.match(
      log(env),
      new RegExp(
        `star-homes\\.json: ${gone.replace(/[.*+?^${}()|[\\]\\]/g, "\\$&")} skipped: .* is project app too`,
      ),
    );
    assert.match(
      log(env),
      /star-homes\.json: skipped an entry that is not \{name, repo, home\}/,
    );
  } finally {
    await env.close();
  }
});

test("a registry that is not JSON lists nothing and says so in the log", async () => {
  const env = await setup();
  try {
    fs.writeFileSync(path.join(env.juel, "star-homes.json"), "not json");
    await env.app.registry.refresh();
    assert.deepEqual(await (await env.api("/api/projects")).json(), []);
    assert.match(log(env), /star-homes\.json unreadable/);
  } finally {
    await env.close();
  }
});

test("an Orca list that fails shows every project stopped and logs why once", async () => {
  const env = await setup();
  try {
    env.setTerminals(null);
    await env.app.registry.refresh();
    await env.app.registry.refresh();
    const list = (await (await env.api("/api/projects")).json()) as {
      state: string;
    }[];
    assert.equal(list[0]?.state, "stopped");
    assert.equal(
      log(env).match(/orca terminal list failed/g)?.length,
      1,
      log(env),
    );
  } finally {
    await env.close();
  }
});

test("concurrent reads share one Orca call", async () => {
  const env = await setup();
  try {
    const before = env
      .orcaCalls()
      .filter((c) => c.startsWith("terminal list")).length;
    await Promise.all([
      env.app.registry.refresh(),
      env.app.registry.refresh(),
      env.app.registry.refresh(),
    ]);
    assert.equal(
      env.orcaCalls().filter((c) => c.startsWith("terminal list")).length -
        before,
      1,
    );
  } finally {
    await env.close();
  }
});

test("modules see a project registered later without any request, and cannot change the core list", async () => {
  const env = await setup({ refreshMs: 200 });
  try {
    const before = env.app.registry.snapshot();
    before.splice(0, 1);
    assert.equal(
      env.app.registry.snapshot().length,
      1,
      "snapshot() hands out a copy",
    );
    const later = path.join(env.tmp, "later", "star");
    fs.cpSync(path.join(import.meta.dirname, "fixtures", "star"), later, {
      recursive: true,
    });
    const list = JSON.parse(
      fs.readFileSync(path.join(env.juel, "star-homes.json"), "utf8"),
    ) as unknown[];
    register(env, [
      ...list,
      { name: "later", repo: path.join(env.tmp, "later"), home: later },
    ]);
    await sleep(600);
    assert.deepEqual(
      env.app.registry.snapshot().map((p) => p.name),
      ["app", "later"],
    );
  } finally {
    await env.close();
  }
});

test("a folder registered after start gets change events, and a rename relabels them", async () => {
  const env = await setup({ rescanMs: 200 });
  const events = await openEvents(env);
  try {
    const later = await env.addProject("later");
    await sleep(500);
    fs.appendFileSync(path.join(later, "open-loops.md"), "\n");
    assert.deepEqual(
      await events.next(
        (e) => e["project"] === "later" && e["what"] === "loops",
      ),
      { type: "change", project: "later", what: "loops" },
    );
    const list = JSON.parse(
      fs.readFileSync(path.join(env.juel, "star-homes.json"), "utf8"),
    ) as { name: string }[];
    register(
      env,
      list.map((e) => (e.name === "later" ? { ...e, name: "renamed" } : e)),
    );
    await sleep(500);
    fs.appendFileSync(path.join(later, "ledger.md"), "\n");
    assert.deepEqual(
      await events.next(
        (e) => e["project"] === "renamed" && e["what"] === "ledger",
      ),
      { type: "change", project: "renamed", what: "ledger" },
    );
  } finally {
    events.close();
    await env.close();
  }
});
