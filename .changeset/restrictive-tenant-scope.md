---
"better-supabase": minor
---

In `tenant` scope, every block table a client can reach and every tenant
table in `tables` gets a restrictive `bsb_tenant_scope` policy. It keeps rows
to the caller's organizations and to what the block's own policies grant, so
a permissive policy the app adds, even `using (true)`, can no longer read or
write another organization's rows. Run `better-supabase upgrade` and generate
a migration to apply it.
