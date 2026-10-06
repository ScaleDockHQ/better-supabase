---
"better-supabase": minor
---

The `audit` module maps the vocabulary of an adopted log: `sql.modules.audit.options.values` (adopt mode only, reported by doctor BS314) gives the log's own values for `scope`, `actorKind`, `outcome` and `source` (row changes and `audit_event` calls). Writes store the log's values, and `list_audit_events`, and so `createAuditLog`, reads them back as the module's. `options.tenantLabel` (`schema.table.column`, matched on `options.tenantLabelKey`) fills `tenant_label` without the `organizations` module.
