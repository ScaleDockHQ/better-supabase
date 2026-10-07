---
"better-supabase": patch
---

`StripeTaxId` has the optional `created` field (epoch seconds), and `billing.taxIds(organizationId, { from: "sync" })` returns the `created` value that `billing_tax_ids` reports instead of dropping it, or `null` when the synced row has none. `billing_tax_ids` also reads `created` from `_raw_data` when the Sync Engine keeps it there.
