---
"@better-supabase/cli": minor
"better-supabase": minor
---

Doctor treats `security definer` functions and functions with a `set` option as not inlinable (BS205, BS206), and its advice for them now points to `column in (select helper())`. New checks: `auth.role()` (BS109), update policies without a select policy or `with check` (BS110), needless and unused API grants (BS111), exposed security definer functions that never check the caller (BS112), storage inserts without the upsert policies (BS113), helpers that read `user_metadata` (BS114), zero-argument helpers called without `select` (BS215), foreign keys without an index (BS216, replacing splinter's lint for the same table), tenant foreign keys that can cross tenants (BS217), soft-delete tables without a partial index (BS218), containment filters without GIN (BS219), column types to avoid (BS220) and direct connections in serverless apps (BS221). BS211 also reports `idle_in_transaction_session_timeout`.

Snapshots now record each index's access method and predicate, and who among `anon` and `authenticated` may execute the functions doctor reads. Both fields are optional in `snapshot-v2.json`, so older snapshots still load.
