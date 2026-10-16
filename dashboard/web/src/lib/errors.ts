import { ApiError, NetworkError } from "@/api/client"
export const TOKEN_REFUSED = "The dashboard server refused the token."
export function errorMessage(error: unknown): string {
  if (error instanceof ApiError && error.status === 401)
    return TOKEN_REFUSED
  if (error instanceof ApiError) return error.message
  if (error instanceof NetworkError)
    return "The dashboard server did not answer."
  if (error instanceof Error) return error.message
  return String(error)
}
