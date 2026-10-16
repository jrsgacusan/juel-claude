import assert from "node:assert/strict";
import fs from "node:fs";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { IMMUTABLE, serveStatic } from "../static.ts";

/** serveStatic alone on 127.0.0.1:0, over a dist folder the test builds. */
async function serve(dist: string): Promise<{ url(p: string): string; close(): Promise<void> }> {
  const server = http.createServer((req, res) => serveStatic(req, res, dist));
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const port = (server.address() as { port: number }).port;
  return {
    url: (p) => `http://127.0.0.1:${port}${p}`,
    close: () => new Promise<void>((resolve) => { server.close(() => resolve()); server.closeAllConnections(); }),
  };
}

/** box/dist with index.html, two hashed assets and robots.txt; box/secret.js outside it, linked from assets/link.js. */
function build(): { box: string; dist: string } {
  const box = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), "star-static-")));
  const dist = path.join(box, "dist");
  fs.mkdirSync(path.join(dist, "assets"), { recursive: true });
  fs.writeFileSync(path.join(dist, "index.html"), "<!doctype html><title>STAR</title>");
  fs.writeFileSync(path.join(dist, "assets", "index-BxYz12ab.js"), "console.log(1)");
  fs.writeFileSync(path.join(dist, "assets", "geist-latin-Dm3htQBi.woff2"), "font");
  fs.writeFileSync(path.join(dist, "robots.txt"), "User-agent: *");
  fs.writeFileSync(path.join(box, "secret.js"), "leak");
  fs.symlinkSync(path.join(box, "secret.js"), path.join(dist, "assets", "link.js"));
  return { box, dist };
}

test("a hashed file under /assets is cached for a year, immutable, on GET and on HEAD", async () => {
  const { box, dist } = build();
  const s = await serve(dist);
  try {
    assert.equal(IMMUTABLE, "public, max-age=31536000, immutable");
    for (const p of ["/assets/index-BxYz12ab.js", "/assets/geist-latin-Dm3htQBi.woff2"]) {
      for (const method of ["GET", "HEAD"]) {
        const r = await fetch(s.url(p), { method });
        assert.equal(r.status, 200, `${method} ${p}`);
        assert.equal(r.headers.get("cache-control"), IMMUTABLE, `${method} ${p}`);
      }
    }
    assert.equal(await (await fetch(s.url("/assets/index-BxYz12ab.js"))).text(), "console.log(1)");
  } finally {
    await s.close();
    fs.rmSync(box, { recursive: true, force: true });
  }
});

test("index.html, a deep link, a missing asset and a link out of dist all get index.html with no-cache", async () => {
  const { box, dist } = build();
  const s = await serve(dist);
  try {
    for (const p of ["/", "/index.html", "/app/needs", "/assets/missing-AAAAAAAA.js", "/assets/link.js"]) {
      const r = await fetch(s.url(p));
      const body = await r.text();
      assert.equal(r.status, 200, p);
      assert.equal(r.headers.get("cache-control"), "no-cache", p);
      assert.match(body, /<title>STAR<\/title>/, p);
      assert.doesNotMatch(body, /leak/, p);
    }
  } finally {
    await s.close();
    fs.rmSync(box, { recursive: true, force: true });
  }
});

test("a file outside /assets keeps no-cache, and the build-first page stays no-store", async () => {
  const { box, dist } = build();
  const s = await serve(dist);
  const empty = await serve(path.join(box, "nope"));
  try {
    const r = await fetch(s.url("/robots.txt"));
    assert.equal(await r.text(), "User-agent: *");
    assert.equal(r.headers.get("cache-control"), "no-cache");
    const b = await fetch(empty.url("/"));
    assert.equal(b.headers.get("cache-control"), "no-store");
    assert.match(await b.text(), /Build the web app first/);
  } finally {
    await s.close();
    await empty.close();
    fs.rmSync(box, { recursive: true, force: true });
  }
});
