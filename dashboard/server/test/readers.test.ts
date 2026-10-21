import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { allDecisions, parseBrief, readBrief } from "../readers/briefs.ts";
import { isPlainName, listFiles, readText } from "../readers/files.ts";
import { kindOf } from "../readers/evidence.ts";
import { readProgress } from "../readers/progress.ts";
import { readRelease } from "../readers/releases.ts";
import { slackDrafts } from "../readers/drafts.ts";
import { readBriefings } from "../readers/briefings.ts";
import { awayPendingOf, readLedger, readQueue, readStar, tickOf } from "../readers/star.ts";
import { Unreadable } from "../http.ts";
import { Router } from "../router.ts";

const FIXTURE = path.join(import.meta.dirname, "fixtures", "star");

test("the ledger, queue and star.json read through hooks/star.ts", () => {
  const rows = readLedger(FIXTURE);
  assert.equal(rows.length, 6);
  assert.equal(rows[0]?.counters, "batch=B-1 start=1");
  const q = readQueue(FIXTURE);
  assert.deepEqual(
    q.needs.map((n) => n.id),
    ["N-3", "N-4", "N-5", "N-6", "N-7"],
  );
  assert.equal(tickOf(q.resume), "2026-10-15T08:00:00Z");
  assert.equal(tickOf({ "last tick": "-" }), null);
  const s = readStar(FIXTURE);
  assert.equal(s.star.terminal, "term_star");
  assert.equal("quietHours" in s.raw, false);
});

test("an unreadable or broken file is an Unreadable naming it", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "star-readers-"));
  fs.writeFileSync(path.join(tmp, "ledger.md"), "# Ledger\n| nope |\n");
  assert.throws(
    () => readLedger(tmp),
    (err: unknown) =>
      err instanceof Unreadable &&
      err.file === "ledger.md" &&
      /no ledger table/.test(err.why),
  );
  assert.throws(
    () => readQueue(tmp),
    (err: unknown) =>
      err instanceof Unreadable &&
      err.file === "open-loops.md" &&
      err.why === "not found",
  );
  assert.throws(
    () => readText(tmp, "star.json"),
    (err: unknown) => err instanceof Unreadable && err.why === "not found",
  );
  fs.rmSync(tmp, { recursive: true, force: true });
});

test("a brief gives its title, go time, criteria and decision headings", () => {
  const b = readBrief(FIXTURE, "app", "issue-1");
  assert.deepEqual(b, {
    title: "Export reports as CSV",
    approved: "2026-10-15T07:00:00Z",
    criteria: [
      "The reports page has an Export CSV button",
      "The file opens in a spreadsheet",
    ],
    decisions: [
      {
        id: "D1",
        title: "CSV over XLSX (2026-10-15, decided by the brief worker)",
      },
      {
        id: "D2",
        title: "A 10,000-row cap on exports (2026-10-15, decided by STAR)",
      },
    ],
  });
  assert.equal(
    readBrief(FIXTURE, "app", "issue-4")?.title,
    "Fix invoice rounding",
  );
  assert.equal(readBrief(FIXTURE, "app", "nope"), null);
  assert.deepEqual(parseBrief("no frontmatter\n"), {
    title: null,
    approved: null,
    criteria: [],
    decisions: [],
  });
  assert.deepEqual(
    allDecisions(FIXTURE, "app").map((d) => `${d.item} ${d.id}`),
    ["issue-1 D1", "issue-1 D2"],
  );
});

