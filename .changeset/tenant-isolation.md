---
'better-supabase': minor
---

Tenant isolation testing.

- `expectTenantIsolation(sb, { tenants, tables, stack?, seed? })` in `better-supabase/testing` seeds one row per tenant through the service role and asserts that a user of each tenant can't select, insert, update or delete the other's rows. It runs without plugins, checks each user can read its own row, and throws a `ConformanceError` naming every leaking table and command.
- `LocalStack.secretKey` (defaults to `$SUPABASE_SECRET_KEY`).
- Doctor BS107 (warning): a tenant-scoped table has policies for some commands but not all four.
