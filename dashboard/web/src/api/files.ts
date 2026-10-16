import { useQuery } from "@tanstack/react-query"
import { apiFetch } from "./client"
import { keys } from "./queries"
import type { FileKind } from "./types"
type FileData = { url: string | null; text: string | null }
// An <img> or <video> cannot send X-Star-Token (spec D12), so files are fetched with apiFetch;
// the object URL is revoked when its query is dropped from the cache (createQueryClient).
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
    refetch: query.refetch,
  }
}
