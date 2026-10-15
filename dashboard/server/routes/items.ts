import type { LedgerRow, NeedItem } from "../../../hooks/star.ts";
import type { Ctx } from "../app.ts";
import { HttpError } from "../http.ts";
import { readBrief } from "../readers/briefs.ts";
import { isPlainName } from "../readers/files.ts";
import { readProgress } from "../readers/progress.ts";
import { readLedger, readQueue } from "../readers/star.ts";
import type { Router } from "../router.ts";

const counterOf = (counters: string, key: string): string | null =>
  new RegExp(`(?:^|\\s)${key}=(\\S+)`).exec(counters)?.[1] ?? null;

export function statusOf(row: LedgerRow, open: readonly NeedItem[]): string {
  if (row.state === "done") return "merged";
  if (row.state === "dropped") return "dropped";
  if (row.state === "escalated" || row.state === "failed") return "stopped";
  const batch = counterOf(row.counters, "batch");
  const named = open.some(
    (n) =>
      n.item === row.item ||
      (n.kind === "go-batch" &&
        ((batch !== null && n.item === batch) ||
          n.body.some((l) => l.trim() === row.item))),
  );
  if (named) return "needs-you";
  if (["inbox", "briefing", "brief-ready"].includes(row.state))
    return "briefing";
  if (["building", "posting", "post-queued", "reported"].includes(row.state))
    return "building";
  if (["babysit-queued", "babysitting", "verifying"].includes(row.state))
    return "in-review";
  return "queued";
}

export function itemOf(
  home: string,
  project: string,
  row: LedgerRow,
  open: readonly NeedItem[],
): Record<string, unknown> {
  const steps = readProgress(home, row.item);
  return {
    ...row,
    title: readBrief(home, project, row.item)?.title ?? null,
    status: statusOf(row, open),
    step: steps.length ? (steps[steps.length - 1]?.text ?? null) : null,
    prUrl: /^https?:\/\//.test(row.pr) ? row.pr : null,
  };
}

export const openNeeds = (home: string): NeedItem[] =>
  readQueue(home).needs.filter((n) => !n.answer);

export function itemRoutes(router: Router, ctx: Ctx): void {
  router.add("GET", "/api/projects/:p/items", async (req) => {
    const p = await ctx.registry.find(req.params["p"] ?? "");
    const rows = readLedger(p.home);
    const open = openNeeds(p.home);
    return { json: rows.map((r) => itemOf(p.home, p.name, r, open)) };
  });
  router.add("GET", "/api/projects/:p/items/:item", async (req) => {
    const p = await ctx.registry.find(req.params["p"] ?? "");
    const name = req.params["item"] ?? "";
    if (!isPlainName(name))
      throw new HttpError(400, `${name} is not an item name`);
    const row = readLedger(p.home).find((r) => r.item === name);
    if (!row) throw new HttpError(404, `no item ${name} in ${p.name}`);
    const brief = readBrief(p.home, p.name, name);
    return {
      json: {
        row: itemOf(p.home, p.name, row, openNeeds(p.home)),
        progress: readProgress(p.home, name),
        criteria: brief?.criteria ?? [],
        decisions: brief?.decisions ?? [],
      },
    };
  });
}
