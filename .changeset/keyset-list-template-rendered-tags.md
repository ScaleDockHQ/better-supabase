---
"better-supabase": minor
---

The list functions of the risks, meetings, inspections and warranty blocks page by keyset. Pass `after` (the previous `nextCursor`) with `{ paged: true }` to get `{ items, hasMore, nextCursor }`, and `{ total: true }` for a total capped at `totalCap` (default 10,000). `offset` stays as an explicit option for callers that show page numbers, and a plain call still returns the array. `risks.page()` is the typed client, and each table gets a list index that ends in the id. Run `better-supabase upgrade` and `db diff` to write the new indexes.

The `access`, `list` and `idempotency` table tags render policies, a keyset list function with its indexes, and a unique index for retried writes: `better-supabase table <name> enable <tag>` reads the tag's arguments from the table comment. The authorization provider gains an optional `functions.canIn` template for the policies; without it the tag calls `better_supabase.tenant_ids_with`, so existing providers keep working and `apiVersion` stays 1.
