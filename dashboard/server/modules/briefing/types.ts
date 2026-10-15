// The dashboard's module contract, copied from the server item ("Module contract" in
// star-dashboard-server.md, brief D1). dashboard/server/types.ts holds the same text: change both
// together. Only ever imported with `import type`.
export type Project = { name: string; repo: string; home: string; terminal: string | null; state: 'running' | 'idle' | 'stopped' }
export type Req = { params: Record<string, string>; query: URLSearchParams; body: unknown }
export type Res = { status?: number; json?: unknown }
export type ModuleApi = {
  route(method: 'GET' | 'POST' | 'PUT', path: string, handler: (req: Req) => Promise<Res>): void
  emit(event: { type: string; project?: string; [k: string]: unknown }): void
  projects(): Project[]
  nudge(project: string): Promise<boolean>
  log(line: string): void
}
export function register(api: ModuleApi): void
