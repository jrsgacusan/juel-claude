import { ApiError } from "@/api/client"
export function errorMessage(error: unknown): string {
  if (error instanceof ApiError && error.status === 401)
    return "The dashboard server refused the token. Open the dashboard again with /juel:star dashboard."
  if (error instanceof ApiError) return error.message
  if (error instanceof TypeError) return "The dashboard server did not answer."
  if (error instanceof Error) return error.message
  return String(error)
}
