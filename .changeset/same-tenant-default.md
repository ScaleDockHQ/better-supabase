---
"better-supabase": minor
---

`blocks.memberships.options.sameTenant` defaults to the foreign keys the schema files declare, so `upgrade` writes a `bsb_same_tenant_<column>` trigger for every single-column key between two tenant tables without a config entry. A composite key that pairs the column with the tenant column also counts as covering it. A list now adds entries to the derived ones, and `sameTenant: false` writes none. This replaces the `sameTenant: { auto: true }` line in app configs.
