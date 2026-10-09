---
"better-supabase": minor
---

Vector search supports hybrid ranking, filters and scores. Run `better-supabase sql sync`.

- `vectorSearch` entries take `type: "halfvec"`, `hybrid`, `boost`, `prefilter`, `predicate` and `order`.
- `db.$search` takes `filter`, `text` and `score: true`; on a `hybrid` entry `text` alone ranks by full text when the embedding call fails.
- `options.schema` sets pgvector's schema, which `sql sync` otherwise reads from your `create extension` statement.
