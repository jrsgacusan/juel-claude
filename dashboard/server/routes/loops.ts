import { needOf } from "../../../hooks/star.ts";
import type { NeedItem } from "../../../hooks/star.ts";
import path from "node:path";
import type { Ctx } from "../app.ts";
import { HttpError, Unreadable } from "../http.ts";
import { lastLine, run } from "../proc.ts";
import { readQueue } from "../readers/star.ts";
import type { Router } from "../router.ts";

const BLOCKED = [
  "go-batch",
  "question",
  "person",
  "escalation",
  "restart-or-drop",
  "go-merge",
];
const rank = (kind: string): number =>
  BLOCKED.includes(kind) ? 0 : kind === "slack-reply" ? 1 : 2;
const num = (id: string): number => Number(id.slice(2)) || 0;

export function loopOf(n: NeedItem, nowMs: number): Record<string, unknown> {
  const need = needOf(n, nowMs);
  return {
    id: n.id,
    kind: n.kind,
    item: n.item,
    title: n.title,
    body: n.body.filter((l) => !/^(options|suggest)\s*:/i.test(l)),
    options: need.options.map((o) => ({
      label: o.label,
      answer: o.text,
      recommended: o.recommended,
    })),
    suggestion: need.suggestion,
    answer: n.answer,
    askedAt: null,
  };
}

export function loopRoutes(router: Router, ctx: Ctx): void {
  router.add("GET", "/api/projects/:p/loops", async (req) => {
    const p = await ctx.registry.find(req.params["p"] ?? "");
    const needs = [...readQueue(p.home).needs].sort(
      (a, b) => rank(a.kind) - rank(b.kind) || num(a.id) - num(b.id),
    );
    return { json: needs.map((n) => loopOf(n, Date.now())) };
  });

  // The band's path (hooks/register.tsx sendAnswer): loops.sh set-answer, then wake STAR, here with
  // `orca terminal send` (ctx.nudge), since this process is not STAR's session. Nothing goes to a
  // worker from here: STAR's Answers step does that.
  router.add("POST", "/api/projects/:p/loops/:id/answer", async (req) => {
    const p = await ctx.registry.find(req.params["p"] ?? "");
    const id = req.params["id"] ?? "";
    if (!/^N-\d+$/.test(id))
      throw new HttpError(400, `${id} is not a queue id`);
    const body = req.body as { text?: unknown } | undefined;
    const text =
      typeof body?.text === "string"
        ? body.text.replace(/\s+/g, " ").trim()
        : "";
    if (!/[\p{L}\p{N}]/u.test(text))
      throw new HttpError(400, "type an answer in words first");
    const r = await run("sh", [
      ctx.loopsSh,
      "--file",
      path.join(p.home, "open-loops.md"),
      "set-answer",
      id,
      text,
    ]);
    const said = r.stdout.trim();
    const why = lastLine(r.stderr);
    if (r.code === 0 && said === "set")
      return { json: { recorded: true, nudged: await ctx.nudge(p) } };
    if (r.code === 0 && said === "kept")
      throw new HttpError(
        409,
        `${id} already has an answer: STAR acts on that one`,
      );
    if (r.code === 3)
      throw new HttpError(
        409,
        why || "open-loops.md has git conflict markers: resolve them first",
      );
    if (r.code === 4) throw new HttpError(404, why || `no ${id} in the queue`);
    if (r.code === 2)
      throw new Unreadable(
        "open-loops.md",
        why || "loops.sh could not read it",
      );
    throw new HttpError(500, why || `loops.sh exited ${r.code}`);
  });
}
