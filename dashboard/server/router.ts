import type { Req, Res } from "./types.ts";

export type Method = "GET" | "POST" | "PUT";
/** A core route may also answer with a file to stream; a module's answer is plain Res. */
export type CoreRes = Res & {
  file?: { path: string; rel: string; size: number; type: string };
};
export type Handler = (req: Req) => Promise<CoreRes>;
type Route = { method: Method; parts: string[]; handler: Handler };

const split = (p: string): string[] => p.split("/").filter(Boolean);

/** Routes with `:name` params, matched in the order they were added. */
export class Router {
  routes: Route[] = [];

  add(method: Method, path: string, handler: Handler): void {
    this.routes.push({ method, parts: split(path), handler });
  }

  /** The handler and params; 'method' when the path exists only under another method; undefined when no route has it. */
  match(
    method: string,
    pathname: string,
  ):
    | { handler: Handler; params: Record<string, string> }
    | "method"
    | undefined {
    const parts = split(pathname);
    let other = false;
    for (const r of this.routes) {
      const params = paramsOf(r.parts, parts);
      if (!params) continue;
      if (r.method === method) return { handler: r.handler, params };
      other = true;
    }
    return other ? "method" : undefined;
  }
}

function paramsOf(
  pattern: readonly string[],
  parts: readonly string[],
): Record<string, string> | undefined {
  if (pattern.length !== parts.length) return undefined;
  const params: Record<string, string> = {};
  for (let i = 0; i < pattern.length; i += 1) {
    const want = pattern[i] ?? "";
    const got = parts[i] ?? "";
    if (want.startsWith(":")) {
      try {
        params[want.slice(1)] = decodeURIComponent(got);
      } catch {
        return undefined;
      }
    } else if (want !== got) {
      return undefined;
    }
  }
  return params;
}
