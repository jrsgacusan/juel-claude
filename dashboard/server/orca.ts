import { lastLine, run } from "./proc.ts";

export type Terminals =
  | { ok: true; handles: Set<string> }
  | { ok: false; why: string };

/** The handles `orca terminal list` shows (result.terminals[].handle), or why it could not be read. */
export async function listTerminals(): Promise<Terminals> {
  const r = await run("orca", ["terminal", "list", "--limit", "500", "--json"]);
  if (r.code !== 0) {
    return {
      ok: false,
      why: `exit ${r.code}: ${lastLine(r.stderr) || lastLine(r.stdout)}`,
    };
  }
  try {
    const data = JSON.parse(r.stdout) as {
      result?: { terminals?: { handle?: unknown }[] };
    };
    const list = data.result?.terminals;
    if (!Array.isArray(list)) {
      return { ok: false, why: "its output had no terminal list" };
    }
    return {
      ok: true,
      handles: new Set(
        list
          .map((t) => t.handle)
          .filter((h): h is string => typeof h === "string"),
      ),
    };
  } catch {
    return { ok: false, why: "its output had no terminal list" };
  }
}

/**
 * Wake STAR with `inbox` through `orca terminal send`, as a hand-over does (the band's
 * prompt.submit works only inside STAR's own session). True only when Orca took it; a terminal
 * Orca does not list, or none, is false without sending.
 */
export async function nudge(
  terminal: string | null,
  log: (line: string) => void = () => {},
): Promise<boolean> {
  if (!terminal) return false;
  const listed = await listTerminals();
  if (!listed.ok) {
    log(`nudge: orca terminal list failed (${listed.why})`);
    return false;
  }
  if (!listed.handles.has(terminal)) return false;
  const r = await run("orca", [
    "terminal",
    "send",
    "--terminal",
    terminal,
    "--text",
    "inbox",
    "--enter",
    "--json",
  ]);
  if (r.code !== 0) {
    log(
      `nudge ${terminal}: orca terminal send exit ${r.code}: ${lastLine(r.stderr)}`,
    );
    return false;
  }
  return true;
}
