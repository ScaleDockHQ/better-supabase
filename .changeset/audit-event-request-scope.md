---
"better-supabase": minor
---

`audit_event` takes `request_id` and `scope`, and `createAuditLog()` gains `record(event)`. A job or API route that records an event as the service role can pass the request id it handled and an explicit scope (an adopted log's own value, or `tenant` and `platform`); other callers keep the request's `x-request-id` header and the scope derived from the tenant. `sql.modules.audit.options.metadataColumns` fills an adopted log's own columns from keys of the event's metadata, converted to each column's type. `audit.record` calls `audit_event` with every argument and returns the entry id.
