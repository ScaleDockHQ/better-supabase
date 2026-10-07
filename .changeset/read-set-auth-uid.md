---
"better-supabase": minor
---

Read sets can filter by the caller's id without a parameter. The `defineReadSet` builder takes a third argument, `auth` (the new `ReadSetAuth` type), and `auth.uid` goes wherever a `uuid` value does: `s.customers.count({ where: { createdBy: auth.uid } })`. The generated function compiles it to `(select auth.uid())`, so a caller can't pass someone else's id. Over `better-supabase/postgres` and on executors without RPC, `$many` binds the `sub` claim of the connection's `claims`, and returns `invalid_request` when there is none. `auth.uid` can't go in an `in` list.
