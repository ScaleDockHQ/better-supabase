---
"better-supabase": patch
---

BS386 and BS206 say that a select policy on a table's own rows keeps the per-row call as the `or` fallback after a set helper, since the set misses a row the statement inserts and `insert ... returning` fails.
