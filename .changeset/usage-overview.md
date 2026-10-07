---
"better-supabase": minor
---

`usage.overview(organizationId)` returns the status of every meter of a tenant in one request, sorted by meter: the catalog's meters, the meters a quota applies to and the meters the tenant has used. It calls the new `usage_overview(tenant)` SQL function, so a usage page no longer needs one `current()` call per meter.
