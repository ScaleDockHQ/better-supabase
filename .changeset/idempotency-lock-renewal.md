---
"better-supabase": minor
---

`createIdempotency().handle` now renews the key's lock at half its length while the handler runs, so a handler slower than `lock` keeps its key instead of losing it to a retry. The new `extend(key, holder, scope)` does the same for callers of the lower-level protocol. Rerun `better-supabase sql sync` and generate a migration to add `better_supabase.extend_idempotent`.
