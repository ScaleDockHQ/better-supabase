---
"better-supabase": minor
---

Numbering now supports imports and legal entities. Counters are kept per tenant, entity, legal
entity scope and period, and `series: "none"` lets credit notes share the invoice series. During an
import run, `issue_invoice` and `credit_invoice` take a historical `fixed_number`, other entities
take `set_fixed_number(entity, number)`, and the counters continue above the imported numbers.
`sync_number_sequences(tenant, entity, scope)` now returns `{ synced, mismatched }` and lists numbers
outside the current format as import run warnings, without rejecting them. `next_number` and
`preview_number` gain a trailing `p_scope` argument with a default. Run `better-supabase upgrade`
and apply the new migration. On an app's own sequences table it replaces the key with one over
tenant, entity, scope and period.
