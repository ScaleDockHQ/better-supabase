---
"better-supabase": minor
---

`number-sequences` entities take `periodFrom: { column, key? }`, the column that holds each tenant's reset period (`none`, `year`, `month` or `format`), so a tenant can keep a format such as `INV-{yyyy}{mm}-{n}` and still number on through the year. A null or empty value falls back to the entity's `period`, so `period: "format"` keeps deriving the period from the format; any other value fails with `NUMBER_PERIOD_INVALID`. `number_period(tenant, entity)` returns a tenant's choice. `next_number`, `preview_number` and `sync_number_sequences` use the same period, and sync needs `periodColumn` for such an entity.
