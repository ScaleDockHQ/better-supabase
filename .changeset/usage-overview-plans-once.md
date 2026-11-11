---
"better-supabase": patch
---

`usage_overview` reads the tenant's plans and entitlements once per call instead of once per quota row. Run `better-supabase upgrade` and generate a migration.
