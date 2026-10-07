---
"better-supabase": patch
---

`organization.purged` is written without a tenant partition, since the tenant row no longer exists when the purge ends; the organization's id stays in the event's `organizationId`.
