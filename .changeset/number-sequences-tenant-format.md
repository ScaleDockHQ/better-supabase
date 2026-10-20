---
"better-supabase": minor
---

`number-sequences` numbers each tenant in its own format. `formatFrom: { column: "schema.table.column", key }` reads a tenant's format from a settings column and falls back to the entity's `format`; a tenant format without `{n}` fails with `NUMBER_FORMAT_INVALID`. The new `period: "format"` restarts the counter by the format's tokens: monthly with a year and `{mm}`, yearly with only a year, never without either, so one tenant can number continuously and another per year. `sequenceColumn` also stores the bare number next to the formatted one. `sync_number_sequences` reads per-tenant formats and sequence columns, and the orders, invoices, quotes, deals and work-items modules use the tenant's format when they number through the block.
