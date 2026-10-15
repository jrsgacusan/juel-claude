import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { test } from "node:test";
import { setup } from "./helpers.ts";

test("GET items: every ledger column plus title, status, step and prUrl", async () => {
  const env = await setup();
  try {
    const items = (await (
      await env.api("/api/projects/app/items")
    ).json()) as Record<string, unknown>[];
    assert.deepEqual(
      items.map((i) => [i["item"], i["status"]]),
      [
        ["issue-1", "building"],
        ["issue-2", "needs-you"],
        ["issue-3", "in-review"],
        ["issue-4", "merged"],
        ["issue-5", "stopped"],
        ["issue-6", "queued"],
      ],
    );
    assert.deepEqual(items[0], {
      item: "issue-1",
      ref: "#1",
      project: "app",
      worktree: "/w/app-issue-1",
      state: "building",
      stage: "build",
      round: "2",
      task: "t-1",
      dispatch: "d-1",
      restarts: "0",
      pr: "https://github.com/o/r/pull/11",
      head: "abc1234",
      cursor: "-",
      verify: "-",
      counters: "batch=B-1 start=1",
      updated: "2026-10-15T08:00:00Z",
      title: "Export reports as CSV",
      status: "building",
      step: "gate-r2 codex gate round 2",
      prUrl: "https://github.com/o/r/pull/11",
    });
    assert.equal(items[1]?.["title"], null);
    assert.equal(items[1]?.["step"], null);
    assert.equal(items[1]?.["prUrl"], null);
  } finally {
    await env.close();
  }
});

test("GET items/:item: the row, every progress line, the criteria and the decision headings", async () => {
  const env = await setup();
  try {
    const one = (await (
      await env.api("/api/projects/app/items/issue-1")
    ).json()) as Record<string, unknown>;
    assert.equal((one["row"] as Record<string, unknown>)["status"], "building");
    assert.deepEqual(one["progress"], [
      { time: "2026-10-15T07:10:00Z", text: "phase1 start: reading the brief" },
      { time: "2026-10-15T07:40:00Z", text: "gate-r2 codex gate round 2" },
    ]);
    assert.deepEqual(one["criteria"], [
      "The reports page has an Export CSV button",
      "The file opens in a spreadsheet",
    ]);
    assert.deepEqual(one["decisions"], [
      {
        id: "D1",
        title: "CSV over XLSX (2026-10-15, decided by the brief worker)",
      },
      {
        id: "D2",
        title: "A 10,000-row cap on exports (2026-10-15, decided by STAR)",
      },
    ]);
    assert.equal(
      (await env.api("/api/projects/app/items/issue-99")).status,
      404,
    );
    assert.equal(
      (await env.api("/api/projects/app/items/..%2Fstar")).status,
      400,
    );
    assert.equal((await env.api("/api/projects/app/items/a%20b")).status, 400);
  } finally {
    await env.close();
  }
});

test("a broken ledger makes only the routes that read it answer 502", async () => {
  const env = await setup();
  try {
    await env.addProject("broken", (home) =>
      fs.writeFileSync(path.join(home, "ledger.md"), "# Ledger\n| nope |\n"),
    );
    const r = await env.api("/api/projects/broken/items");
    assert.equal(r.status, 502);
    assert.deepEqual(await r.json(), { error: "ledger.md: no ledger table" });
    assert.equal((await env.api("/api/projects/broken/loops")).status, 200);
    assert.equal((await env.api("/api/projects/app/items")).status, 200);
    fs.chmodSync(path.join(env.star, "progress", "issue-1.log"), 0o000);
    const locked = await env.api("/api/projects/app/items/issue-1");
    assert.equal(locked.status, 502);
    assert.match(
      ((await locked.json()) as { error: string }).error,
      /^progress\/issue-1\.log: permission denied/,
    );
  } finally {
    await env.close();
  }
});

test("GET evidence: merged items with evidence, and one item's files in one group", async () => {
  const env = await setup();
  try {
    assert.deepEqual(
      await (await env.api("/api/projects/app/evidence")).json(),
      [
        {
          item: "issue-4",
          title: "Fix invoice rounding",
          pr: "https://github.com/o/r/pull/7",
          sha: "0b8e4c3d2a1f",
          mergedAt: "2026-10-15T11:40:00Z",
          goAt: "2026-10-15T09:30:00Z",
          files: 3,
        },
      ],
    );
    const one = (await (
      await env.api("/api/projects/app/evidence/issue-4")
    ).json()) as Record<string, unknown>;
    const enc = (rel: string): string =>
      `/api/projects/app/file?path=${encodeURIComponent(rel)}`;
    assert.deepEqual(one, {
      item: "issue-4",
      title: "Fix invoice rounding",
      pr: "https://github.com/o/r/pull/7",
      sha: "0b8e4c3d2a1f",
      mergedAt: "2026-10-15T11:40:00Z",
      goAt: "2026-10-15T09:30:00Z",
      groups: [
        {
          criterion: null,
          files: [
            {
              name: "2026-10-15-fix-rounding/recording.webm",
              kind: "video",
              url: enc(
                "evidence/issue-4/2026-10-15-fix-rounding/recording.webm",
              ),
            },
            {
              name: "2026-10-15-fix-rounding/report.md",
              kind: "text",
              url: enc("evidence/issue-4/2026-10-15-fix-rounding/report.md"),
            },
            {
              name: "2026-10-15-fix-rounding/screenshots/invoice-page.png",
              kind: "image",
              url: enc(
                "evidence/issue-4/2026-10-15-fix-rounding/screenshots/invoice-page.png",
              ),
            },
          ],
        },
      ],
    });
    assert.equal(
      (await env.api("/api/projects/app/evidence/issue-1")).status,
      404,
    );
    assert.equal(
      (await env.api("/api/projects/app/evidence/.hidden")).status,
      400,
    );
    assert.equal(
      (await env.api("/api/projects/app/evidence/..%2Fbriefs")).status,
      400,
    );
  } finally {
    await env.close();
  }
});
