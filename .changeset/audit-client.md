---
"better-supabase": minor
---

`createAuditLog({ transport })` reads the audit log through the module's functions as the caller: `list` (`list_audit_events`, with tenant, event, actor, target, record and time filters and a cursor), `reveal(entryId)` (`reveal_audit_entry`, recorded as `audit.revealed`), `export({ format: "ndjson" | "csv" | "ocsf" })` as a stream, and `exportToStorage` for background exports to a bucket with a signed URL. It honours an adopted log's column mappings and the version 3 columns, and works over `sqlTransport` or `rpcTransport` with an API schema. The audit subpath now also exports `sqlTransport` and `rpcTransport`, and the docs run `auditListQuery` on `ctx.sql`.
