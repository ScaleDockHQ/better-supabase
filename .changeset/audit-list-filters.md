---
"better-supabase": minor
---

The audit log lists with more filters. `createAuditLog().list()` and `export()` take one value or a list for `organizationId`, `eventType`, `actorId`, `targetType` and `record`, new `category` and `outcome` filters, a case-insensitive `search` over the event type, summary, labels, record and table, and `order: "asc"`; `list({ count: true })` adds `page.total`. In SQL, `list_audit_events` takes array filters (`for_tenants`, `for_event_types`, `for_actors`, `for_target_types`, `for_records`, `for_categories`, `for_outcomes`), `search`, `cursor_at`, `cursor_id` and `ascending`, replacing the single-value parameters and `before_at`/`before_id`, and the new `count_audit_events` counts what the filters match. Code that calls `list_audit_events` directly passes the new argument names.
