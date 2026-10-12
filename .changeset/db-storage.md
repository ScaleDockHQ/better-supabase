---
"better-supabase": minor
---

A `Db` carries Storage as the same caller: `db.$storage` is the new `storage` option of `connect(client, context, { storage })`, or the client's `storage`, and it throws on a connection with neither. `bucket.connect(db.$storage)` and blocks given `db.$storage` then follow whatever the `Db` runs as. In a support session, `ctx.db.$storage` and `ctx.sql.$storage` are `ctx.storage`, which is now typed `StorageApi`, so the same code reads Storage as the caller in a normal request and as the target in a support session.
