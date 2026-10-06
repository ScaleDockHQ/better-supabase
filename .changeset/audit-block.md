---
"better-supabase": minor
---

The `audit` module adds `list_audit_events`, which lists the entries the caller can read, and `reveal_audit_entry`, which returns an entry's restricted details and records it as `audit.revealed`. The `audit` module, now at version 3, records `actor_kind`, `actor_label`, `tenant_label`, `target_label` (`audit(..., label_column)`), `summary`, `request_id`, `correlation_id` and `scope`, keeps the session id and per-column changes in the restricted table, and adds `audit_schema_calls` and `audit_schema` to register a schema's tenant tables. Adopted logs write the new columns they map. Run `better-supabase sql upgrade`.

Reading the user agent no longer fails on a connection where an earlier transaction set `request.headers`.
