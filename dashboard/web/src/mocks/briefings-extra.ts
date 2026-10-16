import type { HttpHandler } from "msw/http"

// Routes added here: DELETE /api/projects/:p/briefings/:id, and deletable on the list.
export const briefingsExtraHandlers: HttpHandler[] = []