test("progress lines, release records, evidence kinds, drafts and briefings", () => {
  assert.deepEqual(readProgress(FIXTURE, "issue-1"), [
    { time: "2026-10-15T07:10:00Z", text: "phase1 start: reading the brief" },
    { time: "2026-10-15T07:40:00Z", text: "gate-r2 codex gate round 2" },
  ]);
  assert.deepEqual(readProgress(FIXTURE, "nope"), []);
  assert.deepEqual(readRelease(FIXTURE, "app", "issue-4"), {
    title: "Fix invoice rounding",
    pr: "https://github.com/o/r/pull/7",
    sha: "0b8e4c3d2a1f",
    mergedAt: "2026-10-15T11:40:00Z",
    gate: "Merging head 0b8e4c3d2a1f: codex PASS, required checks green.",
    fields: {
      PR: "https://github.com/o/r/pull/7 (#7), fix/rounding → main",
      Merged: "2026-10-15T11:40:00Z by someone, merge commit 0b8e4c3d2a1f",
      "Approved by": "a-teammate",
      "Checks on the PR head at merge": "all passed",
      "Second-model review rounds": "1",
      Evidence: "evidence/issue-4/",
    },
  });
  assert.deepEqual(readRelease(FIXTURE, "app", "issue-1"), {
    title: null,
    pr: null,
    sha: null,
    mergedAt: null,
    gate: null,
    fields: {},
  });
  const box = fs.mkdtempSync(path.join(os.tmpdir(), "star-rel-"));
  fs.mkdirSync(path.join(box, "releases"));
  const rec = (name: string, text: string) =>
    fs.writeFileSync(path.join(box, "releases", name), text);
  rec("2026-10-16-app-old-1.md", "# app · old-1 · Old shape\n\n- PR: https://x/pull/1 (#1), a → main\n");
  rec("2026-10-16-app-new-1.md", '---\ngate: null\n---\n# app · new-1 · Null gate\n');
  rec("2026-10-16-app-new-2.md", '---\ngate: "Merging head abc: codex PASS, required checks green."\n---\n# app · new-2 · With gate\n- PR: https://x/pull/2 (#2), a → main\n');
  assert.equal(readRelease(box, "app", "old-1").title, "Old shape");
  assert.equal(readRelease(box, "app", "old-1").gate, null);
  assert.equal(readRelease(box, "app", "new-1").title, "Null gate");
  assert.equal(readRelease(box, "app", "new-1").gate, null);
  assert.equal(readRelease(box, "app", "new-2").gate, "Merging head abc: codex PASS, required checks green.");
  assert.equal(readRelease(box, "app", "new-2").pr, "https://x/pull/2");
  fs.rmSync(box, { recursive: true, force: true });
  assert.deepEqual(listFiles(path.join(FIXTURE, "evidence", "issue-4")), [
    "2026-10-15-fix-rounding/recording.webm",
    "2026-10-15-fix-rounding/report.md",
    "2026-10-15-fix-rounding/screenshots/invoice-page.png",
  ]);
  assert.deepEqual(["a.PNG", "b.webm", "c.md", "d.mov", "e.svg"].map(kindOf), [
    "image",
    "video",
    "text",
    "video",
    "image",
  ]);
  assert.deepEqual(slackDrafts(FIXTURE), [
    {
      name: "2026-10-15-app-slack-C1-1700000000.000100.md",
      to: "to: slack C1 1700000000.000100",
      reply: "Not today. It's in final review now.",
    },
  ]);
  assert.deepEqual(readBriefings(FIXTURE), [
    { id: "b1", title: "Saved report views" },
  ]);
  assert.deepEqual(
    ["issue-1", "a.b_c-1", "..", ".x", "a/b", "a b", ""].map(isPlainName),
    [true, true, false, false, false, false, false],
  );
});

test("the router matches params and tells a wrong method from a missing path", async () => {
  const r = new Router();
  r.add("GET", "/api/projects/:p/items/:item", async (req) => ({
    json: req.params,
  }));
  const hit = r.match("GET", "/api/projects/app/items/issue%2D1");
  assert.ok(hit && hit !== "method");
  assert.deepEqual(hit.params, { p: "app", item: "issue-1" });
  assert.equal(r.match("POST", "/api/projects/app/items/issue-1"), "method");
  assert.equal(r.match("GET", "/api/projects/app/items"), undefined);
});

test("the router routes DELETE like any other method", () => {
  const r = new Router();
  r.add("DELETE", "/api/projects/:p/briefings/:id", async (req) => ({
    json: req.params,
  }));
  const hit = r.match("DELETE", "/api/projects/app/briefings/b1");
  assert.ok(hit && hit !== "method");
  assert.deepEqual(hit.params, { p: "app", id: "b1" });
  assert.equal(r.match("GET", "/api/projects/app/briefings/b1"), "method");
});

test("awayPendingOf: the newest away or back control file still in inbox/", () => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "star-away-"));
  const inbox = path.join(home, "inbox");
  const put = (name: string, text: string): void =>
    fs.writeFileSync(path.join(inbox, name), text);
  try {
    assert.equal(awayPendingOf(home), null);
    fs.mkdirSync(inbox);
    assert.equal(awayPendingOf(home), null);
    put("20261017T010000Z-control-aaaa.md", "control: away\n");
    assert.equal(awayPendingOf(home), "away");
    put("20261017T020000Z-control-bbbb.md", "control: back\n");
    assert.equal(awayPendingOf(home), "back");
    put("20261017T030000Z-control-cccc.md", "control: stop\n");
    put("20261017T040000Z-chat-dddd.md", "repo: /w/app\nchat: x\ntext: |\n  control: away\n");
    put(".20261017T050000Z-control-eeee.md.1.abcd.tmp", "control: away\n");
    assert.equal(awayPendingOf(home), "back");
    fs.rmSync(path.join(inbox, "20261017T020000Z-control-bbbb.md"));
    assert.equal(awayPendingOf(home), "away");
    fs.rmSync(path.join(inbox, "20261017T010000Z-control-aaaa.md"));
    assert.equal(awayPendingOf(home), null);
  } finally {
    fs.rmSync(home, { recursive: true, force: true });
  }
});
