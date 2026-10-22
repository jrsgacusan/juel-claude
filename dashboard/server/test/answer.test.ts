import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { setup } from "./helpers.ts";

const answer = (
  env: Awaited<ReturnType<typeof setup>>,
  id: string,
  text: unknown,
): Promise<Response> =>
  env.api(`/api/projects/app/loops/${id}/answer`, {
    method: "POST",
    body: JSON.stringify({ text }),
  });

const block = (queue: string, id: string): string => {
  const at = queue.indexOf(`### ${id} `);
  const next = queue.indexOf("\n### ", at + 1);
  return queue.slice(at, next < 0 ? undefined : next);
};

test("an answer lands on the Answer line through loops.sh, then STAR is nudged with inbox", async () => {
  const env = await setup();
  try {
    const r = await answer(env, "N-3", "  done  ");
    assert.equal(r.status, 200);
    assert.deepEqual(await r.json(), { recorded: true, nudged: true });
    const queue = fs.readFileSync(path.join(env.star, "open-loops.md"), "utf8");
    assert.match(block(queue, "N-3"), /^Answer: done$/m);
    assert.ok(
      env
        .orcaCalls()
        .includes(
          "terminal send --terminal term_star --text inbox --enter --json",
        ),
      env.orcaCalls().join("\n"),
    );
    const again = await answer(env, "N-3", "done");
    assert.equal(again.status, 409);
    assert.match(
      ((await again.json()) as { error: string }).error,
      /N-3 already has an answer/,
    );
  } finally {
    await env.close();
  }
});

test("an answer that starts with a dash or spans lines is recorded as one line", async () => {
  const env = await setup();
  try {
    const r = await answer(env, "N-5", "- drop issue-2\nfor now");
    assert.equal(r.status, 200);
    assert.match(
      block(
        fs.readFileSync(path.join(env.star, "open-loops.md"), "utf8"),
        "N-5",
      ),
      /^Answer: - drop issue-2 for now$/m,
    );
  } finally {
    await env.close();
  }
});

test("with STAR stopped, or a nudge Orca refuses, the answer is still recorded and nudged is false", async () => {
  const env = await setup();
  try {
    env.setTerminals([]);
    const r = await answer(env, "N-3", "skip");
    assert.deepEqual(await r.json(), { recorded: true, nudged: false });
    assert.equal(
      env.orcaCalls().filter((c) => c.startsWith("terminal send")).length,
      0,
    );
    env.setTerminals(["term_star"]);
    fs.writeFileSync(path.join(env.tmp, "send-fails"), "");
    const r2 = await answer(env, "N-5", "go");
    assert.deepEqual(await r2.json(), { recorded: true, nudged: false });
    env.setTerminals(null);
    const r3 = await answer(env, "N-6", "can't now");
    assert.deepEqual(await r3.json(), { recorded: true, nudged: false });
    const queue = fs.readFileSync(path.join(env.star, "open-loops.md"), "utf8");
    assert.match(block(queue, "N-3"), /^Answer: skip$/m);
    assert.match(block(queue, "N-5"), /^Answer: go$/m);
    assert.match(block(queue, "N-6"), /^Answer: can't now$/m);
  } finally {
    await env.close();
  }
});

test("conflict markers are 409 with loops.sh's message; an unknown id 404; no words 400", async () => {
  const env = await setup();
  try {
    assert.equal((await answer(env, "N-99", "done")).status, 404);
    assert.equal((await answer(env, "N-3", "…?")).status, 400);
    assert.equal((await answer(env, "N-3", 42)).status, 400);
    assert.equal((await answer(env, "bogus", "done")).status, 400);
    fs.appendFileSync(path.join(env.star, "open-loops.md"), "<<<<<<< HEAD\n");
    const r = await answer(env, "N-3", "done");
    assert.equal(r.status, 409);
    assert.match(
      ((await r.json()) as { error: string }).error,
      /unresolved git conflict markers/,
    );
    assert.equal(
      env.orcaCalls().filter((c) => c.startsWith("terminal send")).length,
      0,
    );
  } finally {
    await env.close();
  }
});

test("a loops.sh that fails is a 500 with its last line, and the log keeps the whole reason", async () => {
  const bad = path.join(
    fs.mkdtempSync(path.join(os.tmpdir(), "star-loops-")),
    "loops.sh",
  );
  fs.writeFileSync(
    bad,
    "echo 'Traceback (most recent call last):' >&2\necho 'KeyError: boom' >&2\nexit 1\n",
  );
  const env = await setup({ loopsSh: bad });
  try {
    const r = await answer(env, "N-3", "done");
    assert.equal(r.status, 500);
    assert.deepEqual(await r.json(), { error: "KeyError: boom" });
    assert.match(
      fs.readFileSync(path.join(env.juel, "dashboard.log"), "utf8"),
      /POST \/api\/projects\/app\/loops\/N-3\/answer: 500 KeyError: boom/,
    );
  } finally {
    await env.close();
  }
});
