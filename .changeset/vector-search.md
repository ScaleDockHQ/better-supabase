---
'better-supabase': minor
---

Add vector search. The `vector-search` SQL kit module writes a security invoker `search_<table>(query, k)` function for each table in the new `vectorSearch` config key, using pgvector's iterative HNSW scans so RLS filters still return `k` rows. `db.$search(table, { vector, k, select, include, where })` reads through it with the usual selection, filters and casing. Executors opt in with `Executor.functionSources`, and read from the new `SelectOp.source`. `SPEC_PINS.pgvector` pins pgvector 0.8.
