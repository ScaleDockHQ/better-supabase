---
"better-supabase": minor
---

The `audit` SQL kit module can adopt an existing audit table (`kits.audit.tables` and `columns`), and `audit()` takes `redact`, `category`, `event_prefix`, `target_type` and `tenant_column`. The new `audit_event` function records events that are not row changes, with an idempotency key. The options `appendOnly`, `readPolicy`, `impersonators`, `restricted`, `eventRoles`, `eventCategory` and `eventSource` add an append-only guard, a tenant read policy, hidden impersonation columns and a separate table for sensitive details. `purge_audit_log` honours an `audit_retention(tenant)` SQL hook, and `purgeAuditLog` from `better-supabase/jobs` takes a per-tenant retention callback. Run `better-supabase sql upgrade` to move from version 1.
