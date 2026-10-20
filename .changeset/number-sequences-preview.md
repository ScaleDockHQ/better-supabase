---
"better-supabase": minor
---

`number-sequences` adds `preview_number(tenant, entity, at)` and `createNumberSequences().preview()`: the formatted number the next document would get, in the tenant's format and period, without assigning it. Signed-in users may call it when they hold the block's `assign` permission (`blocks.number-sequences.permissions.assign`, default `number_sequences.assign`), which until now no function checked; others get `NUMBER_FORBIDDEN`. `next_number` stays service-only, and documents keep getting their numbers from the trigger.
