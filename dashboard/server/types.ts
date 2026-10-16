// The STAR dashboard's module contract: what dashboard/server/ hands every feature module it loads
// from dashboard/server/modules/<name>/index.ts. Each module keeps its own copy of this text in
// modules/<name>/types.ts.

export type Project = { name: string; repo: string; home: string; terminal: string | null; state: 'running' | 'idle' | 'stopped' }
export type Req = { params: Record<string, string>; query: URLSearchParams; body: unknown }
export type Res = { status?: number; json?: unknown }
export type ModuleApi = {
  route(method: 'GET' | 'POST' | 'PUT' | 'DELETE', path: string, handler: (req: Req) => Promise<Res>): void
  emit(event: { type: string; project?: string; [k: string]: unknown }): void
  projects(): Project[]
  nudge(project: string): Promise<boolean>
  log(line: string): void
}
export function register(api: ModuleApi): void
