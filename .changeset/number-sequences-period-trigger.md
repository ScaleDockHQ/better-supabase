---
"better-supabase": minor
---

`sql sync` now keeps `number-sequences` counters in step when a tenant changes its period. For an entity with `table`, `column` and `periodColumn` that sets `periodFrom`, or `formatFrom` with `period: "format"`, it adds an `after update` trigger, `bs_sync_number_period_<entity>`, to each tenant table those columns name. When an update changes the tenant's effective period, the trigger runs `sync_number_sequences(tenant, entity)` in the same transaction, so no number repeats; other updates leave the counters alone. It compares the old and new rows through the new `number_period_kind(period, format)`, so a generated column works too. Without `periodColumn` no trigger is added, as sync cannot run for such an entity. Drop a hand-written trigger that called sync on a period change.
