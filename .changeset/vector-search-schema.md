---
"better-supabase": minor
---

The `vector-search` module no longer assumes pgvector lives in `extensions`. `sql sync` reads the schema from the `create extension ... vector ... schema` statement in your schema files or migrations, and `sql.modules.vector-search.options.schema` sets it explicitly; the default stays `extensions`. The search functions also turn on `hnsw.iterative_scan` in their body and restore the caller's value afterwards, instead of in a `set` clause: a `set` clause for a pgvector setting failed with `permission denied to set parameter "hnsw.iterative_scan"` when a migration created the function in a session that hadn't loaded pgvector yet. The functions are now `plpgsql`.
