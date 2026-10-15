import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { test } from "node:test";
import { setup } from "./helpers.ts";

const file = (rel: string): string =>
  `/api/projects/app/file?path=${encodeURIComponent(rel)}`;

test("GET file serves a file inside the STAR folder with its type", async () => {
  const env = await setup();
  try {
    const r = await env.api(
      file("evidence/issue-4/2026-10-15-fix-rounding/report.md"),
    );
    assert.equal(r.status, 200);
    assert.match(r.headers.get("content-type") ?? "", /^text\/plain/);
    assert.equal(r.headers.get("x-content-type-options"), "nosniff");
    assert.equal(r.headers.get("content-security-policy"), "sandbox");
    assert.equal(await r.text(), "evidence head=0b8e4c3\n");
    const png = await env.api(
      file(
        "evidence/issue-4/2026-10-15-fix-rounding/screenshots/invoice-page.png",
      ),
    );
    assert.equal(png.headers.get("content-type"), "image/png");
    const big = Buffer.alloc(2 * 1024 * 1024, 7);
    fs.writeFileSync(
      path.join(env.star, "evidence", "issue-4", "big.webm"),
      big,
    );
    const video = await env.api(file("evidence/issue-4/big.webm"));
    assert.equal(video.headers.get("content-length"), String(big.length));
    assert.equal(Buffer.from(await video.arrayBuffer()).equals(big), true);
    assert.equal((await fetch(env.url(file("ledger.md")))).status, 401);
  } finally {
    await env.close();
  }
});

test("GET file refuses .., an absolute path and a symlink out with 400; a missing file is 404", async () => {
  const env = await setup();
  try {
    fs.writeFileSync(path.join(env.tmp, "outside.txt"), "secret\n");
    fs.symlinkSync(
      path.join(env.tmp, "outside.txt"),
      path.join(env.star, "evidence", "issue-4", "out.txt"),
    );
    for (const rel of [
      "../outside.txt",
      "evidence/../../outside.txt",
      path.join(env.tmp, "outside.txt"),
      "/etc/hosts",
      "evidence/issue-4/out.txt",
      "",
    ]) {
      const r = await env.api(file(rel));
      assert.equal(r.status, 400, rel);
      assert.doesNotMatch(await r.text(), /secret/);
    }
    assert.equal((await env.api(file("evidence"))).status, 400);
    assert.equal((await env.api(file("evidence/nope.png"))).status, 404);
  } finally {
    await env.close();
  }
});

test("PUT drafts/:name replaces everything after the first line and keeps the first line", async () => {
  const env = await setup();
  const name = "2026-10-15-app-slack-C1-1700000000.000100.md";
  try {
    const r = await env.api(`/api/projects/app/drafts/${name}`, {
      method: "PUT",
      body: JSON.stringify({ text: "Tomorrow morning, before the demo.\n\n" }),
    });
    assert.equal(r.status, 200);
    assert.deepEqual(await r.json(), { saved: true });
    assert.equal(
      fs.readFileSync(path.join(env.star, "drafts", name), "utf8"),
      "to: slack C1 1700000000.000100\nTomorrow morning, before the demo.\n",
    );
    // (a bare `..` segment never reaches the server: fetch resolves it in the URL first)
    for (const bad of ["..%2Fledger.md", ".hidden", "a%20b.md", "x..md"]) {
      const b = await env.api(`/api/projects/app/drafts/${bad}`, {
        method: "PUT",
        body: JSON.stringify({ text: "x" }),
      });
      assert.equal(b.status, 400, bad);
    }
    assert.equal(
      (
        await env.api("/api/projects/app/drafts/nope.md", {
          method: "PUT",
          body: JSON.stringify({ text: "x" }),
        })
      ).status,
      404,
    );
    assert.equal(
      (
        await env.api(`/api/projects/app/drafts/${name}`, {
          method: "PUT",
          body: JSON.stringify({ text: 3 }),
        })
      ).status,
      400,
    );
    assert.equal(
      (
        await env.api(`/api/projects/app/drafts/${name}`, {
          method: "PUT",
          body: "not json",
        })
      ).status,
      400,
    );
    assert.equal(
      fs
        .readFileSync(path.join(env.star, "ledger.md"), "utf8")
        .startsWith("# Ledger"),
      true,
    );
  } finally {
    await env.close();
  }
});

test("an html evidence file is served as text, and a file the server cannot read is 502", async () => {
  const env = await setup();
  try {
    const htmlPath = path.join(env.star, "evidence", "issue-4", "page.html");
    fs.writeFileSync(htmlPath, "<script>alert(1)</script>");
    const html = await env.api(file("evidence/issue-4/page.html"));
    assert.match(html.headers.get("content-type") ?? "", /^text\/plain/);
    fs.chmodSync(htmlPath, 0o000);
    const locked = await env.api(file("evidence/issue-4/page.html"));
    assert.equal(locked.status, 502);
    assert.match(
      ((await locked.json()) as { error: string }).error,
      /^evidence\/issue-4\/page\.html: permission denied/,
    );
  } finally {
    await env.close();
  }
});

test("search on one project with an unreadable draft is 502 naming it", async () => {
  const env = await setup();
  try {
    fs.chmodSync(
      path.join(
        env.star,
        "drafts",
        "2026-10-15-app-slack-C1-1700000000.000100.md",
      ),
      0o000,
    );
    const r = await env.api("/api/search?q=x&project=app");
    assert.equal(r.status, 502);
    assert.match(
      ((await r.json()) as { error: string }).error,
      /^drafts\/2026-10-15-app-slack-C1-1700000000\.000100\.md: permission denied/,
    );
  } finally {
    await env.close();
  }
});
