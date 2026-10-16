import { createAccounts } from './accounts.ts'
import type { ModuleApi } from './types.ts'

export function register(api: ModuleApi): void {
  createAccounts(api).start()
}
