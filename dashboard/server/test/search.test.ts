import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { test } from "node:test";
import os from "node:os";
import { setup } from "./helpers.ts";

process.env.JUEL_RECALL_SH = path.join(os.tmpdir(), "no-such-recall.sh");

type Hit = {
  group: string;
  title: string;
  sub: string;
  ref: string;
  project: string;
  route: string;
};
const find = async (
  env: Awaited<ReturnType<typeof setup>>,
  qs: string,
): Promise<Hit[]> =>
  (await (await env.api(`/api/search?${qs}`)).json()) as Hit[];

test("search finds items, open loops and decision headings in one project", async () => {
  const env = await setup();
  try {
    assert.deepEqual(await find(env, "q=csv&project=app"), [
      {
        group: "Items",
        title: "Export reports as CSV",
        sub: "building, gate-r2 codex gate round 2",
        ref: "issue-1",
        project: "app",
        route: "/app/progress?item=issue-1",
      },
      {
        group: "Needs you",
        title: "Ria in #eng: is the CSV export landing today?",
        sub: "slack-reply",
        ref: "N-4",
        project: "app",
        route: "/app/needs?loop=N-4",
      },
      {
        group: "Decisions",
        title: "CSV over XLSX (2026-10-15, decided by the brief worker)",
        sub: "issue-1 D1",
        ref: "D1",
        project: "app",
        route: "/app/progress?item=issue-1",
      },
    ]);
  } finally {
    await env.close();
  }
});

test("search finds Slack drafts, briefings and evidence file names", async () => {
  const env = await setup();
  try {
    assert.deepEqual(await find(env, "q=final%20review&project=app"), [
      {
        group: "Slack",
        title: "Not today. It's in final review now.",
        sub: "2026-10-15-app-slack-C1-1700000000.000100.md",
        ref: "C1-1700000000.000100",
        project: "app",
        route: "/app/slack?draft=2026-10-15-app-slack-C1-1700000000.000100.md",
      },
    ]);
    assert.deepEqual(
      (await find(env, "q=SAVED&project=app")).map((h) => [
        h.group,
        h.title,
        h.route,
      ]),
      [["Briefings", "Saved report views", "/app/briefing?id=b1"]],
    );
    assert.deepEqual(
      (await find(env, "q=invoice&project=app")).map((h) => [
        h.group,
        h.title,
        h.ref,
      ]),
      [
        ["Items", "Fix invoice rounding", "issue-4"],
        ["Evidence", "invoice-page.png", "issue-4"],
      ],
    );
    assert.deepEqual(await find(env, "q=&project=app"), []);
    assert.equal((await env.api("/api/search?q=csv")).status, 400);
    assert.equal(
      (await env.api("/api/search?q=csv&project=ghost")).status,
      404,
    );
  } finally {
    await env.close();
  }
});

test("all=1 searches every registered project and skips one that cannot be read", async () => {
  const env = await setup();
  try {
    await env.addProject("second");
    await env.addProject("broken", (home) =>
      fs.writeFileSync(path.join(home, "ledger.md"), "garbage\n"),
    );
    const hits = await find(env, "q=xlsx&all=1");
    assert.deepEqual(
      hits.map((h) => [h.project, h.group, h.ref]),
      [
        ["app", "Decisions", "D1"],
        ["second", "Decisions", "D1"],
      ],
    );
    assert.equal(
      (await env.api("/api/search?q=xlsx&project=broken")).status,
      502,
    );
    assert.match(
      fs.readFileSync(path.join(env.juel, "dashboard.log"), "utf8"),
      /search skipped broken: ledger\.md: no ledger table/,
    );
  } finally {
    await env.close();
  }
});

async function withFake(
  body: string,
  run: () => Promise<void>,
): Promise<void> {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "fake-recall-"));
  const script = path.join(dir, "recall.sh");
  fs.writeFileSync(script, body);
  const prev = process.env.JUEL_RECALL_SH;
  process.env.JUEL_RECALL_SH = script;
  try {
    await run();
  } finally {
    process.env.JUEL_RECALL_SH = prev;
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

const THREE = `cat <<'LINES'
{"kind":"decision","ref":"issue-4#D3","item":"issue-4","status":"active","title":"Round half up","excerpt":"x","project":"app","date":"2026-10-15","path":"briefs/app/issue-4.md"}
{"kind":"library","ref":"L-0002","item":"issue-1","status":"active","title":"CSV over XLSX","excerpt":"x","project":"app","date":"2026-10-15","path":"library/app/L-0002.md"}
{"kind":"release","ref":"2026-10-15-app-issue-4","item":"issue-4","status":"merged","title":"Fix rounding","excerpt":"x","project":"app","date":"2026-10-15","path":"releases/x.md"}
{"kind":"note","ref":"M-0001","item":"","status":"active","title":"A note","excerpt":"x","project":"app","date":"2026-10-15","path":"memory/app/M-0001.md"}
LINES
`;

test("search adds decision text, library decisions and release records from recall.sh", async () => {
  const env = await setup();
  try {
    await withFake(THREE, async () => {
      const hits = await find(env, "q=rounding&project=app");
      const has = (h: Hit): boolean =>
        hits.some((x) => JSON.stringify(x) === JSON.stringify(h));
      assert.ok(
        has({
          group: "Decisions",
          title: "Round half up",
          sub: "issue-4 D3",
          ref: "D3",
          project: "app",
          route: "/app/progress?item=issue-4",
        }),
      );
      assert.ok(
        has({
          group: "Decisions",
          title: "L-0002 CSV over XLSX",
          sub: "library",
          ref: "L-0002",
          project: "app",
          route: "/app/progress?item=issue-1",
        }),
      );
      assert.ok(
        has({
          group: "Releases",
          title: "Fix rounding",
          sub: "issue-4",
          ref: "issue-4",
          project: "app",
          route: "/app/evidence?item=issue-4",
        }),
      );
      assert.equal(hits.some((h) => h.ref === "M-0001"), false);
    });
  } finally {
    await env.close();
  }
});

test("a decision the heading scan already found appears once", async () => {
  const env = await setup();
  try {
    await withFake(
      `echo '{"kind":"decision","ref":"issue-1#D1","item":"issue-1","status":"active","title":"CSV over XLSX","excerpt":"","project":"app","date":"","path":""}'\n`,
      async () => {
        const hits = await find(env, "q=csv&project=app");
        assert.equal(
          hits.filter((h) => h.group === "Decisions" && h.sub === "issue-1 D1")
            .length,
          1,
        );
      },
    );
  } finally {
    await env.close();
  }
});

test("a slow or failing recall.sh leaves today's hits, within 6 s", async () => {
  const env = await setup();
  try {
    const today = await find(env, "q=csv&project=app");
    for (const body of ["exec sleep 10\n", "echo 'not json'\nexit 1\n"]) {
      await withFake(body, async () => {
        const t0 = Date.now();
        assert.deepEqual(await find(env, "q=csv&project=app"), today);
        assert.ok(Date.now() - t0 < 6000);
      });
    }
  } finally {
    await env.close();
  }
});
