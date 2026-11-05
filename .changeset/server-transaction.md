---
"better-supabase": minor
---

`server.transaction(userId, fn, options)` runs repositories and blocks as a user in one Postgres transaction. A throw rolls back, and so does a returned `Result` that is not ok. A nested transaction on a direct Postgres client now runs in a savepoint instead of being flattened, so one failed step no longer aborts the others. `BetterPostgres.transactionFor` is the optional hook behind it.
