---
"better-supabase": minor
---

`dbTransport(db, { schema })` from `better-supabase/blocks` (and every block entry) calls block functions through a `Db`'s executor, so a block follows whatever the `Db` runs over: the Data API for `ctx.db` in a normal request, and direct Postgres as the target user in a support session or for an API key. It rejects with the raw database error like `rpcTransport` and `sqlTransport`, so block error mappers see the same codes and hints, and a `DbError` that a transport rejects with now passes through block calls unchanged.
