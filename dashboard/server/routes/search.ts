import fs from "node:fs";
import path from "node:path";
import type { Ctx } from "../app.ts";
import { HttpError } from "../http.ts";
import { allDecisions, readBrief } from "../readers/briefs.ts";
import { readBriefings } from "../readers/briefings.ts";
import { slackDrafts } from "../readers/drafts.ts";
import { listFiles } from "../readers/files.ts";
import { readProgress } from "../readers/progress.ts";
import { readLedger, readQueue } from "../readers/star.ts";
import type { Router } from "../router.ts";
import type { Project } from "../types.ts";
import { statusOf } from "./items.ts";

type Hit = {
  group: string;
  title: string;
  sub: string;
  ref: string;
  project: string;
  route: string;
};
const LIMIT = 50;
const enc = encodeURIComponent;

function searchProject(p: Project, q: string): Hit[] {
  const out: Hit[] = [];
  const base = `/${enc(p.name)}`;
  const add = (
    group: string,
    title: string,
    sub: string,
    ref: string,
    route: string,
  ): void => {
    if ([title, sub, ref].some((f) => f.toLowerCase().includes(q)))
      out.push({ group, title, sub, ref, project: p.name, route });
  };
  const rows = readLedger(p.home);
  const open = readQueue(p.home).needs.filter((n) => !n.answer);
  for (const row of rows) {
    const steps = readProgress(p.home, row.item);
    const step = steps.length ? (steps[steps.length - 1]?.text ?? "") : "";
    const status = statusOf(row, open);
    add(
      "Items",
      readBrief(p.home, p.name, row.item)?.title ?? row.item,
      step ? `${status}, ${step}` : status,
      row.item,
      `${base}/progress?item=${enc(row.item)}`,
    );
  }
  for (const n of open)
    add("Needs you", n.title, n.kind, n.id, `${base}/needs?loop=${enc(n.id)}`);
  for (const d of allDecisions(p.home, p.name))
    add(
      "Decisions",
      d.title,
      `${d.item} ${d.id}`,
      d.id,
      `${base}/progress?item=${enc(d.item)}`,
    );
  for (const d of slackDrafts(p.home)) {
    const id = /-slack-(.+)\.md$/.exec(d.name)?.[1] ?? d.name;
    add(
      "Slack",
      (d.reply.split("\n")[0] ?? "").slice(0, 80),
      d.name,
      id,
      `${base}/slack?draft=${enc(d.name)}`,
    );
  }
  for (const b of readBriefings(p.home))
    add("Briefings", b.title, b.id, b.id, `${base}/briefing?id=${enc(b.id)}`);
  let items: string[] = [];
  try {
    items = fs
      .readdirSync(path.join(p.home, "evidence"), { withFileTypes: true })
      .filter((d) => d.isDirectory())
      .map((d) => d.name)
      .sort();
  } catch {
    items = [];
  }
  for (const item of items)
    for (const f of listFiles(path.join(p.home, "evidence", item)))
      add(
        "Evidence",
        path.basename(f),
        `${item}: ${f}`,
        item,
        `${base}/evidence?item=${enc(item)}`,
      );
  return out;
}

export function searchRoutes(router: Router, ctx: Ctx): void {
  router.add("GET", "/api/search", async (req) => {
    const q = (req.query.get("q") ?? "").trim().toLowerCase();
    const all = req.query.get("all") === "1";
    const name = req.query.get("project");
    if (!all && !name)
      throw new HttpError(400, "search needs project=<name> or all=1");
    const projects = all
      ? await ctx.registry.current()
      : [await ctx.registry.find(name ?? "")];
    if (!q) return { json: [] };
    const hits: Hit[] = [];
    for (const p of projects) {
      try {
        hits.push(...searchProject(p, q));
      } catch (err) {
        if (!all) throw err;
        ctx.log(
          `search skipped ${p.name}: ${err instanceof Error ? err.message : String(err)}`,
        );
      }
      if (hits.length >= LIMIT) break;
    }
    return { json: hits.slice(0, LIMIT) };
  });
}
