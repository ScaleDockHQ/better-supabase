---
"better-supabase": patch
---

The ledger upgrade from version 1 no longer fails with `LEDGER_APPEND_ONLY` on a database that has
ledger entries: the step that copies `effective_at` from each transaction turns the append-only
trigger off for that one statement and back on in the same block.
