---
"better-supabase": minor
---

`approval_eligible_ids` now answers for every pending request in one query. Users, roles, teams, managers and delegations are joins, and each permission is checked once per tenant and permission pair instead of once per request, so a list policy no longer scales with the number of pending requests. Only an access provider's `isApprover` still runs per request. On PGlite with 10 tenants, 54 pending requests take 2.5 ms (11.5 ms before) and 5,000 take 12 ms (920 ms before). Module version 5, no migration step.
