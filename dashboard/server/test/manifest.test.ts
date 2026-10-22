import assert from "node:assert/strict";
import { test } from "node:test";
import { TOKEN, setup } from "./helpers.ts";

const ICONS = [
  { src: "/icons/star-192.png", sizes: "192x192", type: "image/png", purpose: "any" },
  { src: "/icons/star-512.png", sizes: "512x512", type: "image/png", purpose: "any" },
  { src: "/icons/star-512-maskable.png", sizes: "512x512", type: "image/png", purpose: "maskable" },
];
const manifest = (startUrl: string) => ({
  id: "/",
  name: "STAR",
  short_name: "STAR",
  start_url: startUrl,
  scope: "/",
  display: "standalone",
  background_color: "#ffffff",
  theme_color: "#ffffff",
  icons: ICONS,
});
// no token header: the manifest route is outside the /api check
const get = (url: (p: string) => string, qs: string) =>
  fetch(url(`/manifest.webmanifest${qs}`));

test("a manifest request with the token opens signed in, with the right headers", async () => {
  const env = await setup();
  try {
    const r = await get(env.url, `?t=${TOKEN}`);
    assert.equal(r.status, 200);
    assert.equal(r.headers.get("content-type"), "application/manifest+json; charset=utf-8");
    assert.equal(r.headers.get("cache-control"), "no-store");
    assert.deepEqual(await r.json(), manifest(`/?t=${TOKEN}`));
  } finally {
    await env.close();
  }
});

test("a manifest request without a good token never carries the token", async () => {
  const env = await setup();
  try {
    for (const qs of [
      "",
      "?t=wrong",
      "?t=",
      `?t=x&t=${TOKEN}`,
      `?t=${TOKEN}&t=${TOKEN}`,
      `?t=${TOKEN.toUpperCase()}`,
      `?x=${TOKEN}`,
    ]) {
      const r = await get(env.url, qs);
      assert.equal(r.status, 200, qs);
      const text = await r.text();
      assert.equal(text.includes(TOKEN), false, qs);
      assert.deepEqual(JSON.parse(text), manifest("/"), qs);
    }
  } finally {
    await env.close();
  }
});

test("the manifest route is GET only, and /api keeps its token check", async () => {
  const env = await setup();
  try {
    const post = await fetch(env.url(`/manifest.webmanifest?t=${TOKEN}`), { method: "POST" });
    assert.equal(post.status, 405);
    assert.equal((await post.text()).includes(TOKEN), false);
    assert.equal((await fetch(env.url("/api/items"))).status, 401);
    assert.equal((await fetch(env.url("/api/items"), { headers: { "x-star-token": "nope" } })).status, 401);
  } finally {
    await env.close();
  }
});
