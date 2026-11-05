---
"better-supabase": minor
---

`bsb.withContext(factory)` accepts an async factory: each call awaits it, and concurrent calls on one context share a single run. `blocks.sessions.options.bootstrap` entries take `tables` (and a `{ function, tables?, subject? }` form), and `gen` records them in `meta.bootstrap.tables`, deriving them from the function body when an entry doesn't declare them. `bsb.bootstrap({ rpc })` tags its cache entry with those tables, so `bsb:<table>@<tenant>` invalidation reaches payload RPCs. The snapshot gains `extras.functionSources`. The Next.js docs now say which cache scopes tags invalidate.
