---
"better-supabase": minor
---

Add `better-supabase/create/lite`. `validateDesign(files)` applies the files Create generates to an in-memory PGlite database through `@supabase/lite` and reports what Postgres rejects. Modules that need `pgmq` or `btree_gist` are reported as skipped.
