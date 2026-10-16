import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { test } from "node:test";

// The module contract: every module under modules/ keeps its own copy of this exact text.
const CONTRACT = [
  "export type Project = { name: string; repo: string; home: string; terminal: string | null; state: 'running' | 'idle' | 'stopped' }",
  "export type Req = { params: Record<string, string>; query: URLSearchParams; body: unknown }",
  "export type Res = { status?: number; json?: unknown }",
  "export type ModuleApi = {",
  "  route(method: 'GET' | 'POST' | 'PUT' | 'DELETE', path: string, handler: (req: Req) => Promise<Res>): void",
  "  emit(event: { type: string; project?: string; [k: string]: unknown }): void",
  "  projects(): Project[]",
  "  nudge(project: string): Promise<boolean>",
  "  log(line: string): void",
  "}",
  "export function register(api: ModuleApi): void",
].join("\n");

test("types.ts holds the module contract exactly", () => {
  const text = fs.readFileSync(
    path.join(import.meta.dirname, "..", "types.ts"),
    "utf8",
  );
  assert.ok(text.includes(CONTRACT), text);
});

test("each module's copy holds the same contract", () => {
  for (const name of ["briefing"]) {
    const text = fs.readFileSync(
      path.join(import.meta.dirname, "..", "modules", name, "types.ts"),
      "utf8",
    );
    assert.ok(text.includes(CONTRACT), `${name}: ${text}`);
  }
});
