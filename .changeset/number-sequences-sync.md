---
"better-supabase": minor
---

The number-sequences block adds `sync_number_sequences(p_tenant, p_entity)`, a service-only function that raises each counter to the highest number its table already holds, per tenant and period, and never lowers one. Run it after seeding (`select better_supabase.sync_number_sequences();` at the end of `supabase/seed.sql`), after an import, or once after adopting tables whose documents already have numbers, so the next number does not collide. It reads the entities that set `table` and `column` and parses each number with the entity's `format`; the period comes from `{yyyy}`, `{yy}` and `{mm}` in the format, or from the new `periodColumn` option.
