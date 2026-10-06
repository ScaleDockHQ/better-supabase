---
"better-supabase": minor
---

Relation names no longer end in `_` when two foreign keys to one table get the same `_by_` suffix, such as `(customer_id)` and the tenant-safe `(customer_id, organization_id)`. Those relations are now named by every key column (`customerByCustomer` and `customerByCustomerOrganization`), then by the constraint name, and only then get a trailing `_`. Names that did not collide are unchanged. A relation that was called `customerByCustomer_` gets its new name after `better-supabase gen`; keep the old one with `tables.<table>.relations` in the config if you need it.
