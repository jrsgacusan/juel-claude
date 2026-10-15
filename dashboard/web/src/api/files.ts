import { useQuery } from "@tanstack/react-query"
import { apiFetch } from "./client"
import { keys } from "./queries"
import type { FileKind } from "./types"
type FileData = { url: string | null; text: string | null }
export function useFileBlob(url: string | null, kind: FileKind) {
  const query = useQuery({
    queryKey: keys.file(url ?? ""),
    enabled: url !== null,
    staleTime: Infinity,
    queryFn: async (): Promise<FileData> => {
      const res = await apiFetch(url ?? "")
      if (kind === "text") return { url: null, text: await res.text() }
      return { url: URL.createObjectURL(await res.blob()), text: null }
    },
  })
  return {
    url: query.data?.url ?? null,
    text: query.data?.text ?? null,
    isLoading: query.isLoading,
    error: query.error,
  }
}
