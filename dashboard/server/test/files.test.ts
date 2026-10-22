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
