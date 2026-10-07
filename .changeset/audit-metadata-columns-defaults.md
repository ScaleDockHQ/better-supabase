---
"better-supabase": minor
---

`sql.modules.audit.options.metadataColumns` no longer writes `null` into an adopted column when the event's metadata leaves the key out: `audit_event` names only the mapped columns whose key is present, so the column's default applies and a `not null default` column accepts events without it. The mapped keys are removed from the stored metadata; set `keepMappedMetadata: true` to keep them there too. `list_audit_events` returns the mapped columns under `columns`, and `createAuditLog<Columns>()` types them on `AuditRecord.columns` for `list` and `export`.
