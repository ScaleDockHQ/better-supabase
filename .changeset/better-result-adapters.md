---
'better-supabase': minor
---

Add `sb.mapError(fn)`, so `.orThrow()` throws your own error while results keep their `DbError`. Add `toBetterResult(result, Result, mapError?)` and `fromBetterResult(r)` to convert to and from better-result values without depending on it. Errors whose `cause` is a `DbError` are now recognised by the server, Hono and oRPC adapters and by `isConflict`, `isCheck` and `isForeignKey`. TanStack Query hooks keep throwing `DbException`.
