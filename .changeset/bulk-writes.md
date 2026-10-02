---
"better-supabase": minor
---

On the Postgres executor, `createMany` and `upsertMany` split an insert that needs more than 65,535 bind parameters into several statements and run them in one transaction, instead of failing. `upsertMany` sends rows sorted by the conflict columns, so concurrent upserts over overlapping rows lock them in the same order instead of deadlocking; its returned rows follow that order.
