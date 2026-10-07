---
"better-supabase": minor
---

`createSafeFetch` throws the new `UrlCheckError` (with the original error as `cause`) when `allowUrl` throws, such as a failed DNS lookup in `publicUrl`, instead of `UnsafeUrlError`, so callers can retry a transient failure and treat `UnsafeUrlError` as a refused URL. Code that caught `UnsafeUrlError` for DNS failures now catches `UrlCheckError` as well.
