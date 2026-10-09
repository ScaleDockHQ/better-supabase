---
"better-supabase": minor
---

`createAuditLog({ transport })` in `better-supabase/blocks/audit` lists, reveals and exports the audit log as the caller, and entries record who acted, from where and on what. Run `better-supabase sql upgrade`.

- `list` (`list_audit_events`) filters by tenant, event type, actor, target, record, category, outcome, source and correlation id, with `search`, a cursor or `offset`, and `count: true`. `reveal(entryId)` returns restricted details and records `audit.revealed`.
- `export({ format: "ndjson" | "csv" | "ocsf" })` streams the log (CSV takes `columns`, `preamble` and `formatRow`), `exportToStorage` writes it to a bucket, and `record(event)` calls `audit_event`.
- Entries record actor kind and label, tenant and target labels, `summary`, `request_id`, `correlation_id` and `scope`. Actor and request details are honoured only from the service role and admin connections; `audit_event_trusted` serves an app's `security definer` functions and `options.trustedRoles`.
- `better_supabase.audit(...)` keeps a table's settings on its trigger, so schema files need no data rows, and `bs_audit_forget_dropped` clears registrations of dropped tables. Adopted logs map their own values with `options.values`, `tenantLabel` and `metadataColumns`.
- `sql add` writes a pgTAP file per audited table. Doctor BS315 reports tables without an audit trigger and BS322 registrations of missing tables.
