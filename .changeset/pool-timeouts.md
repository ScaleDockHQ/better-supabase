---
"better-supabase": minor
---

`createPostgres` applies Supabase's role timeouts per transaction: `statement_timeout` 8 s for `asUser` and 3 s for `anon`, because `set role` skips the role's own setting. `statementTimeout` takes a number for every role or one value per role (`admin`, `authenticated`, `anon`). New options: `idleInTransactionTimeout`, `connectionTimeout` and `idleTimeout` (both default to 10 s). Each transaction now sets its timeouts, claims and role in one query after `begin`.
