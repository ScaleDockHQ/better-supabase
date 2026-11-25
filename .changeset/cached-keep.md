---
"better-supabase": minor
---

`bsb.cached({ keep: { name } })` keeps the reads of `ctx.db` in the kept store, per user and table, so a cold page or a new instance answers them without calling the database, and parallel renders share one fill. `bsb.bootstrap({ rpc, kept: true })` keeps the wrapper's answer the same way. `db.$wrapExecutor(wrap)` puts a wrapper around a client's executor, outside the plugins and the call counts.
