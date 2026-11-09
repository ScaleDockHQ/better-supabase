---
"better-supabase": minor
---

An import target can name `naturalKey`, a function `(tenant, item jsonb) returns text`. When no import record exists and the function returns a subject, the write updates that row instead of inserting another.
