---
"better-supabase": minor
---

Vector search gains text-only hybrid search, predicates and ordering. On a `hybrid` entry, `db.$search` takes `text` without `vector` (or with `vector: null`) and ranks by full-text alone, so search keeps working when the embedding call fails. A `vectorSearch` entry takes `predicate` (a SQL condition over the row `t`, applied before ranking, for ranges and related rows), `boostMode: "add"` for an additive boost, and `order` (a SQL order list over `t` that breaks score ties).
