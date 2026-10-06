---
"better-supabase": minor
---

New `better-supabase/blocks/audit`: `createAuditLog` lists audit entries the caller can read, reveals an entry's restricted details (recorded as `audit.revealed`) and exports a tenant's entries as CSV to Storage with a signed URL; `purgeAuditLog` is exported there too. The `audit` module, now at version 3, records `actor_kind`, `actor_label`, `tenant_label`, `target_label` (`audit(..., label_column)`), `summary`, `request_id`, `correlation_id` and `scope`, keeps the session id and per-column changes in the restricted table, and adds `audit_schema_calls` and `audit_schema` to register a schema's tenant tables. Adopted logs write the new columns they map. Run `better-supabase sql upgrade`.

Reading the user agent no longer fails on a connection where an earlier transaction set `request.headers`.
