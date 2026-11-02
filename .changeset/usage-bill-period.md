---
"better-supabase": minor
---

The `usage` block turns its history into invoices. With `options.history` and the `invoices` block,
`usage.setPrice` stores a unit price and an included quantity per meter and currency, and
`usage.billPeriod({ organizationId, periodStart, periodEnd })` rates the period's usage into one
draft invoice, once per tenant and period. The module adds the `usage_meter_prices` and
`usage_billed_periods` tables and the service-only functions `set_usage_price` and
`bill_usage_period`, so run `better-supabase upgrade` to regenerate it.
