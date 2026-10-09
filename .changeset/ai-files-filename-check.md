---
"better-supabase": patch
---

The `ai-files` SQL module writes its filename length check as two comparisons instead of `between`, so `supabase db schema declarative sync` stops writing the same constraint into every new migration.
