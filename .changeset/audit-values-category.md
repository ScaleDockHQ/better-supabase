---
"better-supabase": minor
---

`sql.modules.audit.options.values` maps `category` too, so an adopted audit log that names categories its own way (`record` for row changes, say) gets its words on every write, and `list_audit_events` and `createAuditLog` read them back as the module's.
